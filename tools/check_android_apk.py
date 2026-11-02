#!/usr/bin/env python3
"""Inspect the signed deliverable, including native Debug gates and bundled games."""
import argparse
import hashlib
import subprocess
import zipfile
from android_config import resolve


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()
    config = resolve(args.debug)
    env = dict(__import__('os').environ, JAVA_HOME=str(config.java))
    result = subprocess.run([str(config.build_tools/'apksigner'), 'verify', '--verbose', '--print-certs', args.apk], capture_output=True, text=True, check=True, env=env)
    badging = subprocess.check_output([str(config.build_tools/'aapt'), 'dump', 'badging', args.apk], text=True)
    assert "package: name='org.novaparty.prototype'" in badging
    assert ('application-debuggable' in badging) == args.debug
    assert 'armeabi-v7a' in badging and 'arm64-v8a' in badging
    permissions = subprocess.check_output([str(config.build_tools/'aapt'), 'dump', 'permissions', args.apk], text=True)
    assert ('android.permission.REQUEST_INSTALL_PACKAGES' in permissions) == args.debug
    with zipfile.ZipFile(args.apk) as z:
        names = z.namelist()
        assert not any('/.env' in name or name.startswith('assets/tools/') or name.startswith('assets/tests/') for name in names)
        games = {name.split('/')[2] for name in names if name.startswith('assets/mods/')}
        assert games == {'gomoku'}, games
        dex = b''.join(z.read(name) for name in names if name.startswith('classes') and name.endswith('.dex'))
        assert (b'Lorg/novaparty/debug/ApkUpdateServer;' in dex) == args.debug
        assert b'Lorg/novaparty/sdk/LanDiscovery;' in dex
        assert b'Lorg/novaparty/sdk/JoinQRCode;' in dex
    with open(args.apk, 'rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    print('PASS signed APK: package, architectures, Debug gates, native bridges, only Gomoku and no local config')
    print('SHA256:', sha)
    for line in result.stdout.splitlines():
        if 'certificate SHA-256 digest:' in line:
            print(line)


if __name__ == '__main__':
    main()
