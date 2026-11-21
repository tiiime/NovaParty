#!/usr/bin/env python3
"""Join a waiting TCL Gomoku room from an installed iPhone simulator and finish it."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / p) for p in ('tests/devices', 'tests/integration', 'tests/support', 'tools/build', 'tools/dev')]

from debug_integration import ready, submit
from dev_config import adb_path, setting
from ios_simulator import BUNDLE, credentials
from nvctl import Client
from player_integration import wait_for


def run(device, serial, adb_port):
    adb = [adb_path(), '-P', str(adb_port), '-s', serial]
    def tv_read(*args):
        return subprocess.check_output(adb + ['exec-out', *args], timeout=10)

    with tempfile.TemporaryDirectory(prefix='nv-iphone-tv-') as temp:
        phone = Client(credentials(device, Path(temp) / 'iphone.json'))
        tv = Client(json.loads(tv_read('run-as', BUNDLE, 'cat', 'files/debug/connection.json')))
        participating = False
        try:
            room = tv.call('game.snapshot')
            assert room['in_room'] and room['host'] and room['game_id'] == 'gomoku', 'Host Gomoku on the TV first'
            assert room['revision'] == 0 and len(room['players']) == 1, 'Use an empty TV room'
            assert not phone.call('game.snapshot')['in_room'], 'Leave the current simulator room first'
            sid = room['game_session_id']
            phone.call('lan.search')
            discovered = wait_for(lambda: next((r for r in phone.call('lan.status')['rooms'] if r['session_id'] == sid), None))
            assert discovered['game_id'] == 'gomoku'
            assert phone.call('lan.status')['backend'] == 'apple_bonjour'
            invite = tv.call('qr.status')['invite']
            decoded = phone.call('qr.decode_image', {'data': tv.call('qr.image')['data']})['value']
            assert decoded == invite['uri']
            phone.call('qr.join', {'value': decoded})
            wait_for(lambda: phone.call('game.snapshot')['in_room'])
            participating = True
            assert ready(phone)['game_session_id'] == sid
            assert ready(phone)['seat'] == 1 and not phone.call('lan.status')['confirmation']
            print('PASS iPhone Simulator discovers the physical TV via Bonjour and joins its decoded QR invite', flush=True)
            for x in range(5):
                for client, y in ([(tv, 7), (phone, 8)] if x < 4 else [(tv, 7)]):
                    state = ready(client)
                    result, _ = submit(client, state, f'iphone-tv-{state["revision"]}', {'type': 'place', 'x': x + 5, 'y': y})
                    assert result['accepted'], result
                    ready(phone, state['revision'] + 1)
                    ready(tv, state['revision'] + 1)
            end = ready(phone, 9)
            assert end['view']['finished'] and end['view']['winner'] == 0 and end['view'] == ready(tv, 9)['view']
            out = ROOT / 'build/validation/party-arcade'
            out.mkdir(parents=True, exist_ok=True)
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(out / 'iphone-tv-gomoku.png')], check=True, capture_output=True)
            (out / 'tcl-iphone-gomoku.png').write_bytes(tv_read('screencap', '-p'))
            (out / 'iphone-tv-lan.json').write_text(json.dumps({'discovery': 'apple_bonjour', 'qr_image_decoded': True, 'moves': 9, 'matching_final_board': True, 'physical_tv': True, 'iphone_simulator': device, 'physical_camera': False, 'input': 'Debug RPC'}, indent=2) + '\n')
            print('PASS physical TV ↔ iPhone Simulator: 9 moves, same board and winner', flush=True)
            tv.room('room.leave')
        finally:
            if participating and phone.call('room.status')['local_session_id']:
                phone.room('room.leave')
            phone.close()
            tv.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=setting('IOS_SIMULATOR_DEVICE', 'booted'))
    parser.add_argument('--tv-serial', default=setting('TV_ADB_SERIAL'), required=not setting('TV_ADB_SERIAL'))
    parser.add_argument('--tv-adb-port', type=int, default=int(setting('TV_ADB_PORT', '5037')))
    args = parser.parse_args()
    run(args.device, args.tv_serial, args.tv_adb_port)
