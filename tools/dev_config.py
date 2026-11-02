"""Local development settings. CLI > process environment > repository .env > defaults.

Only literal KEY=value entries are read; shell commands and variable interpolation
are never evaluated. Do not import this module into exported game code.
"""
import os
from pathlib import Path
import re
import shlex
import shutil

ROOT = Path(__file__).resolve().parents[1]


def load_env(path=ROOT / '.env', environ=None):
    target = os.environ if environ is None else environ
    if not path.exists():
        return
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:].lstrip()
        key, separator, value = line.partition('=')
        key = key.strip()
        if not separator or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key):
            raise ValueError(f'{path.name}:{number}: expected KEY=value')
        try:
            parts = shlex.split(value, comments=True, posix=True)
        except ValueError:
            raise ValueError(f'{path.name}:{number}: invalid quoted value') from None
        if len(parts) > 1:
            raise ValueError(f'{path.name}:{number}: quote values containing spaces')
        target.setdefault(key, parts[0] if parts else '')


load_env()


def setting(name, default=None):
    return os.environ.get(name) or default


def godot_path():
    return str(Path(setting('GODOT') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot').expanduser())


def adb_path():
    configured = setting('ADB')
    if configured:
        return str(Path(configured).expanduser())
    sdk = setting('ANDROID_HOME') or setting('ANDROID_SDK_ROOT')
    if sdk:
        return str(Path(sdk).expanduser() / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb'))
    return shutil.which('adb') or 'adb'
