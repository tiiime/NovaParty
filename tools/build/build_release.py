#!/usr/bin/env python3
"""Build Release deliverables: Windows standalone EXE, macOS Universal DMG, and iOS arm64 IPA."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / p) for p in ['tools/build', 'tools/dev']]

from dev_config import godot_path


def run(command, log, env=None):
    print(f'BUILD_PHASE: {log.name}', flush=True)
    with log.open('w') as stream:
        result = subprocess.run(
            list(map(str, command)),
            cwd=ROOT,
            stdout=stream,
            stderr=subprocess.STDOUT,
            timeout=1800,
            env=env,
        )
    text = log.read_text(errors='replace')
    if result.returncode:
        print(text[-16000:])
        raise RuntimeError(f'Command failed ({result.returncode}): {log.name}')
    return text


def run_godot(command, log):
    text = run(command, log)
    if 'ERROR:' in text or 'SCRIPT ERROR:' in text:
        print(text[-16000:])
        raise RuntimeError('Godot reported errors during: ' + log.name)
    return text


def check_release_content(archive):
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        assert {n.split('/')[1] for n in names if n.startswith('mods/')} == {'gomoku'}, names
        assert not any(
            Path(n).name.startswith('.env')
            or n.startswith(('debug/', 'tools/', 'tests/', 'docs/', 'skills/'))
            for n in names
        ), 'Release archive contains forbidden debug/dev files'
    print('PASS release content: only Gomoku, Debug and local dev files excluded', flush=True)


def user_data_dir():
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support/Godot/app_userdata/NovaParty'
    if os.name == 'nt':
        return Path(os.environ['APPDATA']) / 'Godot/app_userdata/NovaParty'
    return Path.home() / '.local/share/godot/app_userdata/NovaParty'


def smoke_release_desktop(binary, log_dir, standalone_copy=False):
    profile = 'ci-release-' + uuid.uuid4().hex
    profile_file = user_data_dir() / ('profile_' + hashlib.sha256(profile.encode()).hexdigest()[:12] + '.json')
    profile_file.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix='nv-release-smoke-') as temp:
        temp_path = Path(temp)
        exe = binary
        if standalone_copy:
            # Copy ONLY the single .exe to verify the embedded PCK works without any sidecar .pck.
            exe = temp_path / binary.name
            shutil.copy2(binary, exe)
        runtime_log = temp_path / 'runtime.log'
        proc = subprocess.Popen(
            [
                str(exe),
                '--headless',
                '--max-fps',
                '60',
                '--quit-after',
                '180',
                '--log-file',
                str(runtime_log),
                '--',
                f'--profile={profile}',
            ],
            cwd=temp_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            deadline = time.monotonic() + 30
            while not profile_file.exists() and time.monotonic() < deadline and proc.poll() is None:
                time.sleep(0.1)
            stdout_text, _ = proc.communicate(timeout=30)
            log_text = runtime_log.read_text(errors='replace') if runtime_log.exists() else ''
            combined = stdout_text + '\n' + log_text
            (log_dir / 'runtime.log').write_text(combined)
            assert proc.returncode == 0, f'Release binary exited with {proc.returncode}:\n{combined[-8000:]}'
            assert profile_file.exists(), f'Release binary did not initialize main scene:\n{combined[-8000:]}'
            assert 'ERROR:' not in combined and 'SCRIPT ERROR:' not in combined, combined[-8000:]
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
            profile_file.unlink(missing_ok=True)
    print('PASS release desktop smoke: standalone launch and main scene verified', flush=True)


def build_windows(godot, directory, output, skip_smoke=False):
    target = output or (directory / 'NovaParty.exe')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()
    run_godot([godot, '--headless', '--path', ROOT, '--export-release', 'Windows Release', target], directory / 'export.log')
    assert target.is_file() and target.read_bytes()[:2] == b'MZ', 'Invalid Windows PE binary'
    # Verify no companion .pck was emitted alongside the standalone embedded .exe.
    sidecar_pck = target.with_suffix('.pck')
    assert not sidecar_pck.exists(), f'Expected embedded PCK inside EXE, but found {sidecar_pck}'
    if not skip_smoke:
        smoke_release_desktop(target, directory, standalone_copy=True)
    return target


def build_macos(godot, directory, output, skip_smoke=False):
    app = directory / 'NovaParty.app'
    if app.exists():
        shutil.rmtree(app)
    run_godot([godot, '--headless', '--path', ROOT, '--export-release', 'macOS Release', app], directory / 'export.log')
    binary = next((app / 'Contents/MacOS').iterdir())
    subprocess.run(['lipo', str(binary), '-verify_arch', 'arm64', 'x86_64'], check=True)
    frameworks = [p for p in app.rglob('NovaBonjour') if p.is_file()]
    assert frameworks, 'macOS release app is missing native NovaBonjour.framework'
    for framework in frameworks:
        subprocess.run(['lipo', str(framework), '-verify_arch', 'arm64', 'x86_64'], check=True)
    sign_identity = os.environ.get('MACOS_SIGN_IDENTITY', '').strip()
    if sign_identity:
        subprocess.run(
            ['codesign', '--force', '--deep', '--options', 'runtime', '--timestamp', '--sign', sign_identity, str(app)],
            check=True,
        )
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    if not skip_smoke:
        smoke_release_desktop(binary, directory, standalone_copy=False)
    target = output or (directory / 'NovaParty.dmg')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()
    with tempfile.TemporaryDirectory(prefix='nv-dmg-stage-') as stage:
        stage_path = Path(stage)
        subprocess.run(['ditto', str(app), str(stage_path / 'NovaParty.app')], check=True)
        (stage_path / 'Applications').symlink_to('/Applications')
        run(
            [
                'hdiutil',
                'create',
                '-volname',
                'NovaParty',
                '-srcfolder',
                stage_path,
                '-ov',
                '-format',
                'UDZO',
                target,
            ],
            directory / 'dmg.log',
        )
    subprocess.run(['hdiutil', 'verify', str(target)], check=True, capture_output=True)
    print(f'PASS macOS universal DMG verified: {target}', flush=True)
    return target


def build_ios(godot, directory, output):
    xcode_dir = directory / 'xcode'
    if xcode_dir.exists():
        shutil.rmtree(xcode_dir)
    xcode_dir.mkdir(parents=True)
    run_godot([godot, '--headless', '--path', ROOT, '--export-release', 'iOS Release', xcode_dir / 'NovaParty.zip'], directory / 'export.log')

    # Ensure the exported project embeds the iphoneos arm64 NovaBonjour.framework.
    ios_framework = ROOT / 'addons/novaparty_bonjour/ios/NovaBonjour.framework'
    assert (ios_framework / 'NovaBonjour').is_file(), 'Missing iOS arm64 NovaBonjour.framework; run build_apple_bridge.py --platform ios'
    for framework in (xcode_dir / 'NovaParty/dylibs').rglob('NovaBonjour.framework'):
        shutil.rmtree(framework)
        shutil.copytree(ios_framework, framework)

    xcodeproj = xcode_dir / 'NovaParty.xcodeproj'
    target = output or (directory / 'NovaParty.ipa')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()

    team_id = os.environ.get('IOS_TEAM_ID', '').strip()
    profile_specifier = os.environ.get('IOS_PROVISIONING_PROFILE_SPECIFIER', '').strip()
    export_method = os.environ.get('IOS_EXPORT_METHOD', 'ad-hoc').strip() or 'ad-hoc'
    sign_identity = os.environ.get('IOS_CODE_SIGN_IDENTITY', 'Apple Distribution').strip() or 'Apple Distribution'

    if team_id and profile_specifier:
        archive_path = directory / 'NovaParty.xcarchive'
        export_dir = directory / 'ipa-export'
        if archive_path.exists():
            shutil.rmtree(archive_path)
        if export_dir.exists():
            shutil.rmtree(export_dir)
        run(
            [
                'xcodebuild',
                '-project',
                xcodeproj,
                '-scheme',
                'NovaParty',
                '-configuration',
                'Release',
                '-sdk',
                'iphoneos',
                'ARCHS=arm64',
                'ONLY_ACTIVE_ARCH=NO',
                'CODE_SIGN_STYLE=Manual',
                f'DEVELOPMENT_TEAM={team_id}',
                f'PROVISIONING_PROFILE_SPECIFIER={profile_specifier}',
                f'CODE_SIGN_IDENTITY={sign_identity}',
                '-archivePath',
                archive_path,
                'archive',
            ],
            directory / 'xcodebuild-archive.log',
        )
        export_options = directory / 'ExportOptions.plist'
        export_options.write_bytes(
            plistlib.dumps(
                {
                    'method': export_method,
                    'signingStyle': 'manual',
                    'teamID': team_id,
                    'provisioningProfiles': {'org.novaparty.prototype': profile_specifier},
                    'compileBitcode': False,
                }
            )
        )
        run(
            [
                'xcodebuild',
                '-exportArchive',
                '-archivePath',
                archive_path,
                '-exportOptionsPlist',
                export_options,
                '-exportPath',
                export_dir,
            ],
            directory / 'xcodebuild-export.log',
        )
        ipas = list(export_dir.glob('*.ipa'))
        assert ipas, f'xcodebuild -exportArchive did not produce an IPA in {export_dir}'
        shutil.copy2(ipas[0], target)
        signed_note = f'signed ({export_method})'
    else:
        build_dir = directory / 'DeviceBuild'
        if build_dir.exists():
            shutil.rmtree(build_dir)
        run(
            [
                'xcodebuild',
                '-project',
                xcodeproj,
                '-target',
                'NovaParty',
                '-configuration',
                'Release',
                '-sdk',
                'iphoneos',
                'ARCHS=arm64',
                'ONLY_ACTIVE_ARCH=NO',
                'CODE_SIGNING_ALLOWED=NO',
                'CODE_SIGNING_REQUIRED=NO',
                'CODE_SIGN_IDENTITY=',
                f'CONFIGURATION_BUILD_DIR={build_dir}',
                'build',
            ],
            directory / 'xcodebuild.log',
        )
        app = build_dir / 'NovaParty.app'
        assert app.is_dir(), f'Missing built iOS app bundle at {app}'
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'org.novaparty.prototype', info
        assert info.get('DTPlatformName') == 'iphoneos', info
        subprocess.run(['lipo', str(app / 'NovaParty'), '-verify_arch', 'arm64'], check=True)
        frameworks = [p for p in app.rglob('NovaBonjour') if p.is_file()]
        assert frameworks, 'iOS release app is missing native NovaBonjour.framework'
        for framework in frameworks:
            subprocess.run(['lipo', str(framework), '-verify_arch', 'arm64'], check=True)
        assert (app / 'NovaParty.pck').is_file(), 'iOS release app is missing NovaParty.pck'
        with tempfile.TemporaryDirectory(prefix='nv-ipa-stage-') as stage:
            payload = Path(stage) / 'Payload'
            payload.mkdir()
            subprocess.run(['ditto', str(app), str(payload / 'NovaParty.app')], check=True)
            subprocess.run(['zip', '-r', '-y', '-q', str(target.resolve()), 'Payload'], cwd=stage, check=True)
        signed_note = 'unsigned (ready for sideloading or re-signing)'

    with zipfile.ZipFile(target) as archive:
        names = archive.namelist()
        assert 'Payload/NovaParty.app/Info.plist' in names, 'IPA missing Payload/NovaParty.app/Info.plist'
        assert 'Payload/NovaParty.app/NovaParty' in names, 'IPA missing Payload/NovaParty.app/NovaParty'
        assert 'Payload/NovaParty.app/NovaParty.pck' in names, 'IPA missing Payload/NovaParty.app/NovaParty.pck'
    print(f'PASS iOS arm64 IPA ({signed_note}): {target}', flush=True)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['windows', 'macos', 'ios'], required=True)
    parser.add_argument('--output', type=Path, help='Explicit output artifact path (.exe, .dmg, or .ipa)')
    parser.add_argument('--skip-smoke', action='store_true', help='Skip desktop headless smoke launch check')
    args = parser.parse_args()

    platform = args.platform
    directory = ROOT / 'build' / f'{platform}-release'
    directory.mkdir(parents=True, exist_ok=True)

    godot = godot_path()
    run_godot([godot, '--headless', '--editor', '--path', ROOT, '--quit'], directory / 'import.log')
    preset = {'windows': 'Windows Release', 'macos': 'macOS Release', 'ios': 'iOS Release'}[platform]
    run_godot([godot, '--headless', '--path', ROOT, '--export-pack', preset, directory / 'content.zip'], directory / 'content.log')
    check_release_content(directory / 'content.zip')

    output_path = args.output.resolve() if args.output else None
    if platform == 'windows':
        output = build_windows(godot, directory, output_path, skip_smoke=args.skip_smoke)
    elif platform == 'macos':
        output = build_macos(godot, directory, output_path, skip_smoke=args.skip_smoke)
    else:
        output = build_ios(godot, directory, output_path)

    with output.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    print(f'RELEASE_OK: {output}')
    print(f'SHA256: {sha}')


if __name__ == '__main__':
    main()
