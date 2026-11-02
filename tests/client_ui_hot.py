#!/usr/bin/env python3
"""Exercise the production bootstrap and authenticated UI updates over real TCP."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import zipfile

from integration import ROOT, GODOT, free_port
from debug_integration import ready, rejected
sys.path.insert(0, str(ROOT / 'tools'))
from nvctl import Client, push, RPCError
from pack_client_ui import pack
from pack_mod import pack as pack_game_mod


@contextlib.contextmanager
def shell(directory, mods=()):
    directory.mkdir(parents=True, exist_ok=True)
    config = directory / 'connection.json'
    config.unlink(missing_ok=True)
    args = [GODOT, '--headless', '--path', str(ROOT), '--', '--profile=' + str(directory), '--debug-bind=127.0.0.1', '--debug-port=' + str(free_port()), '--debug-connection=' + str(config)]
    with (directory / 'process.log').open('w+') as log:
        proc = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, GODOT_EDITOR_CUSTOM_FEATURES='novaparty_debug'))
        client = None
        try:
            for _ in range(200):
                log.seek(0)
                output = log.read()
                assert proc.poll() is None and 'SCRIPT ERROR' not in output and 'ERROR:' not in output, output
                if config.exists():
                    try:
                        client = Client(json.loads(config.read_text()))
                        client.call('ui.updates')
                        break
                    except (OSError, RPCError):
                        if client:
                            client.close()
                        client = None
                time.sleep(.05)
            assert client, output
            for game in mods:
                fixture = directory / (game + '.zip')
                pack_game_mod(ROOT / 'mods' / game, fixture, hot=True)
                build = push(client, fixture)
                client.call('mods.activate', {'build': build['build']})
            yield client, proc
        finally:
            if client:
                client.close()
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)
            log.seek(0)
            output = log.read()
            assert 'SCRIPT ERROR' not in output and 'ERROR:' not in output, output


def variant(base, output, name, transform=lambda files, prefix: None):
    with zipfile.ZipFile(base) as archive:
        old = archive.namelist()[0].split('/')[1]
        prefix = 'ui_versions/' + name + '/'
        files = {}
        for path in archive.namelist():
            value = archive.read(path)
            if path.endswith(('.gd', '.json')):
                value = value.replace(old.encode(), name.encode())
            files[path.replace(old, name)] = value
    transform(files, prefix)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path, value in files.items():
            archive.writestr(path, value)
    return output


def localized(files, prefix):
    for language, label in [('zh_CN', '开始游戏 · 更新验证'), ('en', 'Start game · updated')]:
        path = prefix + 'i18n/' + language + '.json'
        data = json.loads(files[path])
        data['START_GAME'] = label
        files[path] = json.dumps(data, ensure_ascii=False).encode()
    path = prefix + 'app/main.gd'
    files[path] = files[path].replace(b'Color("eef4ff")', b'Color("e7f8f1")')


def not_ready(files, prefix):
    path = prefix + 'app/main.gd'
    files[path] = files[path].replace(b'ui_ready = true', b'ui_ready = false')


def bad_catalog(files, prefix):
    files[prefix + 'i18n/en.json'] = b'[]'


def wrong_engine(files, prefix):
    path = prefix + 'manifest.json'
    data = json.loads(files[path])
    data['engine'] = 'unsupported'
    files[path] = json.dumps(data).encode()


def run():
    with tempfile.TemporaryDirectory(prefix='nv-client-ui-') as temp:
        temp = Path(temp)
        base = pack(temp / 'base.zip')
        state_run = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--script', 'tests/client_ui_state.gd', '--', '--ui-package=' + str(base), '--profile=ui-state-' + str(temp), '--debug-bind=127.0.0.1', '--debug-port=' + str(free_port()), '--debug-connection=' + str(temp / 'state.json')], capture_output=True, text=True, timeout=30, env=dict(os.environ, GODOT_EDITOR_CUSTOM_FEATURES='novaparty_debug'))
        state_log = state_run.stdout + state_run.stderr
        assert state_run.returncode == 0 and 'ERROR:' not in state_log and 'failures=0' in state_log, state_log
        print('PASS setup/settings/join page state, selected cover, language, motion preference and focus preservation', flush=True)
        good = variant(base, temp / 'updated.zip', 'u_updated', localized)
        bad = variant(base, temp / 'not-ready.zip', 'u_not_ready', not_ready)
        malformed = variant(base, temp / 'bad-catalog.zip', 'u_bad_catalog', bad_catalog)
        incompatible = variant(base, temp / 'wrong-engine.zip', 'u_wrong_engine', wrong_engine)
        directory = temp / 'host'
        with shell(directory, mods=['hidden_cards']) as (host, _), shell(temp / 'guest', mods=['hidden_cards']) as (guest, _):
            assert host.call('debug.capabilities')['hot_update']['client_ui']
            original = host.call('ui.status')
            assert original['ui_build'] == 'builtin:client'
            updated = push(host, good, 'ui')['build']
            bad_build = push(host, bad, 'ui')['build']
            for invalid in [malformed, incompatible]:
                try:
                    push(host, invalid, 'ui')
                    raise AssertionError('invalid UI package accepted')
                except RPCError as error:
                    assert str(error) in ['invalid_ui_catalog', 'incompatible_ui_manifest'], str(error)
            # UI preparation failure must leave the current tree/catalogs and TCP alive.
            rejected(host, 'ui.activate', {'build': bad_build}, 'ui_prepare_failed')
            assert host.call('ui.status')['ui_build'] == 'builtin:client'
            assert host.call('ui.status')['start_label'] == original['start_label']
            app_id = host.call('device.info')['app_instance_id']
            host.call('ui.activate', {'build': updated})
            assert host.call('ui.status')['start_label'].endswith(('更新验证', 'updated'))
            assert host.call('device.info')['app_instance_id'] == app_id
            host.call('ui.rollback')
            assert host.call('ui.status')['ui_build'] == 'builtin:client'
            for game in ['gomoku', 'hidden_cards']:
                port = free_port()
                host.room('room.create', {'game_id': game, 'port': port})
                guest.room('room.join', {'game_id': game, 'port': port, 'address': '127.0.0.1'})
                before = ready(host)
                other = ready(guest)
                context = host.call('room.status')
                view_state = host.call('mods.status')['view_state']
                host.call('events.subscribe')
                result = host.call('ui.activate', {'build': updated})
                assert result['session_preserved']
                after = host.call('game.snapshot')
                for key in ['game_session_id', 'state_epoch', 'revision', 'view', 'seat', 'players']:
                    assert after[key] == before[key], key
                assert host.call('room.status')['local_session_id'] == context['local_session_id']
                assert host.call('room.status')['room_generation'] == context['room_generation']
                assert host.call('mods.status')['view_state'] == view_state, (game, view_state, host.call('mods.status')['view_state'])
                assert guest.call('game.snapshot')['view'] == other['view']
                # Submit a real move after reattachment; the guest must still receive it.
                description = host.call('game.describe_actions')
                action = description['legal_actions'][0]
                command = dict(game_session_id=after['game_session_id'], state_epoch=after['state_epoch'], expected_revision=after['revision'], action=action, request_id='ui-hot-' + game)
                response = host.call('game.submit', command)
                assert response['queued']
                for _ in range(100):
                    if host.call('game.snapshot')['revision'] > after['revision']:
                        break
                    time.sleep(.03)
                assert host.call('game.snapshot')['revision'] == after['revision'] + 1
                host.call('ui.rollback')
                assert host.call('ui.status')['screen'] == 'game'
                assert host.call('game.snapshot')['revision'] == after['revision'] + 1
                host.room('room.leave')
                guest.room('room.leave')
            host.call('ui.activate', {'build': updated})
            print('PASS UI upload, version/catalog rejection, prepare failure, live swaps, rollback and real moves in both games', flush=True)
        with shell(directory) as (host, _):
            assert host.call('ui.status')['ui_build'] == updated
            assert host.call('ui.status')['start_label'].endswith(('更新验证', 'updated'))
            assert host.call('ui.updates')['previous']['client'] == 'builtin:client'
            host.call('ui.rollback')
            assert host.call('ui.status')['ui_build'] == 'builtin:client'
            print('PASS UI restart restore and rollback to packaged UI', flush=True)
        # Model a process interrupted inside candidate preparation; next boot avoids it.
        (directory / 'ui-hot/booting.json').write_text(json.dumps({'build': bad_build, 'fallback': updated}))
        with shell(directory) as (host, _):
            assert host.call('ui.status')['ui_build'] == updated
            assert not (directory / 'ui-hot/booting.json').exists()
            print('PASS interrupted UI preparation falls back to last working build', flush=True)


if __name__ == '__main__':
    run()
