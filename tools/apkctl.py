#!/usr/bin/env python3
"""Authenticated HTTP self-update client. Tokens stay in the private connection file."""
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import sys


class ApkClient:
    def __init__(self, connection, port=None, host=None):
        self.host = host or connection['host']
        self.port = port or connection.get('apk_http', {}).get('port')
        if not self.port:
            raise ValueError('APK HTTP capability missing; install a 0.1.12+ Debug base first')
        self.token = connection['token']

    def request(self, method, path, body=None, headers=None):
        headers = dict(headers or {})
        headers['Authorization'] = 'Bearer ' + self.token
        connection = http.client.HTTPConnection(self.host, self.port, timeout=30)
        try:
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            raw = response.read(16385)
            if len(raw) > 16384:
                raise ValueError('HTTP response too large')
            result = json.loads(raw)
            if response.status >= 400:
                raise ValueError(f'HTTP {response.status}: {result.get("status", "request_failed")}')
            return result
        finally:
            connection.close()

    def upload(self, path):
        path = Path(path)
        size = path.stat().st_size
        if not 0 < size <= 192 * 1024 * 1024:
            raise ValueError('APK must be between 1 byte and 192 MiB')
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
            stream.seek(0)
            return self.request('POST', '/debug/apk', stream, {
                'Content-Length': str(size), 'Content-Type': 'application/vnd.android.package-archive',
                'X-APK-SHA256': digest.hexdigest(),
            })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', required=True, type=Path)
    parser.add_argument('--host', help='Transport override, e.g. 127.0.0.1 for adb forwarding')
    parser.add_argument('--port', type=int, help='Transport override for the HTTP port')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('upload').add_argument('apk', type=Path)
    for name in ['status', 'install', 'cancel']:
        commands.add_parser(name)
    args = parser.parse_args()
    try:
        client = ApkClient(json.loads(args.connection.read_text()), args.port, args.host)
        if args.command == 'upload':
            result = client.upload(args.apk)
        else:
            method, path = {'status': ('GET', '/debug/apk/status'),
                'install': ('POST', '/debug/apk/install'), 'cancel': ('DELETE', '/debug/apk')}[args.command]
            result = client.request(method, path)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (OSError, ValueError, http.client.HTTPException) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
