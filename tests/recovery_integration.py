#!/usr/bin/env python3
"""Exercise actual client recovery from closed and silent game TCP links."""
import argparse
import json
from pathlib import Path
import socket
import threading
import tempfile
import time

from hot_integration import peer
from debug_integration import ready, submit
from integration import free_port, Client as GameClient
from player_integration import start, stop_if_running, wait_for, read_json
from game_link import GameLink


def same_game(before, after):
    for key in ['game_session_id', 'state_epoch', 'revision', 'seat', 'view']:
        assert before[key] == after[key], key


def resumed(client, before):
    state = client.call('game.snapshot')
    if state.get('in_room') and state.get('session_state') == 'connected' and state.get('local_session_id') != before['local_session_id']:
        same_game(before, state)
        assert all(p['connected'] for p in state['players'])
        return state
    return None


def recover(host, guest, guest_config, directory, port):
    """Host room must already exist; guest must be in lobby. Returns safe diagnostics."""
    state_path = directory / 'recovery-player.json'
    diagnostics = []
    with GameLink('127.0.0.1', port) as link:
        guest.room('room.join', {'game_id': 'gomoku', 'address': '127.0.0.1', 'port': link.port})
        ready(host)
        ready(guest)
        # Arrange a nonempty board with the guest waiting for the host, so no
        # controller move can hide a state loss during a reconnect.
        receipt, _ = submit(host, host.call('game.snapshot'), 'recovery-opening', {'type': 'place', 'x': 7, 'y': 7})
        assert receipt['accepted']
        receipt, _ = submit(guest, ready(guest, 1), 'recovery-reply', {'type': 'place', 'x': 8, 'y': 7})
        assert receipt['accepted']
        ready(host, 2)
        start(state_path, guest_config)
        try:
            # A healthy idle connection must survive multiple heartbeat periods.
            before = ready(guest, 2)
            time.sleep(9)
            assert guest.call('game.snapshot')['local_session_id'] == before['local_session_id']
            assert guest.call('game.snapshot')['session_state'] == 'connected'
            same_game(before, guest.call('game.snapshot'))
            print('PASS healthy idle heartbeat: same session after 9 seconds', flush=True)
            for mode in ['close', 'both', 'downstream', 'upstream']:
                before = guest.call('game.snapshot')
                cursor = guest.call('events.subscribe')['seq']
                started = time.monotonic()
                link.interrupt_existing(mode)
                after = wait_for(lambda: resumed(guest, before), timeout=20)
                elapsed = round(time.monotonic() - started, 2)
                authority = ready(host, 2)
                assert authority['game_session_id'] == before['game_session_id']
                assert authority['view'] == before['view']
                guest.call('events.subscribe', {'after_seq': cursor})
                errors = [m['params']['data'].get('connection_error') for m in guest.notifications if m.get('params', {}).get('kind') == 'connection' and m['params'].get('seq', -1) > cursor]
                if mode == 'close':
                    assert 'transport_lost' in errors, errors
                else:
                    # One-way loss can cause either peer to time out first. If
                    # the host closes first, guest correctly reports transport_lost.
                    assert any(e in ['heartbeat_timeout', 'transport_lost'] for e in errors), errors
                    assert elapsed < 15, elapsed
                assert after['room_generation'] > before['room_generation']
                assert read_json(state_path)['moves_accepted'] == 0
                diagnostics.append({'fault': mode, 'recovered_seconds': elapsed, 'revision': after['revision'], 'same_game': True, 'same_seat': True})
                print('PASS game link', mode, 'recovered in', elapsed, 'seconds; same match, seat, board and revision', flush=True)
            # Recovered guest can act again through the original authority.
            # Forward its command, lose the receipt and keep TCP silently open.
            # Recovery must query/retry that same ID rather than invent a move.
            prior_session = guest.call('game.snapshot')['local_session_id']
            link.lose_next_command_reply()
            receipt, _ = submit(host, host.call('game.snapshot'), 'recovered-next', {'type': 'place', 'x': 7, 'y': 8})
            assert receipt['accepted']
            wait_for(lambda: host.call('game.snapshot')['revision'] == 4)
            started = time.monotonic()
            wait_for(lambda: guest.call('game.snapshot').get('local_session_id') != prior_session and guest.call('game.snapshot').get('session_state') == 'connected', timeout=20)
            wait_for(lambda: read_json(state_path)['moves_accepted'] == 1, timeout=10)
            final = ready(guest, 4)
            assert final['view'] == host.call('game.snapshot')['view']
            assert read_json(state_path)['pending'] is None
            assert read_json(state_path)['desired'] == 'running'
            assert len(link.commands) >= 2 and len({json.dumps(c, sort_keys=True) for c in link.commands}) == 1
            diagnostics.append({'fault': 'accepted_move_receipt_lost', 'recovered_seconds': round(time.monotonic() - started, 2), 'revision': final['revision'], 'exact_retry': True, 'accepted_moves': 1})
            print('PASS accepted move + lost game receipt: same command replayed after reconnect, one accepted move, no manual resume', flush=True)
        finally:
            stop_if_running(state_path)
            guest.room('room.leave')
    return diagnostics


