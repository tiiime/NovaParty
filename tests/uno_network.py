#!/usr/bin/env python3
"""Public table + three private clients: consent/download, recovery and full UNO game."""
from contextlib import ExitStack
import json
from pathlib import Path
import shutil
import socket
import tempfile
import uuid
from client_ui_hot import shell
from debug_integration import submit
from integration import ROOT, free_port
from game_link import GameLink
from nvctl import push
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
        table.room('room.create', {'game_id': game, 'port': port})
        sid = state(table)['game_session_id']
        link = stack.enter_context(GameLink('127.0.0.1', port))
        for index, phone in enumerate(phones):
            phone.call('lan.inspect', {'address': '127.0.0.1', 'port': link.port if index == 2 else port, 'session_id': sid})
            wait_for(lambda: phone.call('lan.status')['confirmation'])
            assert phone.call('lan.status')['received'] == 0
            phone.call('lan.confirm_download')
            wait_for(lambda: state(phone).get('in_room'), timeout=20)
        wait_for(lambda: len(state(table)['players']) == 4)
        if phones[0].call('lan.status')['backend'] != 'unavailable':
            phones[0].call('lan.search')
            wait_for(lambda: any(r['session_id'] == sid for r in phones[0].call('lan.status')['rooms']))
        assert table.call('game.describe_actions')['legal_actions'][0]['type'] == 'start'
        receipt, _ = submit(table, state(table), 'start-uno', {'type': 'start'})
        assert receipt['accepted'], receipt
        wait_for(lambda: all(state(c)['view']['phase'] == 'playing' for c in clients))
        assert state(table)['view']['hand'] == []
        seen = []
        for phone in phones:
            snapshot = state(phone)
            assert len(snapshot['view']['hand']) == 7
            assert not {'hands', 'deck', 'seed', 'shuffles'} & snapshot['view'].keys()
            assert not any(card in seen for card in snapshot['view']['hand'])
            seen.extend(snapshot['view']['hand'])
        assert table.call('game.describe_actions')['legal_actions'] == []
        if phones[0].call('lan.status')['backend'] != 'unavailable':
            wait_for(lambda: not any(r['session_id'] == sid for r in phones[0].call('lan.status')['rooms']))
        # Lock membership after start without allocating a new seat.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock, sock.makefile('rb') as lines:
            sock.sendall(b'{"type":"catalog"}\n')
            catalog = json.loads(lines.readline())
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock, sock.makefile('rb') as lines:
            sock.sendall((json.dumps({'type': 'hello', 'protocol': 2, 'rules_fingerprint': catalog['rules_fingerprint'], 'player_id': 'late-'+uuid.uuid4().hex, 'nickname': 'Late'})+'\n').encode())
            response = json.loads(lines.readline())
            assert response['code'] == 'game_in_progress', response
        assert len(state(table)['players']) == 4
        print('PASS UNO regular SDK download consent, four clients, screen privacy and locked membership', flush=True)
        before = state(phones[2])
        link.interrupt_existing('close')
        wait_for(lambda: state(table)['view']['paused'])
        wait_for(lambda: state(phones[2]).get('session_state') == 'disconnected')
        result, _ = submit(phones[0], state(phones[0]), 'paused-draw', {'type': 'draw'})
        assert not result['accepted'] and result['code'] == 'players_disconnected'
        phones[2].room('room.reconnect')
        wait_for(lambda: all(not state(c)['view']['paused'] for c in clients) and state(phones[2]).get('session_state') == 'connected')
        after = state(phones[2])
        assert after['game_session_id'] == before['game_session_id'] and after['seat'] == before['seat']
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
        assert final['view']['hand'] == [] and final['view']['winner'] in by_seat
        assert all(state(c)['view']['winner'] == final['view']['winner'] for c in clients)
        for index, phone in enumerate(phones):
            result, _ = submit(phone, state(phone), 'rematch-'+str(index), {'type': 'rematch'})
            assert result['accepted'], result
            wait_for(lambda: all(state(c)['revision'] >= result['revision'] for c in clients))
            if index < 2:
                assert state(table)['view']['phase'] == 'finished'
        assert state(table)['view']['phase'] == 'playing' and state(table)['view']['round'] == 2
        assert state(table)['game_session_id'] == sid
        assert state(table)['view']['hand'] == []
        assert all(len(state(c)['view']['hand']) == 7 for c in phones)
        for client in reversed(clients):
            client.room('room.leave')
        print(f'PASS UNO real TCP game: {moves} actions, missed-call penalty, private hands, winner and unanimous rematch', flush=True)


if __name__ == '__main__':
    run()
