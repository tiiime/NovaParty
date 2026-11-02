"""Resolve Android build tools and signing settings on developer machines and CI."""
from dataclasses import dataclass, field
import os
from pathlib import Path
import re
import sys
from dev_config import setting


def editor_settings_path():
    if sys.platform == 'darwin':
        base = Path.home() / 'Library/Application Support/Godot'
    elif os.name == 'nt':
        base = Path(os.environ['APPDATA']) / 'Godot'
    else:
        base = Path(setting('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'godot'
    return base / 'editor_settings-4.6.tres'


def editor_settings():
    path = editor_settings_path()
    text = path.read_text() if path.exists() else ''
    return dict(re.findall(r'^([\w/]+) = "([^"\n]*)"$', text, re.M))


@dataclass
class AndroidConfig:
    sdk: Path
    java: Path
    build_tools: Path
    android_jar: Path
    keystore: Path
    alias: str
    store_password: str = field(repr=False)
    key_password: str = field(repr=False)


def resolve(debug=True):
    settings = editor_settings()
    sdk = setting('ANDROID_HOME') or setting('ANDROID_SDK_ROOT') or settings.get('export/android/android_sdk_path')
    java = setting('JAVA_HOME') or settings.get('export/android/java_sdk_path')
    if not sdk or not java:
        raise ValueError('Set ANDROID_HOME and JAVA_HOME, or configure Android SDK / Java paths in Godot.')
    sdk, java = Path(sdk).expanduser(), Path(java).expanduser()
    installed = sorted((p.name for p in (sdk / 'build-tools').glob('*') if re.fullmatch(r'\d+\.\d+\.\d+', p.name)), key=lambda name: tuple(map(int, name.split('.'))))
    tools_version = setting('ANDROID_BUILD_TOOLS_VERSION') or (installed[-1] if installed else '35.0.1')
    platform = setting('ANDROID_PLATFORM_VERSION', '35')
    tools = sdk / 'build-tools' / tools_version
    jar = sdk / 'platforms' / ('android-' + platform) / 'android.jar'
    if not tools.is_dir() or not jar.is_file():
        raise ValueError(f'Install Android SDK build-tools;{tools_version} and platforms;android-{platform}.')
    if debug:
        key = setting('ANDROID_DEBUG_KEYSTORE') or settings.get('export/android/debug_keystore') or str(Path.home() / '.android/debug.keystore')
        alias = setting('ANDROID_DEBUG_KEY_ALIAS', 'androiddebugkey')
        password = setting('ANDROID_DEBUG_KEYSTORE_PASSWORD', 'android')
        key_password = setting('ANDROID_DEBUG_KEY_PASSWORD', password)
    else:
        key = setting('ANDROID_KEYSTORE')
        alias = setting('ANDROID_KEY_ALIAS', 'novaparty')
        password = setting('ANDROID_KEYSTORE_PASSWORD')
        key_password = setting('ANDROID_KEY_PASSWORD', password)
        if not key or not password:
            raise ValueError('Release requires ANDROID_KEYSTORE and ANDROID_KEYSTORE_PASSWORD; no Debug signing fallback.')
    keystore = Path(key).expanduser()
    if not keystore.is_file():
        raise ValueError('Configured Android signing keystore does not exist.')
    return AndroidConfig(sdk, java, tools, jar, keystore, alias, password, key_password)
