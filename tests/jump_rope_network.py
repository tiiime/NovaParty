#!/usr/bin/env python3
"""Three real clients exercise drop-in lifecycle and concurrent motion events."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
from client_ui_hot import shell
from debug_integration import submit
from integration import free_port, ROOT
from nvctl import push
from pack_mod import pack
from player_integration import wait_for


def state(client):
    return client.call('game.snapshot')


def role(client, value):
    current = state(client)
    action = {'type': 'role', 'role': value, 'generation': current['view']['slots'][int(current['seat'])]['generation']}
    result, _ = submit(client, current, 'role-' + str(current['revision']), action)
    assert result['accepted'], result


def run():
    with tempfile.TemporaryDirectory(prefix='nv-jump-') as path:
        path = Path(path)
        with shell(path / 'screen', mods=['jump_rope']) as (screen, _), shell(path / 'one', mods=['jump_rope']) as (one, _), shell(path / 'two', mods=['jump_rope']) as (two, _):
            port = free_port()
            screen.room('room.create', {'game_id': 'jump_rope', 'port': port})
            role(screen, 'display')
            session_id = state(screen)['game_session_id']
            for client in [one, two]:
                client.room('room.join', {'game_id': 'jump_rope', 'port': port, 'address': '127.0.0.1'})
                wait_for(lambda: state(client).get('in_room', False))
                role(client, 'controller')
            wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 2)
            revision = state(screen)['revision']
            def jump(client, count, request):
                current = state(client)
                action = {'type': 'jump', 'count': count, 'generation': current['view']['slots'][int(current['seat'])]['generation']}
                result, _ = submit(client, current, request, action, expected_revision=revision)
                assert result['accepted'], result
            with ThreadPoolExecutor(2) as workers:
                for future in [workers.submit(jump, one, 1, 'jump-a'), workers.submit(jump, two, 1, 'jump-b')]:
                    future.result()
            wait_for(lambda: state(screen)['view']['slots'][1]['count'] == 1 and state(screen)['view']['slots'][2]['count'] == 1)
            hot = path / 'jump-hot.zip'
            pack(ROOT / 'mods/jump_rope', hot, hot=True)
            build = push(screen, hot)
            screen.call('mods.activate', {'build': build['build']})
            assert state(screen)['game_session_id'] == session_id
            assert screen.call('mods.status')['view_state']['participants'] == 2
            one.room('room.leave')
            wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 1)
            jump(two, 2, 'jump-after-leave')
            wait_for(lambda: state(screen)['view']['slots'][2]['count'] == 2)
            one.room('room.join', {'game_id': 'jump_rope', 'port': port, 'address': '127.0.0.1'})
            wait_for(lambda: state(one).get('in_room', False))
            assert state(one)['seat'] == 1
            role(one, 'controller')
            wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 2)
            assert state(screen)['game_session_id'] == session_id
            role(one, 'none')
            wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 1)
            two.room('room.leave')
            wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 0)
            one.room('room.leave')
            screen.room('room.leave')
    print('PASS drop-in: waiting display, two simultaneous counters, leave/rejoin/reuse, role change, empty display without restart')


if __name__ == '__main__':
    run()
