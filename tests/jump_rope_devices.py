#!/usr/bin/env python3
"""Android motion capability + iOS simulator display, with an actual adb role tap."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from integration import ROOT, free_port
from dev_config import adb_path, setting
from player_integration import wait_for
from debug_integration import submit
sys.path.insert(0, str(ROOT / 'tools'))
from nvctl import Client, push


def run(serial, device):
    output = ROOT / 'build/validation'
    phone = Client(json.loads(Path('/tmp/novaparty-android.connection.json').read_text()), timeout=30)
    screen_config = json.loads(Path('/tmp/novaparty-iphone.connection.json').read_text())
    screen = Client(screen_config, timeout=30)
    try:
        for client in [phone, screen]:
            assert client.call('device.info')['version'] == '0.1.9'
            assert not client.call('game.snapshot')['in_room']
            build = push(client, ROOT / 'build/mods/jump_rope-0.1.0-hot.zip')
            client.call('mods.activate', {'build': build['build']})
        port = free_port()
        screen.room('room.create', {'game_id': 'jump_rope', 'port': port})
        state = screen.call('game.snapshot')
        result, _ = submit(screen, state, 'screen-role', {'type': 'role', 'role': 'display', 'generation': state['view']['slots'][0]['generation']})
        assert result['accepted']
        phone.room('room.join', {'game_id': 'jump_rope', 'port': port, 'address': screen_config['host']})
        wait_for(lambda: phone.call('game.snapshot').get('in_room', False))
        wait_for(lambda: phone.call('mods.status')['view_state']['sensor_available'], timeout=15)
        def capture(name):
            (output / ('jump-rope-android-' + name + '.png')).write_bytes(subprocess.check_output([adb_path(), '-s', serial, 'exec-out', 'screencap', '-p']))
        capture('role')
        print('ANDROID_CONTROLLER_READY: tap Join as controller', flush=True)
        wait_for(lambda: phone.call('mods.status')['view_state']['role'] == 'controller', timeout=90)
        wait_for(lambda: phone.call('mods.status')['view_state']['sensor_calibrated'], timeout=20)
        wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 1)
        capture('calibrated')
        view = phone.call('mods.status')['view_state']
        assert 5 < view['sensor_baseline'] < 15, view
        subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(output / 'jump-rope-ios-display.png')], check=True, capture_output=True)
        phone.room('room.leave')
        wait_for(lambda: screen.call('mods.status')['view_state']['participants'] == 0)
        screen.room('room.leave')
        report = {'android_base': '0.1.9', 'ios_simulator_base': '0.1.9', 'actual_android_sensor_available': True, 'actual_android_calibration': True, 'baseline_ms2': view['sensor_baseline'], 'actual_adb_role_touch': True, 'ios_display_join_leave': True, 'physical_jumping_tested': False, 'tv_install': 'verification rejected; requires manual 0.1.9 install'}
        (output / 'jump-rope-devices.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print('PASS Android physical sensor/calibration/touch role + iOS display join/leave. Physical jumping not tested.', flush=True)
    finally:
        phone.close()
        screen.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default=setting("ANDROID_SERIAL"), required=not setting("ANDROID_SERIAL"))
    parser.add_argument("--device", default=setting("IOS_SIMULATOR_DEVICE", "booted"))
    args = parser.parse_args()
    run(args.serial, args.device)
