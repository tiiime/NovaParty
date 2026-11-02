#!/usr/bin/env python3
"""Verify local configuration precedence, quoting, and literal-only parsing."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('party_dev_config', ROOT / 'tools/dev_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class DevConfigTests(unittest.TestCase):
    def test_precedence_and_quoting(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / '.env'
            path.write_text('# comment\nexport ADB="/local/sdk with spaces/adb"\nTV_ADB_SERIAL=local-device # comment\nEMPTY=\n')
            env = {'TV_ADB_SERIAL': 'process-device'}
            config.load_env(path, env)
            self.assertEqual(env, {'ADB': '/local/sdk with spaces/adb', 'TV_ADB_SERIAL': 'process-device', 'EMPTY': ''})

    def test_does_not_execute_or_expand(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / '.env'
            marker = Path(folder) / 'unexpected'
            literal = f'$(touch {marker})'
            path.write_text(f'VALUE="{literal}"\nREFERENCE=$VALUE\n')
            env = {}
            config.load_env(path, env)
            self.assertEqual(env['VALUE'], literal)
            self.assertEqual(env['REFERENCE'], '$VALUE')
            self.assertFalse(marker.exists())

    def test_invalid_config_does_not_echo_value(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / '.env'
            for line in ['bad-key=hidden-value', 'ADB="hidden-value', 'ADB=hidden value']:
                path.write_text(line)
                with self.assertRaises(ValueError) as error:
                    config.load_env(path, {})
                self.assertNotIn('hidden', str(error.exception))

    def test_missing_config_and_portable_defaults(self):
        with tempfile.TemporaryDirectory() as folder:
            env = {}
            config.load_env(Path(folder) / 'missing', env)
            self.assertEqual(env, {})
        with patch.dict(os.environ, {'ADB': '~/sdk/adb'}, clear=True):
            self.assertEqual(config.adb_path(), str(Path.home() / 'sdk/adb'))
        with patch.dict(os.environ, {'ANDROID_HOME': '/custom-sdk'}, clear=True):
            self.assertEqual(config.adb_path(), '/custom-sdk/platform-tools/adb')
        with patch.dict(os.environ, {'GODOT': '/custom-godot', 'EMPTY': ''}, clear=True):
            self.assertEqual(config.godot_path(), '/custom-godot')
            self.assertEqual(config.setting('EMPTY', 'default'), 'default')


if __name__ == '__main__':
    unittest.main()
