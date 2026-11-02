#!/usr/bin/env python3
"""Check CI/local SDK resolution and mandatory separate Release credentials."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import android_config as config


class AndroidBuildConfigTests(unittest.TestCase):
    def test_env_paths_and_signing_separation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'sdk/build-tools/35.0.1').mkdir(parents=True)
            (root/'sdk/platforms/android-35').mkdir(parents=True)
            (root/'sdk/platforms/android-35/android.jar').touch()
            debug, release = root/'debug.jks', root/'release.p12'
            debug.touch(); release.touch()
            env = {'ANDROID_HOME': str(root/'sdk'), 'JAVA_HOME': str(root/'jdk'),
                   'ANDROID_DEBUG_KEYSTORE': str(debug)}
            with patch.dict(os.environ, env, clear=True), patch.object(config, 'editor_settings', return_value={}):
                self.assertEqual(config.resolve().keystore, debug)
                with self.assertRaisesRegex(ValueError, 'no Debug signing fallback'):
                    config.resolve(debug=False)
                os.environ.update(ANDROID_KEYSTORE=str(release), ANDROID_KEYSTORE_PASSWORD='fixture-only-password')
                signed = config.resolve(debug=False)
                self.assertEqual(signed.keystore, release)
                self.assertEqual(signed.alias, 'novaparty')
                self.assertEqual(signed.key_password, signed.store_password)
                self.assertNotIn('fixture-only-password', repr(signed))
                os.environ['ANDROID_KEY_PASSWORD'] = 'different-fixture'
                self.assertEqual(config.resolve(False).key_password, 'different-fixture')
                os.environ['ANDROID_BUILD_TOOLS_VERSION'] = '999.0.0'
                with self.assertRaisesRegex(ValueError, 'Install Android SDK'):
                    config.resolve()

    def test_local_editor_settings_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'build-tools/36.0.0').mkdir(parents=True)
            (root/'platforms/android-35').mkdir(parents=True)
            (root/'platforms/android-35/android.jar').touch()
            key = root/'debug.keystore'; key.touch()
            values = {'export/android/android_sdk_path': str(root),
                      'export/android/java_sdk_path': str(root/'jdk'),
                      'export/android/debug_keystore': str(key)}
            with patch.dict(os.environ, {}, clear=True), patch.object(config, 'editor_settings', return_value=values):
                self.assertEqual(config.resolve().build_tools.name, '36.0.0')
                self.assertEqual(config.resolve().keystore, key)


if __name__ == '__main__':
    unittest.main()
