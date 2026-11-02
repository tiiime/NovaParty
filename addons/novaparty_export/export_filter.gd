@tool
extends EditorExportPlugin
const BUILTIN_ROOT = "res://mods/gomoku/"
func _get_name() -> String:
	return "NovaPartyBuiltinGames"
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://mods/") and not path.begins_with(BUILTIN_ROOT):
		skip()
