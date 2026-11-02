#!/usr/bin/env python3
"""Prepare a clean Linux CI checkout for Godot 4.6.1 Android exports."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile
from android_config import editor_settings_path

VERSION = '4.6.1'
CHECKSUMS = {
    'linux.x86_64.zip': 'a76fd0fe1d44a2dd6c065b6f7b434ad75f5593c07bda3d3017f8304f2d069acbcf0f39cb5d0976f0434b56e9ea852032ddbcbdb7e0ce1c75a47e1dacb6794bd7',
    'export_templates.tpz': 'd80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541',
}


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.uname().sysname != 'Linux':
        raise SystemExit('This setup tool is only for a disposable Linux GitHub Actions checkout.')
    root = Path(__file__).resolve().parents[1]
    cache = Path(os.environ['RUNNER_TEMP']) / 'godot'
    cache.mkdir(parents=True, exist_ok=True)
    for suffix, expected in CHECKSUMS.items():
        name = f'Godot_v{VERSION}-stable_{suffix}'
        path = cache / name
        urllib.request.urlretrieve(f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/{name}', path)
        with path.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha512').hexdigest()
        if actual != expected:
            raise ValueError('Godot download checksum mismatch')
    binary = cache / f'Godot_v{VERSION}-stable_linux.x86_64'
    with zipfile.ZipFile(cache / f'Godot_v{VERSION}-stable_linux.x86_64.zip') as z:
        binary.write_bytes(z.read(binary.name))
    binary.chmod(0o755)
    templates = Path.home() / '.local/share/godot/export_templates' / (VERSION + '.stable')
    templates.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(cache / f'Godot_v{VERSION}-stable_export_templates.tpz') as z:
        for name in ['android_debug.apk', 'android_release.apk', 'version.txt']:
            with z.open('templates/' + name) as source, (templates / name).open('wb') as target:
                shutil.copyfileobj(source, target)
    key = Path(os.environ['RUNNER_TEMP']) / 'android-debug.keystore'
    subprocess.run([str(Path(os.environ['JAVA_HOME']) / 'bin/keytool'), '-genkeypair', '-noprompt',
                    '-keystore', str(key), '-alias', 'androiddebugkey', '-storepass', 'android',
                    '-keypass', 'android', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000',
                    '-dname', 'CN=Android Debug,O=Android,C=US'], check=True, capture_output=True)
    key.chmod(0o600)
    settings = editor_settings_path()
    settings.parent.mkdir(parents=True, exist_ok=True)
    values = {'export/android/android_sdk_path': os.environ['ANDROID_HOME'],
              'export/android/java_sdk_path': os.environ['JAVA_HOME'],
              'export/android/debug_keystore': str(key)}
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
                        '\n'.join(f'{k} = {json.dumps(v)}' for k, v in values.items()) + '\n')
    # Android does not use the Apple-only extension. A clean Linux editor cannot
    # load its macOS/iOS binaries, so omit its descriptor in this disposable checkout.
    (root / 'addons/novaparty_bonjour/bonjour.gdextension').unlink()
    with Path(os.environ['GITHUB_ENV']).open('a') as stream:
        stream.write(f'GODOT={binary}\nANDROID_DEBUG_KEYSTORE={key}\n')
    print('Prepared verified Godot downloads, Android templates and editor settings.')


if __name__ == '__main__':
    main()
