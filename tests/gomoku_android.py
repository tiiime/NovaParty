#!/usr/bin/env python3
"""Physical Android host + TV guest. Operator supplies two real adb touch inputs."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from integration import ROOT, free_port
sys.path.insert(0, str(ROOT / 'tools'))
from dev_config import adb_path, setting
from nvctl import Client, push
from debug_integration import ready, submit
from player_integration import wait_for


def run(phone_config, tv_config, serial, tv_serial, tv_adb_port):
    output = ROOT / 'build/validation'
    phone_data = json.loads(phone_config.read_text())
    phone = Client(phone_data, timeout=30)
    tv = Client(json.loads(tv_config.read_text()), timeout=30)
    def tv_key(*keys):
        subprocess.run([adb_path(), '-P', str(tv_adb_port), '-s', tv_serial, 'shell', 'input', 'keyevent', *map(str, keys)], check=True, capture_output=True)
    def capture(name):
        (output / ('gomoku-android-' + name + '.png')).write_bytes(subprocess.check_output([adb_path(), '-s', serial, 'exec-out', 'screencap', '-p']))
    try:
        assert tuple(map(int, phone.call('device.info')['version'].split('.'))) >= (0, 1, 8)
        for client in [phone, tv]:
            assert not client.call('game.snapshot')['in_room']
            build = push(client, ROOT / 'build/mods/gomoku-0.2.0-hot.zip')
            client.call('mods.activate', {'build': build['build']})
        if 'game_ids' not in phone.call('ui.status'):
            build = push(phone, ROOT / 'build/ui/client-ui-0.1.8.zip', 'ui')
            phone.call('ui.activate', {'build': build['build']})
        port = free_port()
        # Do not overwrite the real phone owner's existing nickname.
        phone.room('room.create', {'game_id': 'gomoku', 'port': port})
        tv.room('room.join', {'game_id': 'gomoku', 'address': phone_data['host'], 'port': port})
        ready(phone)
        ready(tv)
        capture('ready')
        print('ANDROID_TOUCH_READY: tap the center intersection', flush=True)
        wait_for(lambda: phone.call('game.snapshot')['revision'] == 1, timeout=90)
        assert phone.call('game.snapshot')['view']['board'][7 * 15 + 7] == 0
        wait_for(lambda: tv.call('game.snapshot')['revision'] == 1)
        tv_key(21, 21, 20, 20, 23)
        wait_for(lambda: phone.call('game.snapshot')['revision'] == 2)
        assert phone.call('game.snapshot')['view']['board'][9 * 15 + 5] == 1
        capture('playing')
        for x in range(8, 12):
            steps = [(phone, {'type': 'place', 'x': x, 'y': 7})]
            if x < 11:
                steps.append((tv, {'type': 'place', 'x': x - 2, 'y': 9}))
            for client, action in steps:
                state = client.call('game.snapshot')
                result, _ = submit(client, state, 'android-' + str(state['revision']), action)
                assert result['accepted']
                wait_for(lambda: phone.call('game.snapshot')['revision'] == state['revision'] + 1 and tv.call('game.snapshot')['revision'] == state['revision'] + 1)
        final = phone.call('game.snapshot')
        assert final['view']['finished'] and phone.call('mods.status')['view_state']['result_open']
        capture('result')
        tv_key(23)
        wait_for(lambda: phone.call('game.snapshot')['view']['rematch_votes'][1])
        capture('result-waiting')
        print('ANDROID_REMATCH_READY: tap the yellow rematch button', flush=True)
        wait_for(lambda: phone.call('game.snapshot')['view']['round'] == 2, timeout=90)
        wait_for(lambda: tv.call('game.snapshot')['view']['round'] == 2)
        state = phone.call('game.snapshot')
        assert state['game_session_id'] == final['game_session_id'] and state['view']['moves'] == 0
        assert state['clock']['elapsed_ms'][1] == 0
        assert tv.call('mods.status')['view_state']['cursor'] == [7, 7]
        capture('rematch')
        (output / 'gomoku-android.json').write_text(json.dumps({'phone_base': phone.call('device.info')['version'], 'phone_model': phone.call('device.info')['model'], 'tv_base': tv.call('device.info')['version'], 'real_android_adb_touch_move': True, 'real_android_adb_touch_rematch': True, 'tv_dpad_move': True, 'tv_dpad_consent': True, 'clock_from_android_host': True, 'new_round_same_session': True, 'mod_version': '0.2.0'}, ensure_ascii=False, indent=2) + '\n')
        phone.room('room.leave')
        tv.room('room.leave')
        print('PASS physical Android touch move/rematch, TV remote input, winning dialog, authoritative clocks and round reset', flush=True)
    finally:
        phone.close()
        tv.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phone-connection', type=Path, required=True)
    parser.add_argument('--tv-connection', type=Path, required=True)
    parser.add_argument('--serial', default=setting('ANDROID_SERIAL'), required=not setting('ANDROID_SERIAL'))
    parser.add_argument('--tv-serial', default=setting('TV_ADB_SERIAL'), required=not setting('TV_ADB_SERIAL'))
    parser.add_argument('--tv-adb-port', type=int, default=int(setting('TV_ADB_PORT', '5037')))
    args = parser.parse_args()
    run(args.phone_connection, args.tv_connection, args.serial, args.tv_serial, args.tv_adb_port)
