#!/usr/bin/env python3
"""Real app UI hot updates over authenticated Debug TCP, while a match stays alive."""
import argparse
import base64
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import sys
import tempfile
import time
import zipfile

from integration import ROOT, GODOT, free_port
from debug_integration import ready, rejected, submit
sys.path.insert(0, str(ROOT / 'tools'))
from nvctl import Client, push
from pack_mod import pack


@contextlib.contextmanager
def peer(directory, game_port, role, visual=False, game='gomoku'):
    directory.mkdir(parents=True, exist_ok=True)
    config = directory / 'connection.json'
    config.unlink(missing_ok=True)
    port = free_port()
    args = [GODOT, *([] if visual else ['--headless']), '--path', str(ROOT), '--log-file', str(directory / 'godot.log'), '--script', 'tests/hot_host.gd', '--', game, str(game_port), role, f'--profile=hot-{directory}', '--debug-bind=127.0.0.1', f'--debug-port={port}', f'--debug-connection={config}']
    if visual:
        args.append('--capture=/tmp/novaparty-hot-update.png')
    with tempfile.TemporaryFile(mode='w+') as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, GODOT_EDITOR_CUSTOM_FEATURES='novaparty_debug'))
        try:
            for _ in range(200):
                log.seek(0)
                text = log.read()
                assert 'SCRIPT ERROR' not in text and process.poll() is None, text
                if 'HOT_READY' in text and config.exists():
                    break
                time.sleep(.05)
            else:
                raise AssertionError(text)
            client = Client(json.loads(config.read_text()))
            try:
                yield client, config
            finally:
                client.close()
        finally:
            process.terminate()
            process.wait(timeout=5)
            log.seek(0)
            text = log.read()
            assert 'SCRIPT ERROR' not in text and 'ERROR:' not in text, text


def make_build(directory, name, color='4b85b4', rules_change=False, invalid_contract=False):
    source = directory / name
    shutil.copytree(ROOT / 'mods/gomoku', source)
    (source / 'theme.json').write_text(json.dumps({'board_color': color}))
    if name == 'blue':
        (source / 'sample.bin').write_bytes(os.urandom(100000))
        manifest = json.loads((source / 'manifest.json').read_text())
        manifest['files'].append('sample.bin')
        (source / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False))
    if rules_change:
        with (source / 'rules.gd').open('a') as file:
            file.write('\n# Deliberate rules build change\n')
    if invalid_contract:
        (source / 'view.gd').write_text('extends Control\nsignal command(action: Dictionary)\n')
    output = directory / (name + '.zip')
    pack(source, output, hot=True)
    return output


def state_key(snapshot):
    return {key: snapshot[key] for key in ['game_session_id', 'state_epoch', 'revision', 'seat', 'view', 'players']}


