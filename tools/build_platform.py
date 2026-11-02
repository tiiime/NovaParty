#!/usr/bin/env python3
"""Export and smoke-test Windows, ad-hoc macOS, or simulator-only iOS packages."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile
from dev_config import godot_path
from nvctl import Client

ROOT = Path(__file__).resolve().parents[1]


def run(command, log):
    print(f'BUILD_PHASE: {log.name}', flush=True)
    with log.open('w') as stream:
        result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=900)
    text = log.read_text(errors='replace')
    if result.returncode or 'ERROR:' in text or 'SCRIPT ERROR:' in text:
        print(text[-16000:])
        raise RuntimeError('Build or runtime check failed: ' + log.name)


def check_content(archive):
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        assert {n.split('/')[1] for n in names if n.startswith('mods/')} == {'gomoku'}
        assert not any(Path(n).name.startswith('.env') or n.startswith(('tools/', 'tests/', 'docs/')) for n in names)
        assert 'debug/service.gd' in names
    print('PASS exported content: only Gomoku, Debug service included, local config excluded')


def inspect_client(connection, expected_backend):
    with connection.open() as stream:
        client = Client(json.load(stream), timeout=10)
    try:
        ui = client.call('ui.status')
        assert ui['screen'] == 'home', ui['screen']
        assert 'gomoku' in ui['game_ids'], ui['game_ids']
        if os.environ.get('GITHUB_ACTIONS') == 'true':
            assert ui['game_ids'] == ['gomoku'], ui['game_ids']
        assert client.call('lan.status')['backend'] == expected_backend
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        client.room('room.create', {'game_id': 'gomoku', 'port': port})
        assert client.call('game.snapshot')['in_room']
        if expected_backend == 'apple_bonjour':
            assert client.call('qr.image')['data']
        client.room('room.leave')
    finally:
        client.close()
    print('PASS packaged runtime: fresh home, game catalog, room create/leave, backend=' + expected_backend)


def desktop_smoke(binary, platform, directory):
    with tempfile.TemporaryDirectory(prefix='nv-packaged-') as temp:
        config = Path(temp)/'connection.json'
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        log = directory/'runtime.log'
        with log.open('w') as stream:
            proc = subprocess.Popen([str(binary), '--headless', '--max-fps', '60', '--quit-after', '600', '--',
                                     '--profile=ci-' + uuid.uuid4().hex, '--debug-bind=127.0.0.1',
                                     f'--debug-port={port}', f'--debug-connection={config}'], stdout=stream, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 20
                while not config.exists() and time.monotonic() < deadline and proc.poll() is None:
                    time.sleep(.1)
                assert config.exists(), log.read_text(errors='replace')
                inspect_client(config, 'apple_bonjour' if platform == 'macos' else 'unavailable')
                assert proc.wait(timeout=20) == 0
            finally:
                if proc.poll() is None:
                    proc.terminate(); proc.wait(timeout=10)
        text = log.read_text(errors='replace')
        assert 'ERROR:' not in text and 'SCRIPT ERROR:' not in text, text


def simulator_smoke(app):
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
    devices = [d for runtime, rows in inventory['devices'].items() if '.iOS-' in runtime for d in rows if d['name'].startswith('iPhone')]
    assert devices, 'No available iPhone simulator runtime on this runner'
    device = next((d for d in devices if d['state'] == 'Booted'), devices[0])
    udid = device['udid']
    print('SIMULATOR_PHASE: boot ' + device['name'], flush=True)
    if device['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', udid], check=True, timeout=60)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True, timeout=240)
    print('SIMULATOR_PHASE: install and launch', flush=True)
    subprocess.run(['xcrun', 'simctl', 'install', udid, str(app)], check=True, timeout=120)
    subprocess.run(['xcrun', 'simctl', 'launch', udid, 'org.novaparty.prototype'], check=True, timeout=60)
    try:
        container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, 'org.novaparty.prototype', 'data'], text=True).strip())
        connection = container/'Documents/debug/connection.json'
        deadline = time.monotonic() + 40
        while not connection.exists() and time.monotonic() < deadline:
            time.sleep(.2)
        assert connection.exists(), 'Simulator app did not expose its Debug startup configuration'
        inspect_client(connection, 'apple_bonjour')
    finally:
        subprocess.run(['xcrun', 'simctl', 'terminate', udid, 'org.novaparty.prototype'], check=False, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['windows', 'macos', 'ios-simulator'], required=True)
    stages = parser.add_mutually_exclusive_group()
    stages.add_argument('--skip-smoke', action='store_true', help='Build/archive only; CI runs startup separately')
    stages.add_argument('--smoke-only', action='store_true', help='Check the previously built application')
    args = parser.parse_args()
    platform = args.platform
    directory = ROOT/'build'/platform
    directory.mkdir(parents=True, exist_ok=True)
    if args.smoke_only:
        if platform == 'ios-simulator':
            simulator_smoke(ROOT/'build/ios/SimulatorBuild/NovaParty.app')
        else:
            binary = directory/'package'/'NovaParty.exe' if platform == 'windows' else directory/'package/NovaParty.app/Contents/MacOS/NovaParty'
            desktop_smoke(binary, platform, directory)
        return
    godot = godot_path()
    run([godot, '--headless', '--editor', '--path', ROOT, '--quit'], directory/'import.log')
    preset = {'windows': 'Windows Debug', 'macos': 'macOS Debug', 'ios-simulator': 'iOS Simulator Debug'}[platform]
    run([godot, '--headless', '--path', ROOT, '--export-pack', preset, directory/'content.zip'], directory/'content.log')
    check_content(directory/'content.zip')
    if platform == 'ios-simulator':
        subprocess.run([sys.executable, '-u', 'tools/build_ios_simulator.py'], cwd=ROOT, check=True, timeout=1800)
        app = ROOT/'build/ios/SimulatorBuild/NovaParty.app'
        info = plistlib.loads((app/'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'org.novaparty.prototype'
        assert info['DTPlatformName'] == 'iphonesimulator'
        subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True, capture_output=True)
        if not args.skip_smoke:
            simulator_smoke(app)
        output = directory/'novaparty-ios-simulator-x86_64.zip'
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(output)], check=True)
    else:
        package = directory/'package'
        package.mkdir(exist_ok=True)
        target = package/('NovaParty.exe' if platform == 'windows' else 'NovaParty.app')
        run([godot, '--headless', '--path', ROOT, '--export-debug', preset, target], directory/'export.log')
        if platform == 'macos':
            binary = next((target/'Contents/MacOS').iterdir())
            subprocess.run(['lipo', str(binary), '-verify_arch', 'arm64', 'x86_64'], check=True)
            frameworks = [p for p in target.rglob('NovaBonjour') if p.is_file()]
            assert frameworks, 'macOS package is missing native Bonjour bridge'
            for framework in frameworks:
                subprocess.run(['lipo', str(framework), '-verify_arch', 'arm64', 'x86_64'], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True, capture_output=True)
            if not args.skip_smoke:
                desktop_smoke(binary, platform, directory)
            output = directory/'novaparty-macos-universal.zip'
            subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(target), str(output)], check=True)
        else:
            assert target.read_bytes()[:2] == b'MZ'
            if not args.skip_smoke:
                desktop_smoke(target, platform, directory)
            output = directory/'novaparty-windows-x64.zip'
            with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as z:
                for path in package.rglob('*'):
                    if path.is_file():
                        z.write(path, path.relative_to(package))
    print('PACKAGE_OK:', output)


if __name__ == '__main__':
    main()
