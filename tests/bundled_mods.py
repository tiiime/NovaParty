#!/usr/bin/env python3
"""Inspect every export preset, boot an isolated export, then import an external Mod."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from dev_config import godot_path
GODOT = godot_path()
from pack_mod import pack


def run():
    token = uuid.uuid4().hex
    probe = ROOT / 'mods' / ('export_probe_' + token)
    probe.mkdir()
    try:
        # Even a future Mod with imported assets must not bypass the allowlist.
        (probe/'probe.gd').write_text('extends RefCounted\n')
        (probe/'manifest.json').write_text('{"id":"export_probe"}')
        (probe/('probe_' + token + '.svg')).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4" fill="red"/></svg>')
        with tempfile.TemporaryDirectory(prefix='nv-bundled-mods-') as temp:
            temp = Path(temp)
            packs = {}
            for preset in ['Android Debug', 'Android Release', 'iOS Simulator Debug']:
                archive = temp/(preset.replace(' ', '-')+'.zip')
                result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--export-pack', preset, str(archive)], capture_output=True, text=True, timeout=90)
                assert result.returncode == 0 and 'ERROR:' not in result.stdout+result.stderr, result.stdout+result.stderr
                with zipfile.ZipFile(archive) as z:
                    names = z.namelist()
                    assert not any(Path(name).name == ".env" or Path(name).name.startswith(".env.") for name in names), "local environment exported"
                    assert {name.split('/')[1] for name in names if name.startswith('mods/')} == {'gomoku'}, names
                    assert not any(token in name or name.startswith('addons/novaparty_export/') for name in names)
                    assert 'mods/gomoku/manifest.json' in names and 'mods/gomoku/rules.gd' in names
                packs[preset] = archive
                print('PASS ' + preset + ': only Gomoku bundled; future Mod and its imported asset excluded', flush=True)
            external = temp/'jump-rope.zip'
            pack(ROOT/'mods/jump_rope', external, hot=True)
            project = temp/'project'
            project.mkdir()
            (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="NovaParty Bundling Test '+token+'"\n')
            (project/'run.gd').write_text('''extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    print("TEST_USER_DIR=" + OS.get_user_data_dir())
    var args := OS.get_cmdline_user_args()
    if not ProjectSettings.load_resource_pack(args[0], true): quit(1); return
    var app = load("res://app/main.gd").new()
    root.add_child(app)
    app.profile.ui_sounds = false
    app.ui_feedback.refresh_preferences()
    await process_frame
    if app.choices.item_count != 1 or app.choices.get_item_metadata(0) != "res://mods/gomoku": quit(2); return
    if app.library.cards.size() != 2: quit(3); return
    app.queue_free()
    await process_frame
    # A UI hot pack from the old base still probing removed games must boot quietly.
    var old := GDScript.new()
    old.source_code = FileAccess.get_file_as_string("res://app/main.gd").replace('var roots := ["res://mods/gomoku"]', 'var roots := ["res://mods/gomoku", "res://mods/hidden_cards", "res://mods/jump_rope"]')
    if old.reload() != OK: quit(4); return
    app = old.new()
    root.add_child(app)
    app.profile.ui_sounds = false
    app.ui_feedback.refresh_preferences()
    await process_frame
    if app.choices.item_count != 1: quit(5); return
    app._install_package(args[1])
    if app.choices.item_count != 2: quit(6); return
    var found := false
    for i in range(app.choices.item_count):
        var info: Dictionary = app.loader.inspect(app.choices.get_item_metadata(i))
        if info.manifest.id == "jump_rope": found = true
    if not found: quit(7); return
    app.queue_free()
    app = null
    old = null
    await create_timer(0.25).timeout
    print("BUNDLED_MODS_RUNTIME_OK clean startup, legacy UI compatibility, external Jump Rope install")
    quit()
''')
            result = subprocess.run([GODOT, '--headless', '--path', str(project), '--script', str(project/'run.gd'), '--', str(packs['Android Release']), str(external)], capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            user_dir = next((line.split('=',1)[1] for line in output.splitlines() if line.startswith('TEST_USER_DIR=')), '')
            if user_dir and token in Path(user_dir).name:
                shutil.rmtree(user_dir, ignore_errors=True)
            assert result.returncode == 0 and 'BUNDLED_MODS_RUNTIME_OK' in output and 'ERROR:' not in output, output
            print('PASS isolated exported client: Gomoku + Add game only, legacy UI skips removed builtins, external Mod still installs')
    finally:
        shutil.rmtree(probe)


if __name__ == '__main__':
    run()
