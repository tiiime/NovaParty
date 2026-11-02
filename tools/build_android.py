#!/usr/bin/env python3
"""Build a Debug or Release APK on local machines or CI."""
import argparse
from pathlib import Path
from dev_config import godot_path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=godot_path())
    parser.add_argument('--output', type=Path, default=ROOT / 'build/android/novaparty-debug.apk')
    parser.add_argument("--release", action="store_true", help="Release build without Debug services; requires release signing configuration")
    args = parser.parse_args()
    from android_config import resolve
    resolve(debug=not args.release)  # Fail before exporting if signing configuration is incomplete.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    log = args.output.parent / 'export.log'
    with log.open('w') as stream:
        result = subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--export-release' if args.release else '--export-debug', 'Android Release' if args.release else 'Android Debug', str(args.output.resolve())], stdout=stream, stderr=subprocess.STDOUT)
    output = log.read_text()
    if result.returncode or not args.output.is_file() or 'ERROR:' in output:
        print(output)
        raise SystemExit(result.returncode or 1)
    from android_sdk_dex import include_sdk
    include_sdk(args.output, ROOT, debug=not args.release)
    print(f'APK: {args.output}')
    print(f'Export log: {log}')


if __name__ == '__main__':
    main()
