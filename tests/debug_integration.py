#!/usr/bin/env python3
"""Exercise the Debug service across two real Godot peers, including private cards."""
import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from nvctl import Client, RPCError
from integration import ROOT, GODOT, free_port


@contextlib.contextmanager
def peer(directory, game, game_port, role, enabled=True):
    port = free_port()
    config = Path(directory) / (role + '.json')
    config.unlink(missing_ok=True)
    env = dict(os.environ, GODOT_EDITOR_CUSTOM_FEATURES='novaparty_debug' if enabled else '')
    with tempfile.TemporaryFile(mode='w+') as log:
        process = subprocess.Popen([GODOT, '--headless', '--path', str(ROOT), '--log-file', str(Path(directory) / (role + '.log')), '--script', 'tests/debug_host.gd', '--', game, str(game_port), role, '--debug-bind=127.0.0.1', f'--debug-port={port}', f'--debug-connection={config}'], stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            for _ in range(160):
                log.seek(0)
                output = log.read()
                if 'DEBUG_READY' in output:
                    break
                assert process.poll() is None and 'SCRIPT ERROR' not in output, output
                time.sleep(.05)
            else:
                raise AssertionError(output)
            yield config, port
        finally:
            process.terminate()
            process.wait(timeout=4)
            log.seek(0)
            output = log.read()
            assert 'SCRIPT ERROR' not in output and 'ERROR:' not in output, output


def ready(client, revision=None):
    for _ in range(100):
        state = client.call('game.snapshot')
        if state.get('in_room') and len(state['players']) == 2 and (revision is None or state['revision'] == revision):
            return state
        time.sleep(.03)
    raise AssertionError(state)


def submit(client, state, request, action, **overrides):
    command = dict(game_session_id=state['game_session_id'], state_epoch=state['state_epoch'], expected_revision=state['revision'], request_id=request, action=action)
    command.update(overrides)
    assert client.call('game.submit', command)['queued']
    for _ in range(100):
        result = client.call('game.result', {'game_session_id': state['game_session_id'], 'request_id': request})
        if 'accepted' in result:
            return result, command
        time.sleep(.03)
    raise AssertionError('no receipt')


def rejected(client, method, params, code):
    try:
        client.call(method, params)
    except RPCError as error:
        assert str(error) == code, error
    else:
        raise AssertionError('unexpected success')


def test_debug():
    with tempfile.TemporaryDirectory(prefix='nv-debug-') as directory:
        with peer(directory, 'hidden_cards', free_port(), 'host', enabled=False) as (config, port):
            assert not config.exists()
            with socket.socket() as sock:
                assert sock.connect_ex(('127.0.0.1', port)) != 0
        print('PASS Debug feature absent: no credentials or listener')
        for game in ['gomoku', 'hidden_cards']:
            game_port = free_port()
            with peer(directory, game, game_port, 'host') as (host_config, debug_port), peer(directory, game, game_port, 'guest') as (guest_config, _):
                connection = json.loads(host_config.read_text())
                assert host_config.stat().st_mode & 0o077 == 0
                # Authentication required, both a wrong secret and unauthenticated RPC disconnect.
                for message in [{'method': 'game.snapshot', 'params': {}}, {'method': 'auth', 'params': {'token': 'wrong'}}]:
                    with socket.create_connection(('127.0.0.1', debug_port), timeout=2) as sock:
                        sock.sendall((json.dumps(dict(jsonrpc='2.0', id=1, **message)) + '\n').encode())
                        assert sock.recv(1) == b''
                host = Client(connection)
                guest = Client(json.loads(guest_config.read_text()))
                try:
                    hs, gs = ready(host), ready(guest)
                    assert hs['game_session_id'] == gs['game_session_id']
                    assert hs['app_instance_id'] != gs['app_instance_id']
                    assert 'token' not in json.dumps(hs) and 'player_id' not in json.dumps(hs)
                    assert host.call('device.info')['mode'] == 'play'
                    assert host.call('debug.capabilities')['hot_update']['presentation'] is True
                    assert 'view' not in host.call('room.status')
                    subscription = guest.call('events.subscribe')
                    assert subscription['snapshot']['seat'] == 1
                    rejected(host, 'game.submit', {}, 'invalid_command')
                    rejected(host, 'game.submit', dict(game_session_id='old-room', state_epoch=0, expected_revision=0, request_id='old', action={}), 'stale_context')
                    rejected(host, 'events.subscribe', {'after_seq': 'bad'}, 'invalid_cursor')
                    rejected(host, 'eval', {}, 'method_not_found')
                    if game == 'hidden_cards':
                        assert all(key not in hs['view'] and key not in gs['view'] for key in ['deck', 'hands'])
                        assert set(hs['view']['hand']).isdisjoint(gs['view']['hand'])
                        action = {'type': 'choose', 'card': hs['view']['hand'][0]}
                    else:
                        action = {'type': 'place', 'x': 7, 'y': 7}
                        assert len(host.call('game.describe_actions')['legal_actions']) == 225
                        assert guest.call('game.describe_actions')['legal_actions'] == []
                    receipt, command = submit(host, hs, 'host-action', action)
                    assert receipt['accepted'] and receipt['revision'] == 1
                    # Exact retry reaches the room's persistent deduplication cache.
                    assert host.call('game.submit', command)['queued']
                    assert host.call('game.result', {'game_session_id': hs['game_session_id'], 'request_id': 'host-action'}) == receipt
                    hs, gs = ready(host, 1), ready(guest, 1)
                    description = guest.call('game.describe_actions')
                    legal = description['legal_actions']
                    assert legal
                    if game == 'hidden_cards':
                        assert {item['card'] for item in legal} == set(gs['view']['hand'])
                    # Outdated revision is a final rejection, not transport success.
                    stale, _ = submit(guest, gs, 'stale', legal[0], expected_revision=0)
                    assert not stale['accepted'] and stale['code'] == 'stale_revision'
                    receipt, _ = submit(guest, gs, 'guest-action', legal[0])
                    assert receipt['accepted'] and receipt['revision'] == 2
                    # Guest receives its own authoritative receipt and state notifications.
                    kinds = set()
                    for _ in range(20):
                        event = guest.next_event()['params']
                        kinds.add(event['kind'])
                        if event['kind'] == 'action_result' and event['data'].get('request_id') == 'guest-action':
                            break
                    assert 'state' in kinds and 'action_result' in kinds
                    ready(host, 2)
                    assert guest.call('events.subscribe', {'after_seq': 0, 'app_instance_id': 'previous-process'})['resync_required']
                    # Replay events since an earlier connection cursor.
                    assert not guest.call('events.subscribe', {'after_seq': subscription['seq']})['resync_required']
                    assert guest.call('events.unsubscribe')['subscribed'] is False
                    run = subprocess.run([sys.executable, str(ROOT / 'tools/nvctl.py'), '--connection', str(guest_config), 'game.snapshot'], capture_output=True, text=True, timeout=8)
                    assert run.returncode == 0 and json.loads(run.stdout)['revision'] == 2, run.stderr
                    # Finish the match using exactly the public CLI --wait path.
                    for turn in range(12):
                        current = host.call('game.snapshot')
                        if current['view']['finished']:
                            break
                        seat = current['view']['turn'] if game == 'gomoku' else turn % 2
                        controller = host if seat == 0 else guest
                        config = host_config if seat == 0 else guest_config
                        current = ready(controller)
                        if game == 'gomoku':
                            row = 1 if seat == 0 else 2
                            x = next(x for x in range(15) if current['view']['board'][row * 15 + x] == -1)
                            action = {'type': 'place', 'x': x, 'y': row}
                        else:
                            action = controller.call('game.describe_actions')['legal_actions'][0]
                        command_cli = dict(game_session_id=current['game_session_id'], state_epoch=0, expected_revision=current['revision'], request_id=f"cli-{current['revision']}", action=action)
                        run = subprocess.run([sys.executable, str(ROOT / 'tools/nvctl.py'), '--connection', str(config), '--wait', 'game.submit', json.dumps(command_cli)], capture_output=True, text=True, timeout=12)
                        assert run.returncode == 0 and json.loads(run.stdout)['accepted'], run.stderr + run.stdout
                        ready(host, current['revision'] + 1)
                    assert host.call('game.snapshot')['view']['finished']
                    # Two events per retry overflow the bounded replay window without a new move.
                    revision = host.call('game.snapshot')['revision']
                    for _ in range(70):
                        host.call('game.submit', command)
                        time.sleep(.03)
                    assert host.call('game.snapshot')['revision'] == revision
                    assert host.call('events.subscribe', {'after_seq': 0})['resync_required']
                    cursor = host.call('events.subscribe')['seq']
                    host.close()
                    host = Client(connection)
                    assert not host.call('events.subscribe', {'after_seq': cursor, 'app_instance_id': connection['app_instance_id']})['resync_required']
                finally:
                    host.close()
                    guest.close()
            print('PASS Debug ' + game + ': auth, filtered views/actions, both receipts, retry, stale guards, events, CLI')


if __name__ == '__main__':
    test_debug()
