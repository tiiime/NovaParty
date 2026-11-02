extends Control
# Immutable host. Debug TCP and live Session identity outlive replaceable UI trees.
const UI_API = 1
var client: Control
var debug_service
var ui_build := "builtin:client"
var session:
	get: return client.session if is_instance_valid(client) else null
var mod_info: Dictionary:
	get: return client.mod_info if is_instance_valid(client) else {}
var room_generation: int:
	get: return client.room_generation if is_instance_valid(client) else 0

func _ready() -> void:
	get_window().close_requested.connect(func(): get_tree().quit())
	get_window().go_back_requested.connect(func():
		if is_instance_valid(client): client._go_back()
	)
	get_window().size_changed.connect(func():
		if is_instance_valid(client): client._adapt_display()
	)
	client = _prepare("res://app/main.gd")
	assert(client != null)
	client.ui_preparing = false
	client.show()
	client._save_profile()
	client.home.start_button.grab_focus()
	if OS.is_debug_build() and OS.has_feature("novaparty_debug"):
		debug_service = load("res://debug/service.gd").new()
		debug_service.app = self
		add_child(debug_service)

func _prepare(entry: String) -> Control:
	var script = load(entry)
	if not script is GDScript or not script.can_instantiate() or not ClassDB.is_parent_class(script.get_instance_base_type(), "Control") or script.get_script_constant_map().get("UI_API") != UI_API:
		return null
	var candidate = script.new()
	var properties := []
	for field in candidate.get_property_list():
		properties.append(field.name)
	for field in ["shell_managed", "ui_preparing", "ui_ready", "session", "game_view", "profile"]:
		if not properties.has(field):
			candidate.free()
			return null
	for method in ["ui_import", "ui_restore_focus", "ui_apply_catalogs", "debug_ui_status", "debug_room_command", "debug_replace_view", "debug_view_state", "debug_select_build"]:
		if not candidate.has_method(method):
			candidate.free()
			return null
	candidate.shell_managed = true
	candidate.ui_preparing = true
	candidate.hide()
	candidate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(candidate)
	if not candidate.ui_ready:
		remove_child(candidate)
		candidate.queue_free()
		if is_instance_valid(client):
			client.ui_apply_catalogs()
		return null
	return candidate

func debug_replace_client_ui(entry: String, build: String) -> Dictionary:
	if not OS.is_debug_build() or not OS.has_feature("novaparty_debug"):
		return {"error": "debug_disabled"}
	if build == ui_build:
		return {"activated": true, "build": build, "unchanged": true}
	var locale := TranslationServer.get_locale()
	var old := client
	var view_state: Dictionary = old.debug_view_state()
	var focused := get_viewport().gui_get_focus_owner()
	var focus_path := old.get_path_to(focused) if focused != null and old.is_ancestor_of(focused) else NodePath("")
	var candidate := _prepare(entry)
	if candidate == null:
		TranslationServer.set_locale(locale)
		return {"error": "ui_prepare_failed"}
	if candidate.ui_import(old) != true:
		if candidate.session != null:
			old.ui_import(candidate)
		old.ui_apply_catalogs()
		TranslationServer.set_locale(locale)
		remove_child(candidate)
		candidate.queue_free()
		return {"error": "ui_attach_failed"}
	TranslationServer.set_locale(locale)
	candidate._refresh_translations()
	client = candidate
	client.ui_preparing = false
	old.hide()
	client.show()
	if client.game_view != null and client.game_view.has_method("restore_view_state"):
		client.game_view.restore_view_state(view_state)
	client.ui_restore_focus(focused, old, focus_path)
	ui_build = build
	remove_child(old)
	old.queue_free()
	return {"activated": true, "build": build, "session_preserved": session != null, "ui": debug_ui_status()}

func debug_ui_status() -> Dictionary:
	var state: Dictionary = client.debug_ui_status()
	state["ui_build"] = ui_build
	state["ui_api"] = UI_API
	return state

func debug_room_command(method: String, params: Dictionary) -> Dictionary:
	return client.debug_room_command(method, params)

func debug_replace_view(info: Dictionary) -> Dictionary:
	return client.debug_replace_view(info)

func debug_view_state() -> Dictionary:
	return client.debug_view_state()

func debug_select_build(info: Dictionary) -> void:
	client.debug_select_build(info)

func debug_lan_command(method: String, params: Dictionary) -> Dictionary:
	return client.debug_lan_command(method, params)
