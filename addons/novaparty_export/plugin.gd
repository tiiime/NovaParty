@tool
extends EditorPlugin
var filter: EditorExportPlugin
func _enter_tree() -> void:
	filter = preload("export_filter.gd").new()
	add_export_plugin(filter)
func _exit_tree() -> void:
	remove_export_plugin(filter)
