#!/usr/bin/env python3
"""Optional real TV + iOS Simulator interaction test; device credentials stay local."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

from integration import ROOT, free_port
from dev_config import adb_path, setting
from ios_simulator import credentials
from nvctl import Client, push
from debug_integration import ready, submit
from player_integration import wait_for


def run(device, tv_config, serial, adb_port, manual):
    output = ROOT / 'build/validation'
    mod = ROOT / 'build/mods/gomoku-0.2.0-hot.zip'
    adb = [adb_path(), '-P', str(adb_port), '-s', serial]
    def remote(*keys):
        subprocess.run(adb + ['shell', 'input', 'keyevent', *map(str, keys)], check=True, capture_output=True)
    def capture(name):
        subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(output / ('gomoku-iphone-' + name + '.png'))], check=True, capture_output=True)
        (output / ('gomoku-tv-device-' + name + '.png')).write_bytes(subprocess.check_output(adb + ['exec-out', 'screencap', '-p']))
    with tempfile.TemporaryDirectory(prefix='nv-gomoku-devices-') as temp:
        phone = Client(credentials(device, Path(temp) / 'iphone.json'), timeout=30)
        tv = Client(json.loads(tv_config.read_text()), timeout=30)
        try:
            for client in [phone, tv]:
                state = client.call('game.snapshot')
                if state['in_room']:
                    assert state['view']['finished'], 'device has an unfinished match'
                    client.room('room.leave')
                package = push(client, mod)
                client.call('mods.activate', {'build': package['build']})
            port = free_port()
            host_address = json.loads((Path(temp) / 'iphone.json').read_text())['host']
            phone.room('room.create', {'game_id': 'gomoku', 'nickname': '手机月亮', 'port': port})
            tv.room('room.join', {'game_id': 'gomoku', 'nickname': '电视小星', 'address': host_address, 'port': port})
            ready(phone)
            ready(tv)
            assert tuple(map(int, phone.call('device.info')['version'].split('.'))) >= (0, 1, 8)
            assert tv.call('game.snapshot')['clock']['running_seat'] == 0
            if manual:
                print('TOUCH_READY: tap the center intersection on the iPhone board', flush=True)
                wait_for(lambda: phone.call('game.snapshot')['revision'] == 1, timeout=90)
                assert phone.call('game.snapshot')['view']['board'][7 * 15 + 7] == 0
            else:
                state = phone.call('game.snapshot')
                result, _ = submit(phone, state, 'device-black-0', {'type': 'place', 'x': 7, 'y': 7})
                assert result['accepted']
            wait_for(lambda: tv.call('game.snapshot')['revision'] == 1)
            # Test actual TV focus navigation and confirm, rather than RPC for this move.
            remote(21, 21, 20, 20, 23)
            wait_for(lambda: phone.call('game.snapshot')['revision'] == 2)
            assert phone.call('game.snapshot')['view']['board'][9 * 15 + 5] == 1
            capture('playing')
            for x in range(8, 12):
                actions = [(phone, {'type': 'place', 'x': x, 'y': 7})]
                if x < 11:
                    actions.append((tv, {'type': 'place', 'x': x - 2, 'y': 9}))
                for client, action in actions:
                    state = client.call('game.snapshot')
                    result, _ = submit(client, state, 'device-move-' + str(state['revision']), action)
                    assert result['accepted']
                    wait_for(lambda: phone.call('game.snapshot')['revision'] == state['revision'] + 1 and tv.call('game.snapshot')['revision'] == state['revision'] + 1)
            final = phone.call('game.snapshot')
            assert final['view']['finished'] and final['view']['winner'] == 0
            assert phone.call('mods.status')['view_state']['result_open'] and tv.call('mods.status')['view_state']['result_open']
            capture('result')
            remote(23)
            wait_for(lambda: phone.call('game.snapshot')['view']['rematch_votes'][1])
            assert phone.call('game.snapshot')['view']['finished']
            if manual:
                print('REMATCH_TOUCH_READY: tap Play again on the iPhone result dialog', flush=True)
                wait_for(lambda: phone.call('game.snapshot')['view']['round'] == 2, timeout=90)
            else:
                state = phone.call('game.snapshot')
                result, _ = submit(phone, state, 'device-consent-black', {'type': 'rematch', 'round': 1})
                assert result['accepted']
            wait_for(lambda: tv.call('game.snapshot')['view']['round'] == 2)
            new = phone.call('game.snapshot')
            assert new['game_session_id'] == final['game_session_id'] and new['view']['moves'] == 0
            assert new['clock']['elapsed_ms'][1] == 0
            assert not tv.call('mods.status')['view_state']['result_open']
            capture('rematch')
            report = {'phone_base': phone.call('device.info')['version'], 'tv_base': tv.call('device.info')['version'], 'mod_version': '0.2.0', 'tv_ui_build': tv.call('ui.status')['ui_build'], 'phone_touch': manual, 'tv_dpad_move': True, 'real_winner_dialogs': True, 'tv_dpad_rematch_vote': True, 'phone_touch_rematch': manual, 'consensus_rematch': True, 'authoritative_clock_from_phone': True, 'limits': ['TV 0.1.7 can display host clocks; TV hosting clocks requires 0.1.8']}
            (output / 'gomoku-devices.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
            phone.room('room.leave')
            tv.room('room.leave')
            print('PASS TV/iPhone UI, actual TV remote move/rematch, winner dialogs, phone input and new-round clocks', flush=True)
        finally:
            phone.close()
            tv.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=setting('IOS_SIMULATOR_DEVICE', 'booted'))
    parser.add_argument('--tv-connection', type=Path, required=True)
    parser.add_argument('--tv-serial', default=setting('TV_ADB_SERIAL'), required=not setting('TV_ADB_SERIAL'))
    parser.add_argument('--adb-port', type=int, default=int(setting('TV_ADB_PORT', '5037')))
    parser.add_argument('--manual-touch', action='store_true')
    args = parser.parse_args()
    run(args.device, args.tv_connection, args.tv_serial, args.adb_port, args.manual_touch)
