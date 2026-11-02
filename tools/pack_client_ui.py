#!/usr/bin/env python3
"""Package the complete client UI in a unique, portable Godot resource namespace."""
import argparse
import json
from pathlib import Path
from dev_config import godot_path
import subprocess
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GODOT = godot_path()


def pack(output, source=ROOT, build_id=None):
    source, output = Path(source), Path(output)
    build_id = build_id or 'u_' + uuid.uuid4().hex
    if not build_id.isascii() or not build_id.isidentifier():
        raise ValueError('invalid build_id')
    prefix = 'ui_versions/' + build_id + '/'
    files = {}
    with tempfile.TemporaryDirectory(prefix='nv-ui-resources-') as temp:
        run = subprocess.run([GODOT, '--headless', '--path', str(source), '--script', 'tools/ui_resources.gd', '--', '--output=' + temp], capture_output=True, text=True, timeout=90)
        if run.returncode or 'ERROR:' in run.stdout + run.stderr or 'UI_RESOURCES_OK' not in run.stdout:
            raise RuntimeError(run.stdout + run.stderr)
        engine = next(line.removeprefix("UI_ENGINE=") for line in run.stdout.splitlines() if line.startswith("UI_ENGINE="))
        for path in Path(temp).rglob('*.res'):
            files[path.relative_to(temp).as_posix()] = path.read_bytes()
    for path in sorted((source / 'app').rglob('*')):
        if path.suffix not in ['.gd', '.tscn', '.tres', '.gdshader', '.json']:
            continue
        if path.name in ['bootstrap.gd', 'bootstrap.tscn']:
            continue
        name = path.relative_to(source).as_posix()
        text = path.read_text()
        for folder in ['app/', 'assets/ui/', 'assets/fonts/', 'assets/audio/', 'i18n/']:
            text = text.replace('res://' + folder, 'res://' + prefix + folder)
        text = text.replace('const UI_ROOT := "res://"', 'const UI_ROOT := "res://' + prefix.rstrip('/') + '"')
        for extension in ['svg', 'png', 'jpg', 'jpeg', 'webp', 'ttf', 'otf']:
            text = text.replace('.' + extension + '"', '.res"')
        files[name] = text.encode()
    for path in sorted((source / 'i18n').glob('*.json')):
        files[path.relative_to(source).as_posix()] = path.read_bytes()
    for folder in ['assets/ui', 'assets/fonts', 'assets/audio']:
        for path in sorted((source / folder).rglob('*')):
            if path.is_file() and path.suffix not in ['.import', '.uid', '.svg', '.png', '.jpg', '.jpeg', '.webp', '.ttf', '.otf']:
                files[path.relative_to(source).as_posix()] = path.read_bytes()
    manifest = {'kind': 'client_ui', 'ui_api': 1, 'sdk': 1, 'engine': engine, 'entry': 'app/main.gd', 'build_id': build_id, 'files': sorted(files)}
    if len(files) > 128:
        raise ValueError('too many files')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(prefix + 'manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        for name, data in sorted(files.items()):
            archive.writestr(prefix + name, data)
    if output.stat().st_size > 64 * 1024 * 1024:
        output.unlink()
        raise ValueError('UI package exceeds 64 MiB')
    print(output)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--source', type=Path, default=ROOT)
    args = parser.parse_args()
    pack(args.output, args.source)
