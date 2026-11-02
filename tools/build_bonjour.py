#!/usr/bin/env python3
"""Build Apple DNS-SD/QR bridges; macOS includes both Intel and Apple Silicon."""
import argparse
from pathlib import Path
from dev_config import godot_path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'addons/novaparty_bonjour'
TARGETS = {
    'macos': ('macosx', [('arm64', 'arm64-apple-macos12'), ('x86_64', 'x86_64-apple-macos12')]),
    'simulator': ('iphonesimulator', [('x86_64', 'x86_64-apple-ios13-simulator')]),
    'ios': ('iphoneos', [('arm64', 'arm64-apple-ios13')]),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['all', *TARGETS], default='all')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='nv-bonjour-') as temp:
        subprocess.run([godot_path(), '--headless', '--dump-gdextension-interface'], cwd=temp, check=True, capture_output=True)
        for name, (sdk, targets) in TARGETS.items():
            if args.platform not in ['all', name]:
                continue
            directory = OUT / name / 'NovaBonjour.framework'
            directory.mkdir(parents=True, exist_ok=True)
            sysroot = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
            binaries = []
            for arch, target in targets:
                binary = Path(temp) / (name + '-' + arch)
                subprocess.run(['xcrun', '--sdk', sdk, 'clang++', '-std=c++17', '-fobjc-arc', '-dynamiclib',
                                '-target', target, '-isysroot', sysroot, '-I', temp, str(ROOT/'native/bonjour/bonjour.mm'),
                                '-framework', 'Foundation', '-framework', 'CoreImage', '-framework', 'ImageIO', '-framework', 'CoreGraphics',
                                *(['-framework', 'UIKit', '-framework', 'AVFoundation'] if sdk != 'macosx' else []),
                                '-install_name', '@rpath/NovaBonjour.framework/NovaBonjour', '-o', str(binary)], check=True)
                binaries.append(str(binary))
            subprocess.run(['xcrun', 'lipo', '-create', *binaries, '-output', str(directory/'NovaBonjour')], check=True)
            info = {'CFBundleIdentifier': 'org.novaparty.bonjour', 'CFBundleName': 'NovaBonjour',
                    'CFBundleExecutable': 'NovaBonjour', 'CFBundlePackageType': 'FMWK',
                    'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0'}
            (directory/'Info.plist').write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--sign', '-', str(directory)], check=True, capture_output=True)
    print('BONJOUR_BUILD_OK')


if __name__ == '__main__':
    main()
