#!/usr/bin/env python3
"""Validate portable UI resources and live swaps inside the installed iOS app."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

from integration import ROOT, free_port
from dev_config import setting
from ios_simulator import BUNDLE, credentials
from debug_integration import ready
from player_integration import wait_for
from client_ui_hot import shell, variant, localized
from nvctl import Client, push


def run(device):
    output = ROOT / 'build/validation'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nv-ios-ui-') as temp:
        temp = Path(temp)
        config = temp / 'iphone.json'
        connection = credentials(device, config)
        client = Client(connection, timeout=20)
        try:
            assert client.call('debug.capabilities')['hot_update']['client_ui']
            original = client.call('device.info')
            assert not client.call('game.snapshot')['in_room']
            base = ROOT / 'build/ui/client-ui.zip'
            base_build = push(client, base, 'ui')['build']
            client.call('ui.activate', {'build': base_build})
            custom = variant(base, temp / 'visual.zip', 'u_ios_visual_' + str(time.time_ns()), localized)
            custom_build = push(client, custom, 'ui')['build']
            client.call('ui.activate', {'build': custom_build})
            assert client.call('ui.status')['start_label'].endswith(('更新验证', 'updated'))
            assert client.call('device.info')['app_instance_id'] == original['app_instance_id']
            time.sleep(.5)
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(output / 'iphone-ui-hot.png')], check=True, capture_output=True)
            # A real remote guest remains connected while the phone swaps its platform UI.
            with shell(temp / 'guest') as (guest, _):
                port = free_port()
                client.room('room.create', {'game_id': 'gomoku', 'port': port})
                guest.room('room.join', {'game_id': 'gomoku', 'port': port, 'address': connection['host']})
                before = ready(client)
                ready(guest)
                result = client.call('ui.rollback')
                assert result['session_preserved']
                after = client.call('game.snapshot')
                for key in ['game_session_id', 'state_epoch', 'revision', 'view', 'players']:
                    assert before[key] == after[key], key
                action = client.call('game.describe_actions')['legal_actions'][0]
                assert client.call('game.submit', dict(game_session_id=after['game_session_id'], state_epoch=after['state_epoch'], expected_revision=after['revision'], action=action, request_id='ios-ui-hot-move'))['queued']
                wait_for(lambda: guest.call('game.snapshot')['revision'] == after['revision'] + 1)
                client.room('room.leave')
                guest.room('room.leave')
            client.call('ui.activate', {'build': custom_build})
            before_restart = client.call('device.info')['app_instance_id']
            client.close()
            subprocess.run(['xcrun', 'simctl', 'terminate', device, BUNDLE], check=True, capture_output=True)
            subprocess.run(['xcrun', 'simctl', 'launch', device, BUNDLE], check=True, capture_output=True)
            wait_for(lambda: credentials(device, config)['app_instance_id'] != before_restart)
            client = Client(json.loads(config.read_text()), timeout=20)
            assert client.call('ui.status')['ui_build'] == custom_build
            assert client.call('ui.status')['start_label'].endswith(('更新验证', 'updated'))
            client.call('ui.rollback')
            assert client.call('ui.status')['ui_build'] == base_build
            client.call('ui.activate', {'build': 'builtin:client'})
            report = {'version': client.call('device.info')['version'], 'device': device, 'ui_api': 1, 'portable_textures_and_font': True, 'localized_ui_swap': True, 'same_tcp_connection': True, 'live_gomoku_and_remote_move': True, 'restart_restore_and_rollback': True, 'final_build': client.call('ui.status')['ui_build'], 'limits': ['iOS Simulator; TV requires new base installation']}
            (output / 'client-ui-ios.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
            print('PASS iOS UI/resources/font update, live TCP session and continued remote play, restart restore and rollback')
        finally:
            client.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=setting('IOS_SIMULATOR_DEVICE', 'booted'))
    run(parser.parse_args().device)
