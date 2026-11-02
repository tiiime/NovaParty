#!/usr/bin/env python3
"""Android HTTP updater checks; requires our running Debug app and an adb-forwarded HTTP port."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from dev_config import adb_path, setting
from apkctl import ApkClient


def expect_error(call, expected):
    try:
        call()
    except ValueError as error:
        assert expected in str(error), str(error)
    else:
        raise AssertionError('expected ' + expected)
    print('PASS rejected ' + expected, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', type=Path, required=True)
    parser.add_argument('--port', type=int, default=29843)
    parser.add_argument('--apk', type=Path, default=ROOT / 'build/android/novaparty-0.1.12-debug.apk')
    parser.add_argument('--release', type=Path, default=ROOT / 'build/android/novaparty-0.1.12-release.apk')
    parser.add_argument('--serial', default=setting('ANDROID_EMULATOR_SERIAL', 'emulator-5554'))
    parser.add_argument('--upload-valid', action='store_true', help='Finally upload valid APK and trigger Android installation UI')
    args = parser.parse_args()
    descriptor = b'Lorg/novaparty/debug/ApkUpdateServer;'
    for path, expected in [(args.apk, True), (args.release, False)]:
        with zipfile.ZipFile(path) as archive:
            present = any(descriptor in archive.read(name) for name in archive.namelist() if name.endswith('.dex'))
            assert present == expected, (path, present)
    print('PASS native APK updater included only in Debug DEX', flush=True)
    connection = json.loads(args.connection.read_text())
    client = ApkClient(connection, args.port)
    bad = dict(connection, token='0' * 64)
    expect_error(lambda: ApkClient(bad, args.port).request('GET', '/debug/apk/status'), '401')
    expect_error(lambda: client.request('POST', '/debug/apk/install'), 'no_pending_apk')
    expect_error(lambda: client.request('POST', '/debug/apk', b'x', {'Content-Length': '201326593'}), 'apk_size_limit')
    expect_error(lambda: client.request('POST', '/debug/apk', b'x'), 'sha256_required')
    expect_error(lambda: client.request('POST', '/debug/apk', b'x', {'X-APK-SHA256': '0' * 64}), 'sha256_mismatch')
    time.sleep(.1)
    expect_error(lambda: client.request('POST', '/debug/apk', b'x', {'X-APK-SHA256': hashlib.sha256(b'x').hexdigest()}), 'invalid_apk')
    expect_error(lambda: client.upload(args.release), 'debug_apk_required')
    old = ROOT / 'build/android/novaparty-0.1.11-debug.apk'
    if old.is_file():
        expect_error(lambda: client.upload(old), 'version_downgrade')
    sdk = Path.home() / 'Library/Android/Sdk'
    build_tools = sorted((sdk / 'build-tools').iterdir(), key=lambda p: tuple(map(int, p.name.split('.'))))[-1]
    java = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin')
    # Test signing key is temporary and unrelated to the user's production keys.
    with tempfile.TemporaryDirectory(prefix='nv-apk-negative-') as temp:
        temp = Path(temp)
        key = temp / 'other.jks'
        subprocess.run([str(java/'keytool'), '-genkeypair', '-keystore', str(key), '-storepass', 'test-only',
            '-keypass', 'test-only', '-alias', 'test', '-dname', 'CN=Updater Test', '-keyalg', 'RSA', '-validity', '1'],
            check=True, capture_output=True)
        foreign = temp / 'foreign.apk'
        subprocess.run([str(build_tools/'apksigner'), 'sign', '--ks', str(key), '--ks-pass', 'pass:test-only',
            '--key-pass', 'pass:test-only', '--out', str(foreign), str(args.apk)], check=True, capture_output=True,
            env=dict(__import__('os').environ, JAVA_HOME=str(java.parent)))
        expect_error(lambda: client.upload(foreign), 'signature_mismatch')
        other = temp / 'other.apk'
        with zipfile.ZipFile(args.apk) as source, zipfile.ZipFile(other, 'w') as out:
            for info in source.infolist():
                if info.filename.startswith('META-INF/'): continue
                body = source.read(info.filename)
                if info.filename == 'AndroidManifest.xml':
                    before = 'org.novaparty.prototype'.encode('utf-16-le')
                    assert before in body
                    body = body.replace(before, 'org.novaparty.prototypx'.encode('utf-16-le'))
                out.writestr(info, body)
        subprocess.run([str(build_tools/'apksigner'), 'sign', '--ks', str(key), '--ks-pass', 'pass:test-only',
            '--key-pass', 'pass:test-only', str(other)], check=True, capture_output=True,
            env=dict(__import__('os').environ, JAVA_HOME=str(java.parent)))
        expect_error(lambda: client.upload(other), 'package_mismatch')
    files = subprocess.check_output([adb_path(),'-s',args.serial,'shell','run-as','org.novaparty.prototype',
        'ls','files/debug/apk'], text=True).splitlines()
    assert 'update.apk' not in files and 'upload.part' not in files, files
    print('PASS rejected APKs leave no installable payload or partial file', flush=True)
    if args.upload_valid:
        print(client.upload(args.apk), flush=True)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            state = client.request('GET','/debug/apk/status')
            if state['state'] in ['settings_required', 'awaiting_confirmation', 'failed']: break
            time.sleep(.2)
        assert state['state'] in ['settings_required', 'awaiting_confirmation'], state
        print('APK_INSTALL_READY ' + json.dumps(state), flush=True)


if __name__ == '__main__':
    main()
