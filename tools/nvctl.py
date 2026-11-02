#!/usr/bin/env python3
"""JSON-only Debug RPC client. No dependencies; credentials never enter argv."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import socket
import sys
import time
import uuid


class RPCError(Exception):
    pass


class Client:
    def __init__(self, connection, timeout=5):
        self.socket = socket.create_connection((connection['host'], connection['port']), timeout)
        self.buffer = b''
        self.counter = 0
        self.notifications = []
        self.timeout = timeout
        self.auth = self.call('auth', {'token': connection['token']})

    def close(self):
        self.socket.close()

    def receive(self):
        while b'\n' not in self.buffer:
            chunk = self.socket.recv(8192)
            if not chunk:
                raise RPCError('connection_closed')
            self.buffer += chunk
            if len(self.buffer.split(b'\n', 1)[0]) > 65536:
                raise RPCError('frame_too_large')
        line, self.buffer = self.buffer.split(b'\n', 1)
        return json.loads(line)

    def call(self, method, params=None):
        self.counter += 1
        request = {'jsonrpc': '2.0', 'id': self.counter, 'method': method, 'params': params or {}}
        encoded = (json.dumps(request, ensure_ascii=False) + '\n').encode()
        if len(encoded) > 65536:
            raise RPCError('frame_too_large')
        self.socket.sendall(encoded)
        deadline = time.monotonic() + self.timeout
        previous_timeout = self.socket.gettimeout()
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('rpc_timeout')
                self.socket.settimeout(remaining)
                message = self.receive()
                if message.get('id') == self.counter:
                    if 'error' in message:
                        raise RPCError(message['error']['message'])
                    return message['result']
                if message.get('method') == 'event':
                    if len(self.notifications) >= 512:
                        raise RPCError('notification_overflow')
                    self.notifications.append(message)
        finally:
            self.socket.settimeout(previous_timeout)

    def room(self, method, params=None):
        command = dict(params or {})
        context = self.call('room.status')
        for key in ['app_instance_id', 'room_generation', 'local_session_id']:
            command.setdefault(key, context[key])
        command.setdefault('request_id', 'room-' + uuid.uuid4().hex)
        return self.call(method, command)

    def next_event(self):
        return self.notifications.pop(0) if self.notifications else self.receive()


def push(client, path, scope="mods"):
    if scope not in ["mods", "ui"]:
        raise RPCError("invalid_upload_scope")
    path = Path(path)
    size = path.stat().st_size
    if not 0 < size <= (64 if scope == "ui" else 16) * 1024 * 1024:
        raise RPCError('package_size_limit')
    data = path.read_bytes()
    begin = client.call(scope + '.upload.begin', {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    if begin.get('existing'):
        return begin
    upload = begin['upload_id']
    try:
        offset = 0
        while offset < len(data):
            chunk = data[offset:offset + begin['chunk_size']]
            result = client.call(scope + '.upload.chunk', {'upload_id': upload, 'offset': offset, 'data': base64.b64encode(chunk).decode()})
            offset = result['offset']
            time.sleep(.02)
        return client.call(scope + '.upload.commit', {'upload_id': upload})
    except (OSError, RPCError):
        try:
            client.call(scope + '.upload.abort', {'upload_id': upload})
        except (OSError, RPCError):
            pass
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', type=Path, required=True, help='Private connection.json retrieved from the device')
    parser.add_argument('--timeout', type=float, default=10)
    parser.add_argument('--activate', action='store_true', help='Activate after mods.push or ui.push upload')
    parser.add_argument('--wait', action='store_true', help='Wait for final game.submit receipt')
    parser.add_argument('--watch', action='store_true', help='Stream subscription notifications as JSON lines')
    parser.add_argument('method')
    parser.add_argument('params', nargs='?', default='{}', help='JSON object, or @request.json (preserve request_id on retries)')
    args = parser.parse_args()
    client = None
    try:
        if args.method in ['mods.push', 'ui.push']:
            if args.wait or args.watch:
                raise RPCError('push_does_not_support_wait_or_watch')
            client = Client(json.loads(args.connection.read_text()), args.timeout)
            scope = args.method.split(".", 1)[0]
            result = push(client, args.params, scope)
            if args.activate:
                result = client.call(scope + '.activate', {'build': result['build']})
            print(json.dumps(result, ensure_ascii=False), flush=True)
            return 0
        if args.activate:
            raise RPCError('activate_flag_requires_mods.push_or_ui.push')
        params = json.loads(Path(args.params[1:]).read_text() if args.params.startswith('@') else args.params)
        if not isinstance(params, dict):
            raise RPCError('params_must_be_object')
        if args.wait and args.method != 'game.submit':
            raise RPCError('wait_requires_game.submit')
        if args.watch and args.method != 'events.subscribe':
            raise RPCError('watch_requires_events.subscribe')
        client = Client(json.loads(args.connection.read_text()), args.timeout)
        if args.wait:
            client.call('events.subscribe')
        result = client.room(args.method, params) if args.method in ['room.create', 'room.join', 'room.leave', 'room.reconnect'] else client.call(args.method, params)
        if args.wait:
            if not result.get('queued'):
                raise RPCError(result.get('code', 'not_queued'))
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                client.socket.settimeout(max(.01, deadline - time.monotonic()))
                event = client.next_event().get('params', {})
                data = event.get('data', {})
                if event.get('kind') == 'action_result' and data.get('request_id') == params['request_id'] and data.get('game_session_id') == params['game_session_id']:
                    result = data
                    break
            else:
                raise RPCError('receipt_timeout_query_game.result')
        print(json.dumps(result, ensure_ascii=False), flush=True)
        if args.watch:
            while True:
                print(json.dumps(client.next_event(), ensure_ascii=False), flush=True)
    except (OSError, ValueError, KeyError, RPCError) as error:
        print(json.dumps({'error': str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0
    finally:
        if client:
            client.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
