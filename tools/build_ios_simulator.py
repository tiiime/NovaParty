#!/usr/bin/env python3
"""Build a development-only iOS simulator app using the installed Godot/Xcode."""
import argparse
from pathlib import Path
from dev_config import godot_path, setting
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(command, log):
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text()[-12000:], file=sys.stderr)
        raise SystemExit(result.returncode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=godot_path())
    parser.add_argument('--device', default=setting('IOS_SIMULATOR_DEVICE', 'booted'))
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--launch', action='store_true')
    args = parser.parse_args()
    directory = ROOT / 'build/ios'
    directory.mkdir(parents=True, exist_ok=True)
    run([args.godot, '--headless', '--path', str(ROOT), '--export-debug', 'iOS Simulator Debug', str(directory / 'NovaParty.zip')], directory / 'export.log')
    # The export selects the physical-device framework; replace it for this simulator build.
    for framework in (directory / "NovaParty/dylibs").rglob("NovaBonjour.framework"):
        shutil.rmtree(framework)
        shutil.copytree(ROOT / "addons/novaparty_bonjour/simulator/NovaBonjour.framework", framework)
    # Development simulator only: avoid actool/ibtool requiring an exact runtime
    # match when this Mac has SDK 26 but simulator runtime 18 installed.
    project = directory / 'NovaParty.xcodeproj/project.pbxproj'
    project.write_text(''.join(line for line in project.read_text().splitlines(keepends=True) if not any(marker in line for marker in ['/* Launch Screen.storyboard in Resources */', '/* Images.xcassets in Resources */'])))
    info_path = directory / 'NovaParty/NovaParty-Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.pop('UILaunchStoryboardName', None)
    info['UILaunchScreen'] = {}
    info_path.write_bytes(plistlib.dumps(info))
    library = directory / 'NovaParty.xcframework/ios-arm64_x86_64-simulator/libgodot.a'
    architectures = subprocess.check_output(['xcrun', 'lipo', '-info', str(library)], text=True)
    architecture = 'arm64' if re.search(r'\barm64\b', architectures) else 'x86_64'
    if architecture == 'x86_64':
        subprocess.run(['/usr/bin/arch', '-x86_64', '/usr/bin/true'], check=True)
    run(['xcodebuild', '-project', str(directory / 'NovaParty.xcodeproj'), '-target', 'NovaParty', '-configuration', 'Debug', '-sdk', 'iphonesimulator', f'ARCHS={architecture}', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO', f'CONFIGURATION_BUILD_DIR={directory / "SimulatorBuild"}', 'build'], directory / 'xcodebuild.log')
    app = directory / 'SimulatorBuild/NovaParty.app'
    print(f'App: {app}\nArchitecture: {architecture}\nSimulator-only launch branding omitted; no distribution signing.')
    if args.install or args.launch:
        subprocess.run(['xcrun', 'simctl', 'install', args.device, str(app)], check=True)
    if args.launch:
        subprocess.run(['xcrun', 'simctl', 'launch', args.device, 'org.novaparty.prototype'], check=True)


if __name__ == '__main__':
    main()
