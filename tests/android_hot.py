#!/usr/bin/env python3
"""Android smoke test: requires an installed Debug app hosting a fresh Gomoku room."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from integration import ROOT, GODOT
from debug_integration import submit
from hot_integration import state_key
sys.path.insert(0, str(ROOT / 'tools'))
from dev_config import adb_path, setting
from nvctl import Client, push
from pack_mod import pack


def wait_state(client, predicate):
    for _ in range(120):
        value = client.call('game.snapshot')
        if predicate(value):
            return value
        time.sleep(.05)
    raise AssertionError(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', type=Path, required=True)
    parser.add_argument('--serial', default=setting('ANDROID_SERIAL'), required=not setting('ANDROID_SERIAL'))
    parser.add_argument('--adb-server-port', type=int)
    parser.add_argument('--artifact-prefix', default='android')
    parser.add_argument('--remote-first-move', action='store_true', help='Use D-pad directions and center for the first move')
    parser.add_argument('--adb', default=adb_path())
    parser.add_argument('--restart', action='store_true', help='After finishing, verify persisted build across force-stop/relaunch')
    parser.add_argument('--create-tap', default='145,985', help='Previously observed create-button coordinates for this test phone')
    args = parser.parse_args()
    config = json.loads(args.connection.read_text())
    client = Client(config)
    def adb(*arguments):
        server_args = ['-P', str(args.adb_server_port)] if args.adb_server_port else []
        return subprocess.check_output([args.adb, *server_args, '-s', args.serial, *arguments])
    bot = None
    with tempfile.TemporaryDirectory(prefix='nv-android-hot-') as temp, tempfile.TemporaryFile(mode='w+') as log:
        try:
            state = client.call('game.snapshot')
            assert state['in_room'] and state['host'] and state['revision'] == 0
            old_pid = adb('shell', 'pidof', 'org.novaparty.prototype').strip()
            bot = subprocess.Popen([GODOT, '--headless', '--path', str(ROOT), '--log-file', str(Path(temp) / 'bot.log'), '--script', 'tests/bot.gd', '--', 'gomoku', '27840', config['host'], '120'], stdout=log, stderr=subprocess.STDOUT)
            state = wait_state(client, lambda s: len(s.get('players', [])) == 2)
            if args.remote_first_move:
                cursor = client.call('mods.status')['view_state']['cursor']
                for _ in range(int(cursor[0])):
                    adb('shell', 'input', 'keyevent', '21')
                for _ in range(int(cursor[1])):
                    adb('shell', 'input', 'keyevent', '19')
                adb('shell', 'input', 'keyevent', '23')
            else:
                receipt, _ = submit(client, state, 'android-hot-before', {'type': 'place', 'x': 0, 'y': 0})
                assert receipt['accepted']
            before = wait_state(client, lambda s: s.get('revision') == 2)
            assert before['view']['board'][0] == 0 and before['view']['board'][15] == 1
            before_view = client.call('mods.status')['view_state']
            source = Path(temp) / 'gomoku'
            shutil.copytree(ROOT / 'mods/gomoku', source)
            (source / 'theme.json').write_text('{"board_color":"4b85b4"}\n')
            destination = ROOT / 'build/hot/gomoku-blue.zip'
            pack(source, destination, hot=True)
            build = push(client, destination)['build']
            activated = client.call('mods.activate', {'build': build})
            assert activated['view_state']['board_color'] == '4b85b4'
            assert activated['view_state']['command_connections'] == 1
            assert activated['view_state']['cursor'] == before_view['cursor']
            assert activated['view_state']['focused'] == before_view['focused']
            after = client.call('game.snapshot')
            assert state_key(before) == state_key(after)
            assert adb('shell', 'pidof', 'org.novaparty.prototype').strip() == old_pid
            (ROOT / 'build/validation').mkdir(exist_ok=True)
            assert args.artifact_prefix.isidentifier()
            (ROOT / f'build/validation/{args.artifact_prefix}-hot-update.png').write_bytes(adb('exec-out', 'screencap', '-p'))
            assert client.call('mods.rollback', {'game_id': 'gomoku'})['view_state']['board_color'] == 'd8b477'
            client.call('mods.activate', {'build': build})
            for x in range(1, 5):
                state = wait_state(client, lambda s: s['view']['turn'] == 0)
                receipt, _ = submit(client, state, f'android-hot-after-{x}', {'type': 'place', 'x': x, 'y': 0})
                assert receipt['accepted']
                wait_state(client, lambda s: s['revision'] >= receipt['revision'] and (s['view']['turn'] == 0 or s['view']['finished']))
            final = client.call('game.snapshot')
            assert final['view']['finished'] and final['view']['winner'] == 0 and final['revision'] == 9
            assert bot.wait(timeout=8) == 0
            log.seek(0)
            text = log.read()
            assert 'BOT_FINISHED' in text and 'SCRIPT ERROR' not in text, text
            print('PASS Android LAN hot update + rollback: same PID, nonempty board/revision/seat unchanged, full 9-move match completed', flush=True)
            if args.restart:
                old_instance = after['app_instance_id']
                client.close()
                adb('shell', 'am', 'force-stop', 'org.novaparty.prototype')
                adb('shell', 'am', 'start', '-n', 'org.novaparty.prototype/com.godot.game.GodotAppLauncher')
                for _ in range(100):
                    time.sleep(.1)
                    raw = adb('exec-out', 'run-as', 'org.novaparty.prototype', 'cat', 'files/debug/connection.json')
                    fresh = json.loads(raw)
                    if fresh['app_instance_id'] != old_instance:
                        break
                else:
                    raise AssertionError('new credentials not generated')
                args.connection.write_bytes(raw)
                args.connection.chmod(0o600)
                client = Client(fresh)
                assert client.call('mods.status')['active']['gomoku'] == build
                # Credentials are written before Android's first rendered/input-ready frame.
                time.sleep(1.0)
                x, y = args.create_tap.split(',')
                adb('shell', 'input', 'tap', x, y)
                wait_state(client, lambda s: s.get('in_room'))
                assert client.call('mods.status')['view_state']['board_color'] == '4b85b4'
                assert client.call('mods.rollback', {'game_id': 'gomoku'})['view_state']['board_color'] == 'd8b477'
                adb('shell', 'input', 'keyevent', '4')
                wait_state(client, lambda s: not s.get('in_room'))
                print('PASS Android force-stop/relaunch restores active build; rollback verified; returned device to lobby', flush=True)
        finally:
            client.close()
            if bot and bot.poll() is None:
                bot.terminate()
                bot.wait(timeout=5)


if __name__ == '__main__':
    main()