def test_recovery():
    with tempfile.TemporaryDirectory(prefix='nv-recovery-') as directory:
        directory = Path(directory)
        port = free_port()
        with peer(directory / 'host', port, 'lobby') as (host, _), peer(directory / 'guest', port, 'lobby') as (guest, config):
            host.room('room.create', {'game_id': 'gomoku', 'port': port})
            result = recover(host, guest, config, directory, port)
            host.room('room.leave')
            protocol_edges(host, guest, port)
        output = Path('build/validation/recovery.json')
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2))


def protocol_edges(host, guest, port):
    host.room('room.create', {'game_id': 'gomoku', 'port': port})
    state = host.call('game.snapshot')
    legacy = GameClient(port)
    try:
        legacy.send({'type': 'hello', 'protocol': 1, 'fingerprint': state['fingerprint'], 'player_id': 'legacy', 'nickname': 'Legacy'})
        welcome = legacy.receive('welcome')
        assert 'heartbeat_v1' not in welcome['capabilities']
        legacy.receive('snapshot')
        time.sleep(9)
        legacy.send({'type': 'command', 'request_id': 'legacy-idle', 'expected_revision': 0, 'action': {'type': 'place', 'x': 0, 'y': 0}})
        assert legacy.receive('receipt')['code'] == 'not_your_turn'
        print('PASS unnegotiated protocol-1 client remains connected beyond heartbeat deadline', flush=True)
    finally:
        legacy.close()
        host.room('room.leave')
    host.room('room.create', {'game_id': 'gomoku', 'port': port})
    state = host.call('game.snapshot')
    forged = GameClient(port)
    try:
        forged.send({'type': 'hello', 'protocol': 2, 'rules_fingerprint': state['rules_fingerprint'], 'capabilities': ['heartbeat_v1'], 'player_id': 'forged', 'nickname': 'Forged'})
        assert 'heartbeat_v1' in forged.receive('welcome')['capabilities']
        forged.receive('snapshot')
        forged.socket.settimeout(.2)
        deadline = time.monotonic() + 11
        closed = False
        while time.monotonic() < deadline:
            # Unrelated pongs cannot prove that a challenge reached this peer.
            try:
                forged.send({'type': 'pong', 'nonce': '0000000000000000'})
                data = forged.socket.recv(8192)
                if not data:
                    closed = True
                    break
            except socket.timeout:
                pass
            except (BrokenPipeError, ConnectionResetError):
                closed = True
                break
            time.sleep(.1)
        assert closed, 'wrong nonce kept silent connection alive'
        print('PASS forged/unsolicited pong cannot renew heartbeat deadline', flush=True)
    finally:
        forged.close()
        host.room('room.leave')
    # A TCP connection that accepts hello but never sends welcome must not hang forever.
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen()
    listener.settimeout(.1)
    stopped = threading.Event()
    def silence():
        connection = None
        try:
            while not stopped.is_set():
                if connection is None:
                    try:
                        connection, _ = listener.accept()
                        connection.settimeout(.1)
                    except socket.timeout:
                        continue
                try:
                    if not connection.recv(8192):
                        return
                except socket.timeout:
                    continue
        finally:
            if connection:
                connection.close()
    worker = threading.Thread(target=silence, daemon=True)
    worker.start()
    try:
        guest.room('room.join', {'game_id': 'gomoku', 'address': '127.0.0.1', 'port': listener.getsockname()[1]})
        result = wait_for(lambda: (s if (s := guest.call('game.snapshot')).get('connection_error') == 'handshake_timeout' else None), timeout=14)
        assert not result['in_room'] and result['session_state'] == 'disconnected'
        print('PASS silent welcome handshake ends with structured timeout', flush=True)
    finally:
        stopped.set()
        worker.join(timeout=2)
        listener.close()
        guest.room('room.leave')


def test_ios(device):
    from ios_simulator import credentials
    from nvctl import Client
    with tempfile.TemporaryDirectory(prefix='nv-ios-recovery-') as directory:
        directory = Path(directory)
        config = directory / 'iphone.json'
        ios = Client(credentials(device, config))
        try:
            if ios.call('room.status')['local_session_id']:
                ios.room('room.leave')
            port = free_port()
            with peer(directory / 'desktop', port, 'lobby') as (host, _):
                host.room('room.create', {'game_id': 'gomoku', 'port': port})
                result = recover(host, ios, config, directory, port)
                host.room('room.leave')
            output = Path('build/validation/ios-recovery.json')
            output.write_text(json.dumps({'device': device, 'version': ios.call('device.info')['version'], 'results': result}, indent=2))
        finally:
            ios.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ios-device')
    args = parser.parse_args()
    test_ios(args.ios_device) if args.ios_device else test_recovery()
