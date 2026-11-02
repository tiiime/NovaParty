#!/usr/bin/env python3
"""Install checksum-pinned Godot/templates in disposable Windows or Apple CI jobs."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import zipfile

VERSION = '4.6.1'
HASHES = {
    'macos.universal.zip': '59c7fc792c9a7a9b3c877b43fc6bdedfa3618e90f0d7d5fa77edb8d3bd64568af19bdfa6ecc8ec3eeaa17ad9cb65f7c93760de83b485ae4a33a679e730f7ffd9',
    'win64.exe.zip': '67c63291115c66ebe7145415b5aac235e1667e417d6cd3d1975848670a1d31cbfad111c8231cb53195bb62e6e4fde951d97aaca227736a94f93dcbf8f23b1fbb',
    'export_templates.tpz': 'd80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['windows', 'macos', 'ios-simulator'], required=True)
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Run this setup only in a disposable GitHub Actions checkout.')
    root = Path(__file__).resolve().parents[1]
    cache = Path(os.environ['RUNNER_TEMP'])/'godot'
    cache.mkdir(parents=True, exist_ok=True)
    suffix = 'win64.exe.zip' if args.platform == 'windows' else 'macos.universal.zip'
    for kind in [suffix, 'export_templates.tpz']:
        name = f'Godot_v{VERSION}-stable_{kind}'
        path = cache/name
        urllib.request.urlretrieve(f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/{name}', path)
        with path.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha512').hexdigest() != HASHES[kind]:
                raise ValueError('Godot download checksum mismatch')
    editor = cache/f'Godot_v{VERSION}-stable_{suffix}'
    if args.platform == 'windows':
        with zipfile.ZipFile(editor) as z:
            z.extractall(cache)
        binary = cache/f'Godot_v{VERSION}-stable_win64.exe'
        base = Path(os.environ['APPDATA'])/'Godot'
        templates = ['windows_debug_x86_64.exe', 'windows_release_x86_64.exe',
                     'windows_debug_x86_64_console.exe', 'windows_release_x86_64_console.exe']
        # This platform uses manual-IP joining until a Windows native adapter exists.
        (root/'addons/novaparty_bonjour/bonjour.gdextension').unlink()
    else:
        subprocess.run(['ditto', '-x', '-k', str(editor), str(cache)], check=True)
        binary = cache/'Godot.app/Contents/MacOS/Godot'
        binary.chmod(0o755)
        base = Path.home()/'Library/Application Support/Godot'
        templates = ['macos.zip'] + (['ios.zip'] if args.platform == 'ios-simulator' else [])
    destination = base/'export_templates'/f'{VERSION}.stable'
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(cache/f'Godot_v{VERSION}-stable_export_templates.tpz') as z:
        for name in [*templates, 'version.txt']:
            (destination/name).write_bytes(z.read('templates/'+name))
    with Path(os.environ['GITHUB_ENV']).open('a') as stream:
        stream.write(f'GODOT={binary}\n')
    if args.platform != 'windows':
        env = dict(os.environ, GODOT=str(binary))
        # Build macOS before import; the editor itself needs that native library.
        subprocess.run([sys.executable, 'tools/build_bonjour.py', '--platform', 'macos'], cwd=root, env=env, check=True)
        if args.platform == 'ios-simulator':
            for platform in ['simulator', 'ios']:
                subprocess.run([sys.executable, 'tools/build_bonjour.py', '--platform', platform], cwd=root, env=env, check=True)
    print('Prepared verified Godot, selected export templates and native bridges.')


if __name__ == '__main__':
    main()
