#!/usr/bin/env python3
"""Public table + three private clients over real TCP: consent download, private hands,
bidding, transport cut and reconnect, a complete hand of Dou Dizhu and a unanimous rematch."""
from contextlib import ExitStack
import json
from pathlib import Path
import sys
import shutil
import socket
import tempfile
import uuid
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / p) for p in ['tools/build', 'tools/dev', 'tests/support', 'tests/integration']]

from client_ui_hot import shell
from debug_integration import submit
from game_link import GameLink
from integration import free_port
from nvctl import push
from pack_mod import pack
from player_integration import wait_for


def state(client):
    return client.call('game.snapshot')


def act(actor, clients, request, action):
    result, _ = submit(actor, state(actor), request, action)
    assert result['accepted'], (action, result)
    wait_for(lambda: all(state(c)['revision'] >= result['revision'] for c in clients))
    return result


def run():
    with tempfile.TemporaryDirectory(prefix='nv-doudizhu-network-') as folder, ExitStack() as stack:
        folder = Path(folder)
        source = folder / 'mod'
        shutil.copytree(ROOT / 'mods/doudizhu', source)
        manifest = json.loads((source / 'manifest.json').read_text())
        game = 'doudizhu_probe_' + uuid.uuid4().hex[:10]
        manifest['id'] = game
        (source / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False))
        package = folder / 'doudizhu.zip'
        pack(source, package, hot=True)
        table, _ = stack.enter_context(shell(folder / 'table'))
        phones = [stack.enter_context(shell(folder / ('phone' + str(i))))[0] for i in range(3)]
        clients = [table, *phones]
        build = push(table, package)
        table.call('mods.activate', {'build': build['build']})
        port = free_port()
        table.room('room.create', {'game_id': game, 'port': port})
        sid = state(table)['game_session_id']
        link = stack.enter_context(GameLink('127.0.0.1', port))
        for index, phone in enumerate(phones):
            # Phones do not have the game: the ordinary SDK asks before downloading anything.
            phone.call('lan.inspect', {'address': '127.0.0.1', 'port': link.port if index == 2 else port, 'session_id': sid})
            wait_for(lambda: phone.call('lan.status')['confirmation'])
            assert phone.call('lan.status')['received'] == 0
            phone.call('lan.confirm_download')
            wait_for(lambda: state(phone).get('in_room'), timeout=20)
        wait_for(lambda: len(state(table)['players']) == 4)
        assert table.call('game.describe_actions')['legal_actions'][0]['type'] == 'start'
        act(table, clients, 'start', {'type': 'start'})
        wait_for(lambda: all(state(c)['view']['phase'] == 'bidding' for c in clients))
        assert state(table)['view']['hand'] == [] and state(table)['view']['bottom'] == []
        seen = []
        for phone in phones:
            view = state(phone)['view']
            assert len(view['hand']) == 17
            assert not {'hands', 'seed', 'shuffles'} & view.keys()
            assert view['bottom'] == [] and all(not hand for hand in view['revealed'])
            assert not set(view['hand']) & set(seen)
            seen.extend(view['hand'])
        assert table.call('game.describe_actions')['legal_actions'] == []
        # A fourth identity cannot take a seat once the hand is dealt.
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock, sock.makefile('rb') as lines:
            sock.sendall(b'{"type":"catalog"}\n')
            catalog = json.loads(lines.readline())
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock, sock.makefile('rb') as lines:
            sock.sendall((json.dumps({'type': 'hello', 'protocol': 2, 'rules_fingerprint': catalog['rules_fingerprint'], 'player_id': 'late-' + uuid.uuid4().hex, 'nickname': 'Late'}) + '\n').encode())
            assert json.loads(lines.readline())['code'] == 'game_in_progress'
        print('PASS Dou Dizhu: consent download, public table without cards, three disjoint 17-card hands, seats locked', flush=True)

        by_seat = {int(state(c)['seat']): c for c in phones}
        bidder = by_seat[int(state(table)['view']['turn'])]
        act(bidder, clients, 'bid-1', {'type': 'bid', 'amount': 2})
        second = by_seat[int(state(table)['view']['turn'])]
        result, _ = submit(second, state(second), 'bid-low', {'type': 'bid', 'amount': 1})
        assert not result['accepted'] and result['code'] == 'bid_too_low'
        act(second, clients, 'bid-2', {'type': 'bid', 'amount': 0})
        third = by_seat[int(state(table)['view']['turn'])]
        act(third, clients, 'bid-3', {'type': 'bid', 'amount': 0})
        landlord = int(state(table)['view']['landlord'])
        assert landlord == int(state(bidder)['seat']) and len(state(bidder)['view']['hand']) == 20
        assert all(len(state(c)['view']['bottom']) == 3 for c in clients)
        print('PASS Dou Dizhu bidding: low bid rejected, landlord takes the bottom, bottom becomes public', flush=True)

        # Cut the transport of the phone behind the proxy, then reconnect to the same seat.
        before = state(phones[2])
        link.interrupt_existing('close')
        wait_for(lambda: state(table)['view']['paused'])
        actor = by_seat[int(state(table)['view']['turn'])]
        if actor is not phones[2]:
            assert actor.call('game.describe_actions')['legal_actions'] == []
            card = state(actor)['view']['hand'][-1]
            result, _ = submit(actor, state(actor), 'paused-play', {'type': 'play', 'cards': [card]})
            assert not result['accepted'] and result['code'] == 'players_disconnected'
        phones[2].room('room.reconnect')
        wait_for(lambda: all(not state(c)['view']['paused'] for c in clients) and state(phones[2]).get('session_state') == 'connected')
        after = state(phones[2])
        assert after['seat'] == before['seat'] and after['view']['hand'] == before['view']['hand']
        print('PASS Dou Dizhu transport cut: actions paused, same-seat reconnect keeps the hand', flush=True)

        moves = 0
        passes = 0
        while state(table)['view']['phase'] != 'finished' and moves < 400:
            authoritative = state(table)
            actor = by_seat[int(authoritative['view']['turn'])]
            wait_for(lambda: state(actor)['revision'] == authoritative['revision'])
            legal = actor.call('game.describe_actions')['legal_actions']
            assert legal, state(actor)['view']
            # Mostly play the weakest answer; pass now and then so tricks reset to a free lead.
            plays = [a for a in legal if a['type'] == 'play']
            action = {'type': 'pass'} if (moves % 4 == 3 and any(a['type'] == 'pass' for a in legal)) or not plays else plays[0]
            if action['type'] == 'pass':
                passes += 1
            act(actor, clients, 'move-' + str(moves), action)
            for phone in phones:
                view = state(phone)['view']
                assert len(view['hand']) == view['counts'][int(state(phone)['seat'])]
            moves += 1
        final = state(table)['view']
        assert final['phase'] == 'finished', 'hand did not finish'
        assert sum(final['scores'].values()) == 0
        assert all(state(c)['view']['winner'] == final['winner'] for c in clients)
        assert all(state(c)['view']['scores'] == final['scores'] for c in clients)
        for index, phone in enumerate(phones):
            act(phone, clients, 'rematch-' + str(index), {'type': 'rematch'})
            if index < 2:
                assert state(table)['view']['phase'] == 'finished'
        view = state(table)['view']
        assert view['phase'] == 'bidding' and view['round'] == 2 and view['scores'] == final['scores']
        assert state(table)['game_session_id'] == sid
        assert all(len(state(c)['view']['hand']) == 17 for c in phones)
        for client in reversed(clients):
            client.room('room.leave')
        print(f'PASS Dou Dizhu real TCP hand: {moves} actions ({passes} passes), winner and zero-sum scores agree on all four screens, unanimous rematch keeps totals', flush=True)


if __name__ == '__main__':
    run()