def test_hot(visual=False):
    if visual:
        Path("/tmp/novaparty-hot-update.png").unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix='nv-hot-') as temp:
        temp = Path(temp)
        blue = make_build(temp, 'blue')
        green = make_build(temp, 'green', color='68a97c')
        rules = make_build(temp, 'rules', rules_change=True)
        bad = make_build(temp, 'bad', invalid_contract=True)
        metadata = make_build(temp, 'metadata')
        manifest_path = temp / 'metadata/manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest.pop('name')
        manifest_path.write_text(json.dumps(manifest))
        pack(temp / 'metadata', metadata, hot=True)
        game_port = free_port()
        host_dir, guest_dir = temp / 'host', temp / 'guest'
        with peer(host_dir, game_port, 'host', visual) as (host, host_config), peer(guest_dir, game_port, 'guest') as (guest, _):
            before, guest_before = ready(host), ready(guest)
            old_instance = before['app_instance_id']
            # Upload lifecycle, offset retries, hash verification and cancellation.
            data = blue.read_bytes()
            begin = host.call('mods.upload.begin', {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
            upload = begin['upload_id']
            rejected(host, 'mods.upload.commit', {'upload_id': upload}, 'upload_incomplete')
            chunk = {'upload_id': upload, 'offset': 0, 'data': base64.b64encode(data[:100]).decode()}
            assert host.call('mods.upload.chunk', chunk)['offset'] == 100
            assert host.call('mods.upload.chunk', chunk)['offset'] == 100
            rejected(host, 'mods.upload.chunk', dict(chunk, offset=101), 'offset_mismatch')
            rejected(host, 'mods.upload.chunk', dict(chunk, data='bad!'), 'invalid_chunk')
            assert host.call('mods.upload.abort', {'upload_id': upload})['aborted']
            rejected(host, 'mods.upload.begin', {'size': 16777217, 'sha256': '0' * 64}, 'invalid_upload')
            begin = host.call('mods.upload.begin', {'size': len(data), 'sha256': '0' * 64})
            for offset in range(0, len(data), 24576):
                host.call('mods.upload.chunk', {'upload_id': begin['upload_id'], 'offset': offset, 'data': base64.b64encode(data[offset:offset+24576]).decode()})
                time.sleep(.02)
            rejected(host, 'mods.upload.commit', {'upload_id': begin['upload_id']}, 'hash_mismatch')
            malformed = temp / 'traversal.zip'
            with zipfile.ZipFile(malformed, 'w') as archive:
                archive.writestr('../escape.txt', 'outside')
            try:
                push(host, malformed)
                raise AssertionError('unsafe ZIP accepted')
            except Exception as error:
                assert str(error) == 'unsafe_zip_path', error
            oversized = temp / 'expanded.zip'
            with zipfile.ZipFile(oversized, 'w') as archive:
                archive.writestr('safe.txt', 'x')
            raw = bytearray(oversized.read_bytes())
            position = raw.find(b'PK\x01\x02')
            struct.pack_into('<I', raw, position + 24, 33554433)
            oversized.write_bytes(raw)
            try:
                push(host, oversized)
                raise AssertionError('expanded size bomb accepted')
            except Exception as error:
                assert str(error) == 'expanded_size_limit', error
            pending = [host.call('mods.upload.begin', {'size': 100, 'sha256': digit * 64})['upload_id'] for digit in ['1', '2']]
            rejected(host, 'mods.upload.begin', {'size': 100, 'sha256': '3' * 64}, 'upload_limit')
            for upload_id in pending:
                host.call('mods.upload.abort', {'upload_id': upload_id})
            # Actual CLI upload and activation changes a raw JSON resource in this live view.
            run = subprocess.run([sys.executable, str(ROOT / 'tools/nvctl.py'), '--connection', str(host_config), '--activate', 'mods.push', str(blue)], capture_output=True, text=True, timeout=20)
            assert run.returncode == 0, run.stderr
            activated = json.loads(run.stdout)
            blue_hash = activated['build']
            assert activated['presentation_only']
            assert activated['view_state']['board_color'] == '4b85b4'
            assert activated['view_state']['cursor'] == [4, 5] and activated['view_state']['focused']
            assert activated['view_state']['command_connections'] == 1
            after = ready(host)
            assert state_key(before) == state_key(after)
            assert state_key(guest_before) == state_key(ready(guest))
            assert after['app_instance_id'] == old_instance
            assert after['presentation_fingerprint'] != before['presentation_fingerprint']
            assert after['rules_fingerprint'] == before['rules_fingerprint']
            # Still play through the normal authority after only one side changes presentation.
            receipt, _ = submit(host, after, 'after-hot-host', {'type': 'place', 'x': 7, 'y': 7})
            assert receipt['accepted']
            receipt, _ = submit(guest, ready(guest, 1), 'after-hot-guest', {'type': 'place', 'x': 0, 'y': 0})
            assert receipt['accepted']
            current = ready(host, 2)
            rules_hash = push(host, rules)['build']
            rejected(host, 'mods.activate', {'build': rules_hash}, 'rules_changed_during_game')
            try:
                push(host, bad)
                raise AssertionError('invalid view contract accepted')
            except Exception as error:
                assert str(error) == 'invalid_view_contract', error
            assert state_key(ready(host, 2)) == state_key(current)
            assert host.call('mods.status')['active']['gomoku'] == blue_hash
            try:
                push(host, metadata)
                raise AssertionError('invalid metadata accepted')
            except Exception as error:
                assert str(error).startswith('invalid_mod:'), error
            # Reusing a namespace with changed bytes is forbidden.
            collision = temp / 'collision.zip'
            with zipfile.ZipFile(blue) as source, zipfile.ZipFile(collision, 'w', zipfile.ZIP_DEFLATED) as target:
                for name in source.namelist():
                    content = source.read(name)
                    if name.endswith('theme.json'):
                        content = b'{"board_color":"000000"}'
                    target.writestr(name, content)
            try:
                push(host, collision)
                raise AssertionError('namespace overwrite accepted')
            except Exception as error:
                assert str(error) == 'build_namespace_reused', error
            # Rollback to builtin, then between two immutable builds.
            rolled = host.call('mods.rollback', {'game_id': 'gomoku'})
            assert rolled['view_state']['board_color'] == 'd8b477'
            green_hash = push(host, green)['build']
            assert host.call('mods.activate', {'build': green_hash})['view_state']['board_color'] == '68a97c'
            host.call('mods.activate', {'build': blue_hash})
            assert host.call('mods.status')['previous']['gomoku'] == green_hash
            assert state_key(ready(host, 2)) == state_key(current)
            # Cache/idempotent package push returns existing build without remounting.
            assert push(host, blue)['existing']
            print('PASS live UI/resource swap: unchanged match, cursor/focus, one signal, continued two-peer play, rollback, bad packages/rules rejected', flush=True)
            if visual:
                for _ in range(60):
                    if Path('/tmp/novaparty-hot-update.png').exists():
                        break
                    time.sleep(.05)
                assert Path('/tmp/novaparty-hot-update.png').is_file()
        # Persisted presentation survives a fresh process. Builtin peer negotiates rules compatibility.
        game_port = free_port()
        with peer(host_dir, game_port, 'host') as (host, _), peer(guest_dir, game_port, 'guest') as (guest, _):
            hs, gs = ready(host), ready(guest)
            assert hs['app_instance_id'] != old_instance
            assert hs['rules_fingerprint'] == gs['rules_fingerprint']
            assert hs['fingerprint'] != gs['fingerprint']
            assert host.call('mods.status')['view_state']['board_color'] == '4b85b4'
            assert host.call('mods.rollback', {'game_id': 'gomoku'})['view_state']['board_color'] == '68a97c'
            receipt, _ = submit(host, hs, 'new-room', {'type': 'place', 'x': 1, 'y': 1})
            assert receipt['accepted']
            ready(guest, 1)
            print('PASS fresh-process restore, rollback, and protocol-2 join with different presentation builds', flush=True)
        # Rule builds can be selected in the lobby for the next game.
        with peer(host_dir, free_port(), 'lobby') as (host, _):
            selected = host.call('mods.activate', {'build': rules_hash})
            assert selected['activated'] and not selected['presentation_only']
            print('PASS changed rules selectable for next match in lobby; no live migration', flush=True)
        cards_source = temp / 'cards_source'
        shutil.copytree(ROOT / 'mods/hidden_cards', cards_source)
        view = cards_source / 'view.gd'
        view.write_text(view.read_text().replace('暗牌比大小（协议示例）', '热更新 · 暗牌比大小'))
        cards_zip = temp / 'cards.zip'
        pack(cards_source, cards_zip, hot=True)
        game_port = free_port()
        with peer(temp / 'cards-host', game_port, 'host', game='hidden_cards') as (host, _), peer(temp / 'cards-guest', game_port, 'guest', game='hidden_cards') as (guest, _):
            hs, gs = ready(host), ready(guest)
            focused = guest.call('mods.status')['view_state']['focused_card']
            receipt, _ = submit(host, hs, 'cards-before-update', {'type': 'choose', 'card': hs['view']['hand'][0]})
            assert receipt['accepted']
            before = ready(guest, 1)
            build = push(guest, cards_zip)['build']
            activated = guest.call('mods.activate', {'build': build})
            assert activated['view_state']['focused_card'] == focused
            assert activated['view_state']['command_connections'] == 1
            assert state_key(ready(guest, 1)) == state_key(before)
            for round_number in range(3):
                if round_number:
                    hs = ready(host, round_number * 2)
                    receipt, _ = submit(host, hs, f'cards-host-{round_number}', {'type': 'choose', 'card': hs['view']['hand'][0]})
                    assert receipt['accepted']
                gs = ready(guest, round_number * 2 + 1)
                assert 'hands' not in gs['view'] and 'deck' not in gs['view']
                receipt, _ = submit(guest, gs, f'cards-guest-{round_number}', {'type': 'choose', 'card': gs['view']['hand'][0]})
                assert receipt['accepted']
            assert ready(host, 6)['view']['finished']
            print('PASS private-card UI hot swap with pending opponent action, card focus preserved, all rounds finished', flush=True)



if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--visual', action='store_true')
    test_hot(parser.parse_args().visual)
