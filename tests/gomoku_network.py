#!/usr/bin/env python3
"""Real two-client clock, reconnect and consensus rematch regression."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import time

from client_ui_hot import shell
from debug_integration import ready, submit
from integration import free_port
from player_integration import wait_for
from game_link import GameLink


def run():
    with tempfile.TemporaryDirectory(prefix='nv-gomoku-match-') as directory:
        directory = Path(directory)
        with shell(directory / 'host') as (host, _), shell(directory / 'guest') as (guest, _):
            port = free_port()
            host.room('room.create', {'game_id': 'gomoku', 'port': port, 'nickname': '小星'})
            initial = host.call('game.snapshot')
            assert initial['clock']['running_seat'] == -1
            time.sleep(.4)
            assert host.call('game.snapshot')['clock']['elapsed_ms'] == [0, 0]
            with GameLink('127.0.0.1', port) as link:
                guest.room('room.join', {'game_id': 'gomoku', 'port': link.port, 'address': '127.0.0.1', 'nickname': '月亮'})
                ready(host)
                ready(guest)
                wait_for(lambda: host.call('game.snapshot')['clock']['elapsed_ms'][0] >= 1000)
                before = host.call('game.snapshot')
                assert before['revision'] == 0 and before['clock']['running_seat'] == 0
                assert before['clock']['elapsed_ms'][1] == 0
                game_id = before['game_session_id']
                # Move Black, verify only White's cumulative time advances.
                result, _ = submit(host, before, 'black-0', {'type': 'place', 'x': 5, 'y': 7})
                assert result['accepted']
                wait_for(lambda: guest.call('game.snapshot')['revision'] == 1)
                wait_for(lambda: host.call('game.snapshot')['clock']['elapsed_ms'][1] >= 1000)
                sample = host.call('game.snapshot')
                black_used = sample['clock']['elapsed_ms'][0]
                time.sleep(1.1)
                assert host.call('game.snapshot')['clock']['elapsed_ms'][0] == black_used
                # Close game sockets while keeping Debug sessions alive; clocks stop.
                link.interrupt_existing('close')
                wait_for(lambda: not host.call('game.snapshot')['players'][1]['connected'])
                paused = host.call('game.snapshot')
                assert paused['clock']['running_seat'] == -1
                time.sleep(1.2)
                assert host.call('game.snapshot')['clock']['elapsed_ms'] == paused['clock']['elapsed_ms']
                assert host.call('game.describe_actions')['legal_actions'] == []
                guest.room('room.reconnect')
                ready(host)
                ready(guest)
                resumed = host.call('game.snapshot')
                assert resumed['game_session_id'] == game_id and resumed['revision'] == 1
                assert resumed['clock']['elapsed_ms'][1] < paused['clock']['elapsed_ms'][1] + 800
                assert resumed['clock']['running_seat'] == 1
                for x in range(6, 10):
                    for client, action in [(guest, {'type': 'place', 'x': x - 2, 'y': 9}), (host, {'type': 'place', 'x': x, 'y': 7})]:
                        state = client.call('game.snapshot')
                        result, _ = submit(client, state, 'move-' + str(state['revision']), action)
                        assert result['accepted']
                        wait_for(lambda: host.call('game.snapshot')['revision'] == state['revision'] + 1 and guest.call('game.snapshot')['revision'] == state['revision'] + 1)
                final = host.call('game.snapshot')
                assert final['view']['finished'] and final['view']['winner'] == 0
                assert final['clock']['running_seat'] == -1
                assert host.call('mods.status')['view_state']['result_open']
                assert guest.call('mods.status')['view_state']['result_open']
                elapsed = final['clock']['elapsed_ms']
                time.sleep(1.1)
                assert host.call('game.snapshot')['clock']['elapsed_ms'] == elapsed
                result, _ = submit(host, final, 'consent-black', {'type': 'rematch', 'round': 1})
                assert result['accepted']
                assert host.call('game.snapshot')['view']['finished']
                wait_for(lambda: guest.call('game.snapshot')['revision'] == final['revision'] + 1)
                state = guest.call('game.snapshot')
                result, _ = submit(guest, state, 'consent-white', {'type': 'rematch', 'round': 1})
                assert result['accepted']
                wait_for(lambda: guest.call('game.snapshot')['view']['round'] == 2)
                new = host.call('game.snapshot')
                assert new['game_session_id'] == game_id and new['revision'] == final['revision'] + 2
                assert new['view']['moves'] == 0 and new['view']['board'] == [-1] * 225
                assert new['clock']['elapsed_ms'][0] < 1000 and new['clock']['elapsed_ms'][1] == 0
                assert not host.call('mods.status')['view_state']['result_open']
                assert not guest.call('mods.status')['view_state']['result_open']
                host.room('room.leave')
                guest.room('room.leave')
    print('PASS two-client clocks, pause/reconnect, real win dialogs, both rematch consents, timer reset and continued session')


if __name__ == '__main__':
    run()
