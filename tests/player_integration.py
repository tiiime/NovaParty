#!/usr/bin/env python3
"""Detached policies against full Godot apps and guarded room lifecycle RPCs."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid

from hot_integration import peer
from debug_proxy import lost_submit_reply
from debug_integration import ready, rejected
from integration import ROOT, free_port
from nvplayer import is_running, read_json
from player_strategies import gomoku

PLAYER = ROOT / 'tools/nvplayer.py'


def control(command, state, *arguments, success=True):
    run = subprocess.run([sys.executable, str(PLAYER), command, '--state', str(state), *map(str, arguments)], capture_output=True, text=True, timeout=12)
    assert (run.returncode == 0) == success, run.stdout + run.stderr
    return json.loads(run.stdout if success else run.stderr)


def start(state, config, strategy='gomoku', **options):
    arguments = ['--connection', config, '--strategy', strategy, '--daemon']
    for key, value in options.items():
        arguments += ['--' + key.replace('_', '-')]
        if value is not True:
            arguments += [str(value)]
    return control('start', state, *arguments)


def wait_for(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.04)
    raise AssertionError('condition timed out')


def stop_if_running(state):
    if is_running(state):
        control('stop', state)


def finished(client, timeout=120):
    return wait_for(lambda: (s if (s := client.call('game.snapshot')).get('view', {}).get('finished') else None), timeout)


def tactics():
    def choose(own, enemy):
        board = [-1] * 225
        for seat, positions in enumerate([own, enemy]):
            for x, y in positions:
                board[y * 15 + x] = seat
        snapshot = {'in_room': True, 'connected': True, 'players': [{'connected': True}] * 2, 'game_id': 'gomoku', 'seat': 0, 'view': {'board': board, 'turn': 0, 'finished': False}}
        result = gomoku(snapshot)
        assert snapshot['view']['board'] == board
        return result['x'], result['y']
    assert choose([], [(x, 0) for x in range(4)]) == (4, 0)
    assert choose([(x, 3) for x in range(4)], [(x, 0) for x in range(4)]) == (4, 3)
    assert choose([], [(6, 7), (8, 7), (7, 6), (7, 8)]) == (7, 7)
    assert choose([], []) == (7, 7)
    print('PASS policy: immediate win, forced block, double-three prevention, center opening')


def test_players():
    tactics()
    with tempfile.TemporaryDirectory(prefix='nv-player-') as directory:
        directory = Path(directory)
        port = free_port()
        with peer(directory / 'host', port, 'lobby') as (host, host_config), peer(directory / 'guest', port, 'lobby') as (guest, guest_config), lost_submit_reply(host_config, directory / 'proxy.json') as (proxy_config, dropped):
            initial = host.call('room.status')
            context = {key: initial[key] for key in ['app_instance_id', 'room_generation', 'local_session_id']}
            command = dict(context, request_id='create', game_id='gomoku', port=port)
            rejected(host, 'room.create', dict(command, request_id='stale', app_instance_id='old'), 'stale_room_context')
            rejected(host, 'room.create', dict(command, request_id='bad-port', port=80), 'invalid_room_parameters')
            created = host.call('room.create', command)
            assert host.call('room.create', command) == created
            rejected(host, 'room.create', dict(command, port=port + 1), 'request_id_reused')
            rejected(host, 'room.create', dict(command, request_id='stale-generation'), 'stale_room_context')
            rejected(host, 'room.create', dict(command, request_id='current', room_generation=created['room_generation']), 'room_busy')
            guest.room('room.join', {'game_id': 'gomoku', 'port': port, 'address': '127.0.0.1'})
            hs, gs = ready(host), ready(guest)
            assert hs['session_state'] == 'hosting' and gs['session_state'] == 'connected'
            states = [directory / 'host-player.json', directory / 'guest-player.json']
            try:
                start(states[0], proxy_config, think_delay=.12)
                control('start', states[0], '--connection', host_config, success=False)
                wait_for(lambda: host.call('game.snapshot')['revision'] == 1)
                wait_for(lambda: read_json(states[0]).get('moves_accepted') == 1)
                assert dropped.is_set() and read_json(states[0])['reconnects'] >= 2
                assert host.call('game.snapshot')['revision'] == 1
                print('PASS lost submit reply: reconnect queries original request; one accepted move')
                control('pause', states[0])
                assert read_json(states[0])['desired'] == 'paused'
                start(states[1], guest_config, think_delay=.12)
                wait_for(lambda: host.call('game.snapshot')['revision'] == 2)
                time.sleep(.3)
                assert host.call('game.snapshot')['revision'] == 2
                # Kill/restart the process while a controlled seat is idle. Lock is released;
                # recovered checkpoint must retain the match and never replay accepted moves.
                os.kill(read_json(states[1])['pid'], signal.SIGKILL)
                wait_for(lambda: not is_running(states[1]))
                start(states[1], guest_config, think_delay=.12)
                control('resume', states[0])
                result = finished(host)
                final = ready(guest)
                assert result['view'] == final['view']
                counters = [read_json(state) for state in states]
                assert sum(s['moves_accepted'] for s in counters) == result['revision']
                assert all(s['pending'] is None for s in counters)
                print('PASS detached Gomoku, pause/resume, singleton lock, killed-process recovery:', result['revision'], 'moves; last policy-to-receipt ms:', [s['latency_ms'] for s in counters])
                # An existing controller stays pinned when the same application enters a new match.
                host.room('room.leave')
                guest.room('room.leave')
                rejected(host, 'room.leave', dict(context, request_id='old-leave'), 'stale_room_context')
                host.room('room.create', {'game_id': 'hidden_cards', 'port': port})
                guest.room('room.join', {'game_id': 'hidden_cards', 'port': port, 'address': '127.0.0.1'})
                ready(host)
                wait_for(lambda: read_json(states[0]).get('phase') == 'paused_room_changed')
                assert host.call('game.snapshot')['revision'] == 0
            finally:
                for state in states:
                    stop_if_running(state)
            cards = [directory / 'cards-host.json', directory / 'cards-guest.json']
            try:
                start(cards[0], host_config, 'first_legal', once=True)
                start(cards[1], guest_config, 'first_legal', once=True)
                result = finished(host)
                for state in cards:
                    wait_for(lambda: not is_running(state))
                    assert read_json(state)['phase'] == 'finished'
                assert result['revision'] == 6
                assert sum(read_json(state)['moves_accepted'] for state in cards) == 6
                print('PASS legal-action adapter completes private-hand game; once exits cleanly')
            finally:
                for state in cards:
                    stop_if_running(state)
        print('PASS lifecycle: app/generation guards, exact retry, ID reuse rejection, active-room protection')


if __name__ == '__main__':
    test_players()
