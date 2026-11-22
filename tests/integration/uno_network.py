#!/usr/bin/env python3
"""Public table + three private clients: consent/download, recovery and full UNO game."""
from contextlib import ExitStack
import json
from pathlib import Path
import sys
import shutil
import socket
import tempfile
import uuid
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / p) for p in ['tools/build', 'tools/dev', 'tests/support', 'tests/integration', 'tests/devices']]

from client_ui_hot import shell
from debug_integration import submit
from integration import ROOT, free_port
from game_link import GameLink
from nvctl import RPCError, push
from pack_mod import pack
from player_integration import wait_for


def state(client):
    return client.call('game.snapshot')


def run():
    with tempfile.TemporaryDirectory(prefix='nv-uno-network-') as folder, ExitStack() as stack:
        folder = Path(folder)
        source = folder/'mod'; shutil.copytree(ROOT/'mods/uno', source)
        manifest = json.loads((source/'manifest.json').read_text())
        game = 'uno_probe_' + uuid.uuid4().hex[:10]
        manifest['id'] = game
        (source/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False))
        package = folder/'uno.zip'; pack(source, package, hot=True)
        table, _ = stack.enter_context(shell(folder/'table'))
        phones = [stack.enter_context(shell(folder/('phone'+str(i))))[0] for i in range(3)]
        clients = [table, *phones]
        build = push(table, package); table.call('mods.activate', {'build': build['build']})
        port = free_port()
        assert table.room('room.create', {'game_id': game, 'port': port, 'role': 'spectator'})['started']
        sid = state(table)['game_session_id']
        link = stack.enter_context(GameLink('127.0.0.1', port))
        for index, phone in enumerate(phones):
            phone.call('lan.inspect', {'address': '127.0.0.1', 'port': link.port if index == 2 else port, 'session_id': sid})
            wait_for(lambda: phone.call('lan.status')['confirmation'])
            assert phone.call('lan.status')['received'] == 0
            phone.call('lan.confirm_download')
            wait_for(lambda: phone.call('lan.status')['role_prompt'], timeout=20)
            assert phone.call('lan.choose_role', {'role': 'player'})['joining']
            wait_for(lambda: state(phone).get('in_room'), timeout=20)
        wait_for(lambda: len(state(table)['players']) == 3)
        if phones[0].call('lan.status')['backend'] != 'unavailable':
            phones[0].call('lan.search')
            wait_for(lambda: any(r['session_id'] == sid for r in phones[0].call('lan.status')['rooms']))
        try:
            phones[0].room('room.start_round')
        except RPCError as error:
            assert str(error) == 'host_only'
        else:
            raise AssertionError('guest started the round')
        assert table.room('room.start_round')['started']
        wait_for(lambda: all(state(c)['view']['phase'] == 'playing' for c in clients))
        assert state(table)['role'] == 'spectator' and 'seat' not in state(table)
        assert not {'hand', 'drawn', 'deck', 'seed'} & state(table)['view'].keys()
        seen = []
        for phone in phones:
            snapshot = state(phone)
            assert len(snapshot['view']['hand']) == 7
            assert not {'hands', 'deck', 'seed', 'shuffles'} & snapshot['view'].keys()
            assert not any(card in seen for card in snapshot['view']['hand'])
            seen.extend(snapshot['view']['hand'])
        assert table.call('game.describe_actions')['legal_actions'] == []
        # Lock player membership but keep the game discoverable for spectators. after start without allocating a new seat.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock, sock.makefile('rb') as lines:
            sock.sendall(b'{"type":"catalog"}\n')
            catalog = json.loads(lines.readline())
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock, sock.makefile('rb') as lines:
            sock.sendall((json.dumps({'type': 'hello', 'protocol': 2, 'rules_fingerprint': catalog['rules_fingerprint'], 'player_id': 'late-'+uuid.uuid4().hex, 'nickname': 'Late'})+'\n').encode())
            response = json.loads(lines.readline())
            assert response['code'] == 'game_in_progress', response
        assert catalog['player_slots'] == 0 and catalog['spectator_slots'] == 4
        watcher, _ = stack.enter_context(shell(folder/'watcher'))
        watcher.call('lan.inspect', {'address': '127.0.0.1', 'port': port, 'session_id': sid})
        # LAN downloads are shared across these desktop test processes; a cached
        # compatible copy may already have been loaded by the new spectator.
        wait_for(lambda: (status := watcher.call('lan.status'))['confirmation'] or status['role_prompt'])
        if watcher.call('lan.status')['confirmation']:
            watcher.call('lan.confirm_download')
        wait_for(lambda: watcher.call('lan.status')['role_prompt'], timeout=20)
        try:
            watcher.call('lan.choose_role', {'role': 'player'})
        except RPCError as error:
            assert str(error) == 'invalid_state'
        else:
            raise AssertionError('late player join was offered')
        assert watcher.call('lan.choose_role', {'role': 'spectator'})['joining']
        wait_for(lambda: state(watcher).get('in_room'))
        assert state(watcher)['view'] == state(table)['view']
        assert len(state(table)['players']) == 3
        watcher.room('room.leave')
        assert not state(table)['view']['paused']
        print('PASS UNO: download consent, seatless host, and a late spectator receives only the public view', flush=True)
        before = state(phones[2])
        link.reject_new.set()
        link.interrupt_existing('close')
        wait_for(lambda: state(table)['view']['paused'])
        wait_for(lambda: state(phones[2]).get('session_state') == 'reconnecting')
        result, _ = submit(phones[0], state(phones[0]), 'paused-draw', {'type': 'draw'})
        assert not result['accepted'] and result['code'] == 'players_disconnected'
        link.reject_new.clear()
        wait_for(lambda: all(not state(c)['view']['paused'] for c in clients) and state(phones[2]).get('session_state') == 'connected')
        after = state(phones[2])
        assert after['game_session_id'] == before['game_session_id'] and after['seat'] == before['seat']
        assert after['local_session_id'] == before['local_session_id']
        assert after['view']['hand'] == before['view']['hand'] and after['view']['turn'] == before['view']['turn']
        print('PASS UNO real game-transport cut: paused actions rejected, authenticated same-seat reconnect preserves hand/turn', flush=True)
        caught = False
        moves = 0
        by_seat = {int(state(c)['seat']): c for c in phones}
        while state(table)['view']['phase'] != 'finished' and moves < 2500:
            authoritative = state(table)
            actor = by_seat[int(authoritative['view']['turn'])]
            wait_for(lambda: state(actor)['revision'] == authoritative['revision'])
            current = state(actor)
            legal = actor.call('game.describe_actions')['legal_actions']
            assert legal, current['view']
            action = next((a for a in legal if a['type'] == 'play'), legal[0])
            missed = not caught and action['type'] == 'play' and len(current['view']['hand']) == 2
            if missed:
                action = dict(action, uno=False)
            result, _ = submit(actor, current, 'uno-'+str(moves), action)
            assert result['accepted'], result
            target_revision = result['revision']
            wait_for(lambda: all(state(c)['revision'] >= target_revision for c in clients))
            moves += 1
            if missed and state(table)['view']['phase'] != 'finished':
                catcher = next(c for seat, c in by_seat.items() if seat != current['seat'])
                result, _ = submit(catcher, state(catcher), 'catch-uno', {'type': 'catch'})
                assert result['accepted'], result
                wait_for(lambda: all(state(c)['revision'] >= result['revision'] for c in clients))
                caught = True
        assert state(table)['view']['phase'] == 'finished', 'game did not finish'
        assert caught
        final = state(table)
        assert 'hand' not in final['view'] and final['view']['winner'] in by_seat
        assert all(state(c)['view']['winner'] == final['view']['winner'] for c in clients)
        for index, phone in enumerate(phones):
            result, _ = submit(phone, state(phone), 'rematch-'+str(index), {'type': 'rematch'})
            assert result['accepted'], result
            wait_for(lambda: all(state(c)['revision'] >= result['revision'] for c in clients))
            if index < 2:
                assert state(table)['view']['phase'] == 'finished'
        assert state(table)['view']['phase'] == 'playing' and state(table)['view']['round'] == 2
        assert state(table)['game_session_id'] == sid
        assert 'hand' not in state(table)['view']
        assert all(len(state(c)['view']['hand']) == 7 for c in phones)
        for client in reversed(clients):
            client.room('room.leave')
        print(f'PASS UNO real TCP game: {moves} actions, missed-call penalty, private hands, winner and unanimous rematch', flush=True)


if __name__ == '__main__':
    run()
