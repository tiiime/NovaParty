#!/usr/bin/env python3
"""Two running clients per game; install external Mods, play and recover over TCP."""
from pathlib import Path
import tempfile

from client_ui_hot import shell
from debug_integration import ready, submit
from integration import free_port
from player_integration import wait_for
from game_link import GameLink


def play(client, host, guest, action, reject=None):
    before = client.call('game.snapshot')
    result, _ = submit(client, before, f"tabletop-{before['revision']}-{action}-{reject}", action)
    if reject:
        assert not result['accepted'] and result['code'] == reject, result
        assert host.call('game.snapshot')['revision'] == before['revision']
        return before['view']
    assert result['accepted'], result
    rev = before['revision'] + 1
    wait_for(lambda: host.call('game.snapshot')['revision'] == rev and guest.call('game.snapshot')['revision'] == rev)
    left, right = host.call('game.snapshot'), guest.call('game.snapshot')
    assert left['view']['board'] == right['view']['board']
    assert left['view']['phase'] == right['view']['phase']
    assert all('history' not in s['view'] for s in [left, right])
    if 'undo_by' in left['view']:
        assert left['view']['undo_by'] == right['view']['undo_by']
        assert left['view']['turn'] == right['view']['turn']
    return left['view']


def run(game, folder):
    with shell(folder / 'host', [game]) as (host, _), shell(folder / 'guest', [game]) as (guest, _):
        port = free_port()
        host.room('room.create', {'game_id': game, 'port': port, 'nickname': '小星'})
        with GameLink('127.0.0.1', port) as link:
            guest.room('room.join', {'game_id': game, 'port': link.port, 'address': '127.0.0.1', 'nickname': '月亮'})
            ready(host)
            ready(guest)
            send = lambda client, action, reject=None: play(client, host, guest, action, reject)
            if game == 'xiangqi':
                initial_board = host.call('game.snapshot')['view']['board']
                assert len(host.call('game.describe_actions')['legal_actions']) == 16 * 74 + 1
                send(host, {'type': 'move', 'from': 81, 'to': 82}, 'illegal_move')
                assert send(host, {'type': 'move', 'from': 81, 'to': 27})['board'][27] == 5
                assert send(host, {'type': 'request_undo'})['undo_by'] == 0
                send(host, {'type': 'accept_undo'}, 'undo_needs_opponent')
                send(guest, {'type': 'move', 'from': 28, 'to': 36}, 'undo_pending')
            else:
                send(host, {'type': 'move', 'to': 0})
                send(guest, {'type': 'move', 'to': 0}, 'occupied')
            before = guest.call('game.snapshot')
            link.reject_new.set()
            link.interrupt_existing('close')
            wait_for(lambda: not host.call('game.snapshot')['players'][1]['connected'])
            wait_for(lambda: guest.call('ui.status')['status'] == 'RECONNECTING')
            link.reject_new.clear()
            wait_for(lambda: guest.call('game.snapshot').get('session_state') == 'connected')
            after = ready(guest)
            ready(host)
            for key in ['local_session_id', 'game_session_id', 'room_generation', 'seat', 'revision']:
                assert before[key] == after[key], key
            assert before['view']['board'] == after['view']['board']
            if game == 'xiangqi':
                assert after['view']['undo_by'] == 0
                assert guest.call('game.describe_actions')['legal_actions'] == [{'type': 'accept_undo'}, {'type': 'decline_undo'}]
                declined = send(guest, {'type': 'decline_undo'})
                assert declined['board'][27] == 5 and declined['turn'] == 1
                send(host, {'type': 'request_undo'})
                restored = send(guest, {'type': 'accept_undo'})
                assert restored['board'] == initial_board and restored['turn'] == 0 and restored['undo_result'] == 'undo_accepted'
                assert send(host, {'type': 'move', 'from': 81, 'to': 4})['winner'] == 0
            else:
                send(guest, {'type': 'move', 'to': 80})
                send(host, {'type': 'pass'})
                assert send(guest, {'type': 'pass'})['phase'] == 'score'
                assert send(host, {'type': 'confirm_score'})['phase'] == 'score'
                assert send(guest, {'type': 'mark', 'to': 0})['confirmed'] == [False, False]
                assert send(guest, {'type': 'resume'})['phase'] == 'play'
                send(host, {'type': 'pass'})
                send(guest, {'type': 'pass'})
                send(guest, {'type': 'confirm_score'})
                end = send(host, {'type': 'confirm_score'})
                assert end['reason'] == 'scored' and end['scores'] == [1.0, 8.5], end
            assert send(host, {'type': 'rematch'})['phase'] == 'finished'
            end = send(guest, {'type': 'rematch'})
            assert end['round'] == 2 and end['phase'] == 'play'
            assert host.call('game.snapshot')['game_session_id'] == before['game_session_id']
            host.room('room.leave')
            guest.room('room.leave')
            print(f'PASS {game}: external package, two clients, rejection, reconnect, result, mutual rematch')


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='nv-tabletop-') as directory:
        for mod in ['xiangqi', 'go']:
            run(mod, Path(directory) / mod)
