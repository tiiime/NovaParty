#!/usr/bin/env python3
"""Exercise real Godot TCP processes, not a Python reimplementation of the rules."""
import contextlib
import json
from pathlib import Path
import socket
import shutil
import sys
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from dev_config import godot_path
GODOT = godot_path()


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


@contextlib.contextmanager
def host(game='hidden_cards', autoplay=False):
    port = free_port()
    with tempfile.TemporaryFile(mode='w+') as log:
        process = subprocess.Popen([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-network-host.log', '--script', 'tools/host.gd', '--', game, str(port), *(['autoplay'] if autoplay else [])], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                log.seek(0)
                output = log.read()
                ready = next((line for line in output.splitlines() if line.startswith('HOST_READY ')), None)
                if ready:
                    yield port, json.loads(ready.removeprefix('HOST_READY '))['fingerprint']
                    break
                if process.poll() is not None:
                    raise AssertionError(output)
                time.sleep(.05)
            else:
                raise AssertionError('host startup timeout: ' + output)
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.seek(0)
            output = log.read()
            assert 'SCRIPT ERROR' not in output and 'ERROR:' not in output, output


class Client:
    def __init__(self, port):
        self.socket = socket.create_connection(('127.0.0.1', port), timeout=3)
        self.buffer = b''

    def send(self, data, fragmented=False):
        encoded = (json.dumps(data, ensure_ascii=False) + '\n').encode()
        if fragmented:
            for byte in encoded:
                self.socket.sendall(bytes([byte]))
        else:
            self.socket.sendall(encoded)

    def receive(self, kind):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            while b'\n' not in self.buffer:
                chunk = self.socket.recv(65536)
                assert chunk, 'connection closed'
                self.buffer += chunk
            line, self.buffer = self.buffer.split(b'\n', 1)
            data = json.loads(line)
            if data['type'] == kind:
                return data
        raise AssertionError('missing ' + kind)

    def close(self):
        self.socket.close()


def hello(fingerprint, **extra):
    return dict(type='hello', protocol=1, fingerprint=fingerprint, player_id='guest', nickname='玩家甲', **extra)


def test_rules():
    result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-rules.log', '--script', 'tests/run.gd'], capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and 'failures=0' in output and 'RULES_RESULT' in output and 'SCRIPT ERROR' not in output and 'ERROR:' not in output, output
    print(output.strip())


def test_ui():
    result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-ui-test.log', '--script', 'tests/ui.gd'], capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and 'UI_RESULT' in output and 'failures=0' in output and 'SCRIPT ERROR' not in output and 'ERROR:' not in output, output
    print(output.strip())


def test_protocol():
    with host() as (port, fingerprint):
        bad = Client(port)
        bad.send(hello('wrong'))
        assert bad.receive('error')['code'] == 'incompatible'
        bad.close()
        client = Client(port)
        client.send(hello(fingerprint), fragmented=True)
        welcome = client.receive('welcome')
        snapshot = client.receive('snapshot')
        assert snapshot['seat'] == 1 and snapshot['players'][1]['nickname'] == '玩家甲'
        view = snapshot['view']
        assert not {'deck', 'hands', 'resume_token'} & view.keys()
        request = dict(type='command', request_id='one', expected_revision=0, action=dict(type='choose', card=view['hand'][0]))
        client.send(request)
        receipt = client.receive('receipt')
        assert receipt['accepted'] and receipt['revision'] == 1
        assert client.receive('snapshot')['revision'] == 1
        client.send(request)
        assert client.receive('receipt') == receipt
        assert client.receive('snapshot')['revision'] == 1
        client.send(dict(request, action=dict(type='choose', card=-1)))
        assert client.receive('receipt')['code'] == 'request_id_reused'
        client.receive('snapshot')
        client.send(dict(request, request_id='stale', expected_revision=0))
        assert client.receive('receipt')['code'] == 'stale_revision'
        client.receive('snapshot')
        client.close()
        time.sleep(.15)
        thief = Client(port)
        thief.send(hello(fingerprint))
        assert thief.receive('error')['code'] == 'invalid_resume_token'
        thief.close()
        resumed = Client(port)
        resumed.send(hello(fingerprint, resume_token=welcome['resume_token']))
        assert resumed.receive('welcome')['seat'] == 1
        recovered = resumed.receive('snapshot')
        assert recovered['revision'] == 1 and recovered['view']['chosen'] == view['hand'][0]
        assert not {'deck', 'hands'} & recovered['view'].keys()
        resumed.close()
        malformed = Client(port)
        malformed.socket.sendall(b'[]\n')
        assert malformed.socket.recv(1) == b''
        malformed.close()
        oversized = Client(port)
        oversized.socket.sendall(b'x' * 65537)
        assert oversized.socket.recv(1) == b''
        oversized.close()
    print('PASS TCP: fragmented UTF-8, compatibility, privacy, deduplication, stale revision, credential resume, invalid frames')


def test_full_games():
    for game in ['gomoku', 'hidden_cards']:
        with host(game, autoplay=True) as (port, _):
            result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-network-bot.log', '--script', 'tests/bot.gd', '--', game, str(port)], capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            assert result.returncode == 0 and 'BOT_FINISHED ' + game in output and 'SCRIPT ERROR' not in output, output
        print('PASS full Godot host/client game:', game)


def test_external_pack():
    sys.path.insert(0, str(ROOT / 'tools'))
    from pack_mod import pack
    with tempfile.TemporaryDirectory(prefix='novaparty-pack-') as temp:
        source = Path(temp) / 'source'
        shutil.copytree(ROOT / 'mods/gomoku', source)
        manifest_path = source / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['id'] = 'pack_probe'
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False))
        package = Path(temp) / 'probe.zip'
        pack(source, package)
        result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-pack-test.log', '--script', 'tests/load_pack.gd', '--', str(package)], capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and 'PACK_LOADED custom_rules_and_view' in output and 'SCRIPT ERROR' not in output, output
        try:
            for phase in ['install', 'restore']:
                result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-install-test.log', '--script', 'tests/install_pack.gd', '--', str(package), phase], capture_output=True, text=True, timeout=10)
                output = result.stdout + result.stderr
                assert result.returncode == 0 and 'INSTALL_PHASE_OK ' + phase in output and 'SCRIPT ERROR' not in output, output
        finally:
            subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--log-file', '/tmp/novaparty-install-cleanup.log', '--script', 'tests/install_pack.gd', '--', str(package), 'cleanup'], capture_output=True, timeout=10, check=True)
    print('PASS external ZIP: dynamic rules/view, private storage installation and fresh-process restoration')


if __name__ == '__main__':
    test_rules()
    test_ui()
    test_protocol()
    test_full_games()
    test_external_pack()
