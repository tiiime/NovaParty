#!/usr/bin/env python3
"""Run against an already installed, booted iOS Simulator development app."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

from hot_integration import peer, make_build, state_key
from debug_integration import ready, submit
from integration import ROOT, free_port
from dev_config import setting
from player_integration import start, stop_if_running, finished, wait_for, read_json, is_running
from nvctl import Client, push

BUNDLE = 'org.novaparty.prototype'


def credentials(device, destination):
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data'], text=True).strip())
    source = container / 'Documents/debug/connection.json'
    value = wait_for(lambda: json.loads(source.read_text()) if source.exists() else None)
    destination.write_text(json.dumps(value))
    destination.chmod(0o600)
    return value


def run(device):
    artifact = ROOT / 'build/validation'
    artifact.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nv-ios-') as directory:
        directory = Path(directory)
        config = directory / 'iphone.connection.json'
        ios = Client(credentials(device, config))
        info = ios.call('device.info')
        assert info['os'] == 'iOS', info
        # This test owns its simulator room. Re-running leaves only that room.
        if ios.call('room.status')['local_session_id']:
            ios.room('room.leave')
        if ios.call('mods.status')['active'].get('gomoku'):
            ios.call('mods.activate', {'build': 'builtin:gomoku'})
        port = free_port()
        with peer(directory / 'desktop', port, 'lobby') as (desktop, desktop_config):
            ios.room('room.create', {'game_id': 'gomoku', 'nickname': 'iPhone模拟器', 'port': port})
            desktop.room('room.join', {'game_id': 'gomoku', 'nickname': '桌面测试', 'address': '127.0.0.1', 'port': port})
            hs, gs = ready(ios), ready(desktop)
            for client, action in [(ios, {'type': 'place', 'x': 7, 'y': 7}), (desktop, {'type': 'place', 'x': 8, 'y': 7})]:
                receipt, _ = submit(client, client.call('game.snapshot'), 'ios-manual-' + str(client.call('game.snapshot')['revision']), action)
                assert receipt['accepted']
            before = ios.call('game.snapshot')
            original = before['build_id']
            build = push(ios, make_build(directory, 'ios-green', color='68a97c'))
            activated = ios.call('mods.activate', {'build': build['build']})
            after = ios.call('game.snapshot')
            assert activated['presentation_only'] and activated['view_state']['board_color'] == '68a97c'
            assert state_key(before) == state_key(after) and after['app_instance_id'] == before['app_instance_id']
            time.sleep(.3)
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(artifact / 'iphone-hot-update.png')], check=True, capture_output=True)
            rolled = ios.call('mods.rollback', {'game_id': 'gomoku'})
            assert ios.call('game.snapshot')['build_id'] == original
            assert state_key(before) == state_key(ios.call('game.snapshot'))
            ios.call('mods.activate', {'build': build['build']})
            print('PASS iOS nonempty board hot-update/rollback; process, room, seat, rules and revision preserved', flush=True)
            states = [directory / 'ios-player.json', directory / 'desktop-player.json']
            try:
                start(states[0], config, once=True)
                start(states[1], desktop_config, once=True)
                result = finished(ios, 120)
                for state in states:
                    wait_for(lambda: not is_running(state))
                assert result['view'] == ready(desktop)['view']
                assert sum(read_json(s)['moves_accepted'] for s in states) + 2 == result['revision']
                stats = [{'moves': read_json(s)['moves_accepted'], 'last_policy_to_receipt_ms': read_json(s)['latency_ms']} for s in states]
                print('PASS iOS ↔ desktop detached Gomoku:', result['revision'], 'moves;', stats, flush=True)
            finally:
                for state in states:
                    stop_if_running(state)
            ios.room('room.leave')
            desktop.room('room.leave')
            # Restart iOS to check its private-file Mod activation restoration.
            old_instance = ios.call('room.status')['app_instance_id']
            ios.close()
            subprocess.run(['xcrun', 'simctl', 'terminate', device, BUNDLE], check=True, capture_output=True)
            subprocess.run(['xcrun', 'simctl', 'launch', device, BUNDLE], check=True, capture_output=True)
            wait_for(lambda: credentials(device, config)['app_instance_id'] != old_instance)
            ios = Client(json.loads(config.read_text()))
            ios.room('room.create', {'game_id': 'gomoku', 'port': port})
            assert ios.call('game.snapshot')['build_id'] == build['build_id']
            assert ios.call('mods.status')['active']['gomoku'] == build['build']
            ios.call('mods.rollback', {'game_id': 'gomoku'})
            ios.room('room.leave')
            print('PASS iOS force-stop/relaunch restores active Mod; rollback to bundled version', flush=True)
            # iPhone as guest: validates both peer roles and private hands.
            desktop.room('room.create', {'game_id': 'hidden_cards', 'port': port})
            ios.room('room.join', {'game_id': 'hidden_cards', 'address': '127.0.0.1', 'port': port})
            host, guest = ready(desktop), ready(ios)
            assert set(host['view']['hand']).isdisjoint(guest['view']['hand'])
            assert all(key not in guest['view'] for key in ['hands', 'deck'])
            states = [directory / 'ios-cards.json', directory / 'desktop-cards.json']
            try:
                start(states[0], config, 'first_legal', once=True)
                start(states[1], desktop_config, 'first_legal', once=True)
                cards = finished(ios)
                for state in states:
                    wait_for(lambda: not is_running(state))
                assert cards['revision'] == 6 and cards['view'] == ready(desktop)['view']
                print('PASS iOS guest private-hand game: 6 moves, filtered information only', flush=True)
            finally:
                for state in states:
                    stop_if_running(state)
            ios.room('room.leave')
            desktop.room('room.leave')
            (artifact / 'ios-simulator.json').write_text(json.dumps({'os': info['os'], 'version': info['version'], 'simulator': device, 'gomoku_revision': result['revision'], 'players': stats, 'private_hand_revision': cards['revision'], 'hot_update': True, 'rollback': True, 'restart_restoration': True, 'limitations': ['Simulator only; no physical iPhone validation', 'x86_64 via Rosetta; unsigned development app']}, ensure_ascii=False, indent=2))
            time.sleep(.3)
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(artifact / 'iphone-lobby.png')], check=True, capture_output=True)
        ios.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=setting('IOS_SIMULATOR_DEVICE', 'booted'))
    run(parser.parse_args().device)
