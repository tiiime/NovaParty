#!/usr/bin/env python3
"""Two Android devices over real Bluetooth LE: scan, catalog, join and play without TCP.

Works on two physical phones or two emulators that share the netsim Bluetooth medium
(start both from the same host). Both devices need the current Debug APK installed.

  python3 tests/devices/bluetooth_devices.py --host emulator-5556 --guest emulator-5554
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / p) for p in ['tools/dev', 'tests/integration']]

from dev_config import adb_path
from nvctl import Client
from player_integration import wait_for
from debug_integration import submit

PACKAGE = 'org.novaparty.prototype'
PERMISSIONS = ['BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT', 'BLUETOOTH_ADVERTISE', 'ACCESS_FINE_LOCATION']


def adb(serial, *args, **kwargs):
    return subprocess.run([adb_path(), '-s', serial, *args], check=True, capture_output=True, **kwargs).stdout


def launch(serial, local_port, apk=None):
    if apk:
        adb(serial, 'install', '-r', str(apk))
    adb(serial, 'shell', 'am', 'force-stop', PACKAGE)
    for permission in PERMISSIONS:
        # Test setup grants what the in-app prompt would ask the player for.
        subprocess.run([adb_path(), '-s', serial, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.' + permission], capture_output=True)
    adb(serial, 'shell', 'run-as', PACKAGE, 'rm', '-f', 'files/debug/connection.json')
    adb(serial, 'shell', 'am', 'start', '-n', PACKAGE + '/com.godot.game.GodotAppLauncher')
    config = None
    for _ in range(150):
        time.sleep(0.2)
        raw = subprocess.run([adb_path(), '-s', serial, 'exec-out', 'run-as', PACKAGE, 'cat', 'files/debug/connection.json'], capture_output=True).stdout
        try:
            config = json.loads(raw)
            break
        except ValueError:
            continue
    assert config, serial + ': no debug credentials'
    adb(serial, 'forward', 'tcp:%d' % local_port, 'tcp:%d' % int(config['port']))
    config.update(host='127.0.0.1', port=local_port)
    client = Client(config, timeout=20)
    wait_for(lambda: client.call('ui.status')['screen'] == 'home', timeout=20)
    return client


def snapshot(client):
    return client.call('game.snapshot')


def place(client, request_id, x, y):
    result, _ = submit(client, snapshot(client), request_id, {'type': 'place', 'x': x, 'y': y})
    assert result['accepted'], result


def screenshot(serial, name):
    target = ROOT / 'build/validation/bluetooth' / (name + '.png')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(adb(serial, 'exec-out', 'screencap', '-p'))


def run(args):
    report = {'host': args.host, 'guest': args.guest}
    host = launch(args.host, 29861, args.apk)
    guest = launch(args.guest, 29862, args.apk)
    for name, client in [('host', host), ('guest', guest)]:
        status = client.call('ble.status')
        assert status['backend'] == 'android_ble', status
        client.call('ble.request_access')
        wait_for(lambda: client.call('ble.status')['state'] == 'on', timeout=10)
        report[name + '_state'] = 'on'

    host.room('room.create', {'game_id': 'gomoku', 'port': 27850})
    sid = snapshot(host)['game_session_id']
    wait_for(lambda: host.call('ble.status')['advertising'], timeout=10)
    print('BLE host advertising NP' + sid[:6], flush=True)

    guest.call('lan.search')
    started = time.time()
    wait_for(lambda: any(d['code'] == sid[:6] for d in guest.call('ble.status')['devices']), timeout=30)
    device = next(d for d in guest.call('ble.status')['devices'] if d['code'] == sid[:6])
    report['scan_seconds'] = round(time.time() - started, 1)
    report['rssi'] = device['rssi']
    rows = guest.call('lan.status')['rooms']
    report['listed_as'] = 'bluetooth' if any(r.get('transport') == 'ble' for r in rows) else 'lan'
    screenshot(args.guest, 'guest-search')
    print('BLE guest found host in %.1fs (rssi %s, listed as %s)' % (report['scan_seconds'], device['rssi'], report['listed_as']), flush=True)

    started = time.time()
    guest.call('lan.inspect', {'address': 'ble:' + device['key'], 'port': 0})
    # The built-in Gomoku matches by rules fingerprint, so no download confirmation is needed.
    wait_for(lambda: snapshot(guest).get('in_room') and snapshot(guest).get('game_session_id') == sid, timeout=60)
    wait_for(lambda: len(snapshot(host)['players']) == 2 and snapshot(host)['players'][1]['connected'], timeout=20)
    report['join_seconds'] = round(time.time() - started, 1)
    links = host.call('ble.status')['links']
    assert links and all(link.startswith('p:') for link in links), links
    print('BLE guest joined in %.1fs over %s' % (report['join_seconds'], links), flush=True)

    started = time.time()
    place(host, 'ble-host-1', 7, 7)
    wait_for(lambda: snapshot(guest)['revision'] == 1, timeout=15)
    place(guest, 'ble-guest-1', 8, 7)
    wait_for(lambda: snapshot(host)['revision'] == 2 and snapshot(guest)['revision'] == 2, timeout=15)
    report['two_moves_seconds'] = round(time.time() - started, 1)
    screenshot(args.host, 'host-game')
    screenshot(args.guest, 'guest-game')
    print('BLE moves crossed both directions in %.1fs' % report['two_moves_seconds'], flush=True)

    # Heartbeats keep the link alive while idle.
    time.sleep(12)
    assert snapshot(host)['players'][1]['connected'] and guest.call('room.status').get('connection_state', 'connected') != 'disconnected'
    report['idle_link_kept_seconds'] = 12

    guest.room('room.leave')
    wait_for(lambda: not snapshot(host)['players'][1]['connected'], timeout=20)
    host.room('room.leave')
    wait_for(lambda: not host.call('ble.status')['hosting'], timeout=10)
    report['result'] = 'pass'
    out = ROOT / 'build/validation/bluetooth/report.json'
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('PASS bluetooth devices:', json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--host', required=True, help='adb serial of the hosting device')
    parser.add_argument('--guest', required=True, help='adb serial of the joining device')
    parser.add_argument('--apk', type=Path, help='install this APK on both devices first')
    run(parser.parse_args())
