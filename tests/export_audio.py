#!/usr/bin/env python3
"""Load actual exported audio in an empty project, without source OGG/import caches."""
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from dev_config import godot_path
GODOT = godot_path()


def main():
    archive = ROOT / 'build/validation/feedback-release.zip'
    with zipfile.ZipFile(archive) as z:
        assert 'assets/audio/ui/LICENSE.txt' in z.namelist()
        assert not any(name.startswith('debug/') for name in z.namelist())
    with tempfile.TemporaryDirectory(prefix='nv-export-audio-') as temp:
        temp = Path(temp)
        (temp / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Export audio check"\n')
        (temp / 'main.gd').write_text('''extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var archive := OS.get_cmdline_user_args()[0]
    if not ProjectSettings.load_resource_pack(archive, true): quit(1); return
    var raw := "res://assets/audio/ui/move.ogg"
    if FileAccess.file_exists(raw) or not ResourceLoader.exists(raw): quit(2); return
    var parent_script := GDScript.new()
    parent_script.source_code = "extends Control\\nvar profile := {}\\nvar ui_preparing := false\\n"
    if parent_script.reload() != OK: quit(3); return
    var parent = parent_script.new()
    root.add_child(parent)
    var feedback = load("res://app/ui/ui_feedback.gd").new()
    parent.add_child(feedback)
    if feedback.streams.size() != 5: quit(4); return
    for stream in feedback.streams.values():
        if stream.get_length() <= 0: quit(5); return
    parent.queue_free()
    await create_timer(0.08).timeout
    print("EXPORTED_AUDIO_OK five imported cues loaded without source files")
    quit()
''')
        run = subprocess.run([GODOT, '--headless', '--path', str(temp), '--script', str(temp/'main.gd'),
            '--', str(archive)], capture_output=True, text=True, timeout=20)
        output = run.stdout + run.stderr
        assert run.returncode == 0 and 'EXPORTED_AUDIO_OK' in output and 'ERROR:' not in output, output
    print('PASS Release imported audio loads in an isolated project; attribution present, Debug absent')


if __name__ == '__main__':
    main()
