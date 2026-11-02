#!/usr/bin/env python3
"""Observe the installed iOS app: real animation, localized boot and room transition."""
import argparse
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import time

from ios_simulator import credentials, BUNDLE
from player_integration import wait_for
from integration import ROOT, free_port
from dev_config import setting
from nvctl import Client


def run(device):
    output = ROOT / 'build/validation'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nv-home-ios-') as temp:
        config = Path(temp) / 'iphone.json'
        client = Client(credentials(device, config))
        def reboot(locale):
            nonlocal client
            old = client.call('device.info')['app_instance_id']
            client.close()
            subprocess.run(['xcrun', 'simctl', 'terminate', device, BUNDLE], check=True, capture_output=True)
            subprocess.run(['xcrun', 'simctl', 'launch', device, BUNDLE, '--', '--locale=' + locale], check=True, capture_output=True)
            wait_for(lambda: credentials(device, config)['app_instance_id'] != old)
            client = Client(json.loads(config.read_text()))
            return client.call('ui.status')
        def screenshot(name):
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(output / name)], check=True, capture_output=True)
        try:
            before = reboot('zh_CN')
            assert before['screen'] == 'home' and before['locale'].startswith('zh')
            assert before['title'] == '星星大作战' and before['start_label'] == '开始游戏'
            assert not before['reduced_motion'] and before['animation_processing']
            time.sleep(1.2)
            after = client.call('ui.status')
            assert after['motion_time'] > before['motion_time'] + .8
            assert after['orbits'] != before['orbits']
            screenshot('iphone-home-zh.png')
            video = output / 'iphone-home-motion.mp4'
            with tempfile.TemporaryFile() as log:
                recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', '--force', str(video)], stdout=log, stderr=subprocess.STDOUT)
                time.sleep(6)
                recorder.send_signal(signal.SIGINT)
                assert recorder.wait(timeout=15) == 0
            assert video.stat().st_size > 10000
            print('PASS iOS Chinese boot and live orbit animation; 6-second recording', flush=True)
            english = reboot('en')
            assert english['locale'] == 'en' and english['title'] == 'NovaParty' and english['start_label'] == 'Start game'
            screenshot('iphone-home-en.png')
            client.room('room.create', {'game_id': 'gomoku', 'port': free_port()})
            state = client.call('game.snapshot')
            assert state['in_room'] and state['revision'] == 0
            ui = client.call('ui.status')
            assert ui['screen'] == 'game' and not ui['animation_processing']
            time.sleep(.2)
            frozen = client.call('ui.status')['motion_time']
            time.sleep(.5)
            assert client.call('ui.status')['motion_time'] == frozen
            screenshot('iphone-game-en.png')
            client.room('room.leave')
            assert client.call('ui.status')['screen'] == 'home'
            time.sleep(.3)
            assert client.call('ui.status')['motion_time'] > frozen
            reboot('zh_CN')
            screenshot('iphone-home-zh.png')
            (output / 'home-ios.json').write_text(json.dumps({'version': client.call('device.info')['version'], 'device': device, 'locale_boots': ['zh_CN', 'en'], 'live_orbits': True, 'hidden_animation_pauses': True, 'returns_home': True, 'recording_seconds': 6, 'limits': ['iOS Simulator only', 'Reduced-motion persistence tested in Godot UI suite']}, ensure_ascii=False, indent=2))
            print('PASS iOS English boot, real room entry pauses decoration, leave resumes home', flush=True)
        finally:
            client.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=setting('IOS_SIMULATOR_DEVICE', 'booted'))
    run(parser.parse_args().device)
