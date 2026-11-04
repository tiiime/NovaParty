#!/usr/bin/env python3
"""Validate actual export contents and Debug/Release template runtime gates on macOS."""
import hashlib
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import zipfile
import uuid

from integration import ROOT, GODOT, free_port
import sys
sys.path.insert(0, str(ROOT / 'tools'))
from nvctl import Client


def export(preset, destination):
    result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--export-pack', preset, str(destination)], capture_output=True, text=True, timeout=90)
    assert result.returncode == 0 and 'ERROR:' not in result.stdout + result.stderr, result.stdout + result.stderr


def main():
    templates = Path.home() / 'Library/Application Support/Godot/export_templates/4.6.1.stable/macos.zip'
    with tempfile.TemporaryDirectory(prefix='nv-exports-') as temp:
        temp = Path(temp)
        release_zip = temp / 'release.zip'
        export('Android Release', release_zip)
        with zipfile.ZipFile(release_zip) as archive:
            assert {name.split('/')[1] for name in archive.namelist() if name.startswith('mods/')} == {'gomoku'}
            assert not any(name.startswith(('debug/', 'tests/', 'tools/', 'docs/')) for name in archive.namelist())
            assert all('sdk/' + file in archive.namelist() for file in ['mod_sender.gd', 'peer_mods.gd', 'mod_sharing.gd'])
            assert 'i18n/zh_CN.json' in archive.namelist() and 'i18n/en.json' in archive.namelist()
        packs = {}
        for mode in ['Debug', 'Release']:
            packs[mode] = temp / (mode + '.pck')
            export('Android ' + mode, packs[mode])
        with zipfile.ZipFile(templates) as archive:
            for engine in ['Debug', 'Release']:
                binary = temp / ('engine_' + engine)
                binary.write_bytes(archive.read('macos_template.app/Contents/MacOS/godot_macos_' + engine.lower() + '.universal'))
                binary.chmod(0o755)
                for pack_mode in ['Debug', 'Release']:
                    shutil.copyfile(packs[pack_mode], binary.with_suffix('.pck'))
                    port = free_port()
                    config = temp / f'{engine}_{pack_mode}.json'
                    profile = 'export-smoke-' + uuid.uuid4().hex
                    profile_file = Path.home() / 'Library/Application Support/Godot/app_userdata/NovaParty' / ('profile_' + hashlib.sha256(profile.encode()).hexdigest()[:12] + '.json')
                    with tempfile.TemporaryFile(mode='w+') as output:
                        process = subprocess.Popen([str(binary), '--headless', '--verbose', '--max-fps', '60', '--quit-after', '180', '--log-file', str(temp / 'runtime.log'), '--', f'--profile={profile}', '--debug-bind=127.0.0.1', f'--debug-port={port}', f'--debug-connection={config}'], cwd=temp, stdout=output, stderr=subprocess.STDOUT)
                        try:
                            enabled = engine == pack_mode == 'Debug'
                            # Release stdout can be buffered until normal exit.
                            for _ in range(600):
                                if profile_file.exists() and (not enabled or config.exists()):
                                    break
                                if process.poll() is not None:
                                    break
                                time.sleep(.025)
                            assert profile_file.exists(), 'main scene did not save its unique startup profile'
                            assert process.poll() is None
                            if enabled:
                                client = Client(json.loads(config.read_text()))
                                try:
                                    assert client.call('game.snapshot')['in_room'] is False
                                    assert client.call('device.info')['version'] == '0.1.15'
                                finally:
                                    client.close()
                            else:
                                assert not config.exists()
                                with socket.socket() as sock:
                                    assert sock.connect_ex(('127.0.0.1', port)) != 0
                            assert process.wait(timeout=6) == 0
                        finally:
                            if process.poll() is None:
                                process.terminate()
                                process.wait(timeout=5)
                            profile_file.unlink(missing_ok=True)
                            output.seek(0)
                            text = output.read()
                            assert 'res://app/main.gd' in text and 'SCRIPT ERROR' not in text and 'ERROR:' not in text, text
                    print(f'PASS {engine} template + {pack_mode} export: service={enabled}, main scene loaded', flush=True)
        print('PASS Release export excludes Debug/test/tool files')


if __name__ == '__main__':
    main()
