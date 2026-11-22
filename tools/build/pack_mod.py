#!/usr/bin/env python3
"""Package one trusted source Mod; no native libraries or imported resources yet."""
import argparse
import json
from pathlib import Path
import re
import zipfile
import uuid


def pack(source: Path, output: Path, hot: bool = False):
    manifest = json.loads((source / 'manifest.json').read_text())
    game_id = manifest['id']
    if not isinstance(game_id, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', game_id):
        raise ValueError('invalid id')
    bounds = manifest.get('players', {})
    drop_in = manifest.get('session_mode') == 'drop_in'
    mode = manifest.get('session_mode', '')
    if mode not in ['', 'drop_in', 'fixed']:
        raise ValueError('Unknown session_mode')
    sdk = manifest['sdk']
    low, high = bounds.get('min'), bounds.get('max')
    fixed = mode == 'fixed' and type(low) is int and type(high) is int and 2 <= low <= high <= 8 and (sdk == 2 or low == 2)
    valid_bounds = fixed or (mode == '' and bounds == {'min': 2, 'max': 2}) or (drop_in and low == 1 and type(high) is int and 2 <= high <= 8)
    if type(sdk) is not int or sdk not in (1, 2) or not valid_bounds:
        raise ValueError('Invalid SDK version or player bounds')
    if 'host_start' in manifest and (sdk != 2 or not fixed or manifest['host_start'] is not True):
        raise ValueError('host_start requires an SDK 2 fixed-seat game')
    files = manifest['files']
    if not isinstance(files, list) or len(files) > 128 or len(files) != len(set(files)):
        raise ValueError('invalid file list')
    if manifest['rules'] not in files or manifest['view'] not in files:
        raise ValueError('entrypoints must be listed')
    if 'spectators' in manifest:
        spectators = manifest['spectators']
        if not isinstance(spectators, dict) or set(spectators) != {'max_guests', 'view'}:
            raise ValueError('spectators requires max_guests and view')
        limit, view = spectators['max_guests'], spectators['view']
        if type(limit) is not int or not 1 <= limit <= 8:
            raise ValueError('spectators.max_guests must be an integer from 1 to 8')
        if not isinstance(view, str) or not view.endswith('.gd') or view not in files:
            raise ValueError('spectators.view must be a GDScript entrypoint listed in files')
    for name in files:
        if not isinstance(name, str) or not name or '..' in name or ':' in name or '\\' in name or name.startswith('/'):
            raise ValueError('invalid path')
        path = (source / name).resolve()
        if not path.is_relative_to(source.resolve()) or not path.is_file():
            raise ValueError(f'missing or external file: {name}')
    if hot:
        if 'rules_files' not in manifest or manifest['rules'] not in manifest['rules_files'] or not set(manifest['rules_files']) <= set(files):
            raise ValueError('hot builds require explicit rules_files including every rules dependency')
        manifest['build_id'] = 'b_' + uuid.uuid4().hex
    prefix = f"mod_versions/{game_id}/{manifest['build_id']}" if hot else f"mods/{game_id}"
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        if hot:
            archive.writestr(prefix + '/manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        else:
            archive.write(source / 'manifest.json', prefix + '/manifest.json')
        for name in files:
            archive.write(source / name, prefix + '/' + name)
    print(output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--hot', action='store_true', help='Unique version namespace for network hot updates')
    args = parser.parse_args()
    pack(args.source, args.output, hot=args.hot)
