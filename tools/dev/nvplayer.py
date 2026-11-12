#!/usr/bin/env python3
"""Persistent Debug-seat player; local strategies continue independently of chat."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import uuid

from nvctl import Client, RPCError
from player_strategies import first_legal, gomoku, ready


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + str(os.getpid()) + '.tmp')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        temporary.unlink(missing_ok=True)


def is_running(path):
    lock_path = Path(str(path) + '.lock')
    if not lock_path.exists():
        return False
    with lock_path.open('a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(stream, fcntl.LOCK_UN)
    return False


class Player:
    def __init__(self, args):
        self.args = args
        self.path = args.state.resolve()
        self.run_id = uuid.uuid4().hex
        self.client = None
        self.snapshot = {}
        self.seq = -1
        self.app_id = None
        self.methods = []
        self.stopping = False
        self.last_control = None
        self.last_considered = None
        self.next_decision = 0
        self.next_refresh = 0
        self.next_game_reconnect = 0
        self.next_receipt = 0
        self.phase = 'starting'
        self.reason = ''
        self.signature = [str(args.connection.resolve()), args.strategy, args.create, args.join, args.game, args.port, args.follow_rooms]
        old = read_json(self.path, {})
        old = old if old.get('signature') == self.signature else {}
        self.desired = 'running'
        self.pinned_app = old.get('pinned_app')
        self.pinned_game = old.get('pinned_game')
        self.pending = old.get('pending')
        self.bootstrap = old.get('bootstrap')
        self.bootstrap_done = old.get('bootstrap_done', False)
        self.settled_revision = old.get('settled_revision', -1)
        self.moves = old.get('moves_accepted', 0)
        self.latency_ms = old.get('latency_ms')
        self.reconnects = 0
        self.lock = None

    def save(self):
        value = {'version': 1, 'pid': os.getpid(), 'run_id': self.run_id, 'running': not self.stopping,
                 'phase': self.phase, 'reason': self.reason, 'desired': self.desired,
                 'strategy': self.args.strategy, 'signature': self.signature,
                 'app_instance_id': self.app_id, 'pinned_app': self.pinned_app,
                 'pinned_game': self.pinned_game, 'game_id': self.snapshot.get('game_id'),
                 'revision': self.snapshot.get('revision'), 'seat': self.snapshot.get('seat'),
                 'pending': self.pending, 'bootstrap': self.bootstrap, 'bootstrap_done': self.bootstrap_done,
                 'settled_revision': self.settled_revision, 'moves_accepted': self.moves,
                 'latency_ms': self.latency_ms, 'reconnects': self.reconnects, 'seq': self.seq,
                 'updated_at': time.time()}
        atomic_json(self.path, value)

    def phase_to(self, phase, reason=''):
        if (phase, reason) != (self.phase, self.reason):
            self.phase, self.reason = phase, reason
            self.save()
            print(json.dumps({'event': phase, 'reason': reason, 'revision': self.snapshot.get('revision')}, ensure_ascii=False), flush=True)

    def refresh(self):
        subscription = self.client.call('events.subscribe')
        self.seq = int(subscription['seq'])
        self.snapshot = subscription['snapshot']
        if self.pending and self.snapshot.get('local_session_id') != self.pending.get('local_session_id'):
            self.next_receipt = 0
        self.next_decision = time.monotonic() + self.args.think_delay
        self.next_refresh = time.monotonic() + 3

    def connect(self):
        connection = read_json(self.args.connection)
        if not isinstance(connection, dict):
            raise RPCError('connection_config_unavailable')
        self.client = Client(connection, timeout=self.args.rpc_timeout)
        self.app_id = self.client.auth['app_instance_id']
        self.methods = self.client.call('debug.capabilities')['methods']
        self.refresh()
        self.reconnects += 1
        self.save()
        if not self.bootstrap_done and (self.args.create or self.args.join):
            method = 'room.create' if self.args.create else 'room.join'
            if method not in self.methods:
                raise ValueError('room_control_requires_client_0.1.4')
            if self.bootstrap is None:
                params = self.room_context()
                params.update({'game_id': self.args.game, 'port': self.args.port})
                if self.args.join:
                    params['address'] = self.args.join
                if self.args.nickname:
                    params['nickname'] = self.args.nickname
                self.bootstrap = {'method': method, 'params': params}
                self.save()  # Persist exact lifecycle ID/context before transmitting.
            if self.bootstrap['params']['app_instance_id'] != self.app_id:
                raise ValueError('bootstrap_app_changed')
            self.client.call(self.bootstrap['method'], self.bootstrap['params'])
            self.bootstrap_done = True
            self.bootstrap = None
            self.save()
            self.refresh()
        self.resolve_pending()
        self.next_refresh = time.monotonic() + 3
        self.last_considered = None

    def room_context(self):
        return {'app_instance_id': self.snapshot['app_instance_id'],
                'room_generation': self.snapshot['room_generation'],
                'local_session_id': self.snapshot['local_session_id'],
                'request_id': 'player-room-' + uuid.uuid4().hex}

    def control(self):
        command = read_json(str(self.path) + '.control', {})
        if command.get('run_id') != self.run_id or command.get('nonce') == self.last_control:
            return
        self.last_control = command.get('nonce')
        desired = command.get('desired')
        if desired == 'stopped':
            self.stopping = True
        elif desired in ['paused', 'running']:
            self.desired = desired
            self.last_considered = None
            if command.get('adopt_room'):
                self.pinned_app = self.pinned_game = None
                self.pending = None
                self.settled_revision = -1
            if self.pending:
                self.pending['attempts'] = 0
            self.next_receipt = 0
            self.save()

    def context_matches(self):
        s = self.snapshot
        if not s.get('in_room'):
            self.phase_to('waiting_room' if s.get('session_state', 'lobby') != 'rejected' else 'join_rejected', s.get('connection_error', ''))
            return False
        app, game = s['app_instance_id'], s['game_session_id']
        if (app, game) != (self.pinned_app, self.pinned_game):
            if self.pinned_game is not None and not self.args.follow_rooms:
                self.phase_to('paused_room_changed')
                return False
            self.pinned_app, self.pinned_game = app, game
            self.settled_revision = -1
            self.last_considered = None
            self.save()
        return True

    def receipt(self, value):
        if not self.pending or value.get('request_id') != self.pending['command']['request_id']:
            return
        if value.get('game_session_id') != self.pending['command']['game_session_id']:
            return
        pending = self.pending
        self.pending = None
        if value.get('accepted'):
            self.moves += 1
            self.settled_revision = max(self.settled_revision, int(value['revision']))
            if pending.get('run_id') == self.run_id:
                self.latency_ms = round((time.monotonic() - pending['observed_at']) * 1000, 2)
            self.phase_to('receipt_accepted')
            print(json.dumps({'event': 'receipt', 'accepted': True, 'revision': value['revision'], 'latency_ms': self.latency_ms}), flush=True)
        else:
            code = value.get('code', 'rejected')
            if code not in ['stale_revision', 'not_your_turn', 'waiting_for_players', 'game_finished']:
                self.desired = 'paused'
            self.phase_to('receipt_rejected', code)
            self.last_considered = None
        self.save()

    def resolve_pending(self):
        if not self.pending:
            return
        self.next_receipt = time.monotonic() + self.args.receipt_timeout
        command = self.pending['command']
        s = self.snapshot
        if self.pending['app_instance_id'] != self.app_id:
            self.pending = None
            self.phase_to('pending_discarded', 'app_changed')
            self.save()
            return
        if not s.get('in_room') or not s.get('connected', True):
            return
        if command['game_session_id'] != s['game_session_id'] or command['state_epoch'] != s.get('state_epoch', 0):
            self.pending = None
            self.phase_to('pending_discarded', 'room_changed')
            self.save()
            return
        local_session = s.get('local_session_id')
        if local_session and local_session != self.pending.get('local_session_id'):
            # A resumed game transport gets a fresh retry budget. The original
            # command ID/payload stays unchanged, including after a lost receipt.
            self.pending['local_session_id'] = local_session
            self.pending['attempts'] = 0
            self.save()
        result = self.client.call('game.result', {'game_session_id': command['game_session_id'], 'request_id': command['request_id']})
        if 'accepted' in result:
            self.receipt(result)
        elif self.desired == 'running':
            self.send_pending()

    def send_pending(self):
        if self.pending.get('attempts', 0) >= 3:
            self.desired = 'paused'
            self.phase_to('paused', 'receipt_timeout_resume_to_retry')
            self.save()
            return
        self.pending['attempts'] = self.pending.get('attempts', 0) + 1
        self.save()
        result = self.client.call('game.submit', self.pending['command'])
        if not result.get('queued'):
            self.phase_to('waiting_connection', result.get('code', 'not_queued'))
        else:
            self.phase_to('waiting_receipt')
        self.next_receipt = time.monotonic() + min(30, self.args.receipt_timeout * (2 ** (self.pending['attempts'] - 1)))

    def consider(self):
        if not self.context_matches():
            return
        s = self.snapshot
        if self.pending:
            if time.monotonic() >= self.next_receipt:
                self.resolve_pending()
            return
        if s['view'].get('finished'):
            self.phase_to('finished')
            if self.args.once and not self.pending:
                self.stopping = True
            return
        if self.desired == 'paused':
            self.phase_to('paused')
            return
        if not ready(s):
            self.phase_to('waiting_players' if s.get('connected', True) else 'waiting_connection')
            return
        if int(s['revision']) < self.settled_revision:
            self.phase_to('waiting_snapshot')
            return
        if time.monotonic() < self.next_decision:
            return
        key = (s['app_instance_id'], s['game_session_id'], s.get('state_epoch', 0), s['revision'], self.desired)
        if key == self.last_considered:
            return
        self.last_considered = key
        observed = time.monotonic()
        if self.args.strategy == 'gomoku':
            if s.get('game_id') != 'gomoku':
                self.phase_to('unsupported_game')
                return
            action = gomoku(s)
        else:
            description = self.client.call('game.describe_actions')
            if description.get('context', {}).get('expected_revision') != s['revision']:
                self.refresh()
                self.last_considered = None
                return
            action = first_legal(s, description.get('legal_actions', []))
        if action is None:
            self.phase_to('waiting_turn')
            return
        command = {'game_session_id': s['game_session_id'], 'state_epoch': s.get('state_epoch', 0),
                   'expected_revision': s['revision'], 'request_id': 'player-' + uuid.uuid4().hex, 'action': action}
        self.pending = {'command': command, 'app_instance_id': self.app_id, 'attempts': 0,
                        'local_session_id': s.get('local_session_id'), 'observed_at': observed, 'run_id': self.run_id}
        self.save()  # Crash recovery must retain exactly the original move payload.
        self.send_pending()

    def event(self, message):
        if message.get('method') != 'event':
            return
        event = message.get('params', {})
        if event.get('app_instance_id') != self.app_id or int(event.get('seq', -1)) <= self.seq:
            return
        self.seq = int(event['seq'])
        if event.get('kind') in ['state', 'connection']:
            self.snapshot = event['data']
            if self.pending and self.snapshot.get('local_session_id') != self.pending.get('local_session_id'):
                self.next_receipt = 0
            self.last_considered = None
            self.next_decision = time.monotonic() + self.args.think_delay
            self.save()
        elif event.get('kind') == 'action_result':
            self.receipt(event['data'])

    def game_reconnect(self):
        s = self.snapshot
        if (self.desired != 'running' or s.get('host') or s.get('session_state') != 'disconnected'
                or 'room.reconnect' not in self.methods or time.monotonic() < self.next_game_reconnect):
            return
        self.next_game_reconnect = time.monotonic() + 3
        try:
            self.client.call('room.reconnect', self.room_context())
            self.refresh()
        except RPCError as error:
            if str(error) not in ['already_connected', 'not_resumable', 'stale_room_context']:
                raise
            self.phase_to('waiting_game_reconnect', str(error))

    def run(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = open(str(self.path) + '.lock', 'a')
        os.chmod(self.lock.name, 0o600)
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise ValueError('player_already_running')
        signal.signal(signal.SIGTERM, lambda *_: setattr(self, 'stopping', True))
        signal.signal(signal.SIGINT, lambda *_: setattr(self, 'stopping', True))
        self.save()
        retry_at, backoff = 0, .25
        try:
            while not self.stopping:
                self.control()
                if self.stopping:
                    break
                try:
                    if self.client is None:
                        if time.monotonic() < retry_at:
                            time.sleep(.05)
                            continue
                        self.connect()
                        backoff = .25
                    # Drain already-buffered notifications before making any decision.
                    if self.client.notifications or b'\n' in self.client.buffer:
                        self.event(self.client.next_event())
                        continue
                    readable, _, _ = select.select([self.client.socket], [], [], .02)
                    if readable:
                        self.event(self.client.next_event())
                        continue
                    if time.monotonic() >= self.next_refresh:
                        self.refresh()
                        self.last_considered = None
                    self.game_reconnect()
                    self.consider()
                except (OSError, RPCError, KeyError) as error:
                    # A timed-out RPC connection is never reused; recover with a fresh snapshot and receipt query.
                    if self.client:
                        self.client.close()
                    self.client = None
                    self.phase_to('reconnecting', str(error)[:160])
                    retry_at = time.monotonic() + backoff
                    backoff = min(3, backoff * 2)
        finally:
            if self.client:
                self.client.close()
            self.stopping = True
            if self.phase != 'finished':
                self.phase = 'stopped'
            self.save()
            self.lock.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    start = sub.add_parser('start')
    start.add_argument('--connection', type=Path, required=True)
    start.add_argument('--state', type=Path, required=True)
    start.add_argument('--strategy', choices=['gomoku', 'first_legal'], default='gomoku')
    bootstrap = start.add_mutually_exclusive_group()
    bootstrap.add_argument('--create', action='store_true')
    bootstrap.add_argument('--join', metavar='IP')
    start.add_argument('--game', default='gomoku')
    start.add_argument('--port', type=int, default=27840)
    start.add_argument('--nickname')
    start.add_argument('--follow-rooms', action='store_true')
    start.add_argument('--once', action='store_true')
    start.add_argument('--daemon', action='store_true')
    start.add_argument('--think-delay', type=float, default=.03)
    start.add_argument('--rpc-timeout', type=float, default=2)
    start.add_argument('--receipt-timeout', type=float, default=2)
    for command in ['status', 'pause', 'resume', 'stop']:
        child = sub.add_parser(command)
        child.add_argument('--state', type=Path, required=True)
        if command == 'resume':
            child.add_argument('--adopt-room', action='store_true')
    args = parser.parse_args()
    try:
        if args.command != 'start':
            status = read_json(args.state, {})
            running = is_running(args.state)
            if args.command == 'status':
                status['running'] = running
                print(json.dumps(status, ensure_ascii=False))
                return 0
            if not running:
                raise ValueError('player_not_running')
            desired = {'pause': 'paused', 'resume': 'running', 'stop': 'stopped'}[args.command]
            atomic_json(str(args.state) + '.control', {'run_id': status['run_id'], 'nonce': uuid.uuid4().hex,
                        'desired': desired, 'adopt_room': getattr(args, 'adopt_room', False)})
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline:
                current = read_json(args.state, {})
                if (args.command == 'stop' and not is_running(args.state)) or (args.command != 'stop' and current.get('desired') == desired):
                    print(json.dumps({'accepted': True, 'desired': desired}, ensure_ascii=False))
                    return 0
                time.sleep(.05)
            raise ValueError('control_timeout')
        if args.think_delay < 0 or args.rpc_timeout <= 0 or args.receipt_timeout <= 0:
            raise ValueError('invalid_timing')
        if not isinstance(read_json(args.connection), dict):
            raise ValueError('connection_config_unavailable')
        if args.daemon:
            if is_running(args.state):
                raise ValueError('player_already_running')
            args.state.parent.mkdir(parents=True, exist_ok=True)
            descriptor = os.open(str(args.state) + '.log', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            try:
                process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), *[arg for arg in sys.argv[1:] if arg != '--daemon']], stdin=subprocess.DEVNULL, stdout=descriptor, stderr=subprocess.STDOUT, close_fds=True, start_new_session=True)
            finally:
                os.close(descriptor)
            for _ in range(200):
                status = read_json(args.state, {})
                if status.get('pid') == process.pid and is_running(args.state):
                    print(json.dumps({'started': True, 'pid': process.pid, 'state': str(args.state.resolve())}))
                    return 0
                if process.poll() is not None:
                    raise ValueError('player_start_failed_see_log')
                time.sleep(.025)
            raise ValueError('player_start_timeout')
        Player(args).run()
        return 0
    except (OSError, ValueError, RPCError) as error:
        print(json.dumps({'error': str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
