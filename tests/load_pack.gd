extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loader = Loader.new()
	var path := OS.get_cmdline_user_args()[0]
	if FileAccess.file_exists("res://mods/pack_probe/manifest.json"):
		printerr("probe must not be built in")
		quit(1)
		return
	var mod_root: String = loader.mount_zip(path)
	if mod_root.is_empty():
		printerr(loader.error)
		quit(1)
		return
	var info: Dictionary = loader.inspect(mod_root)
	if info.is_empty():
		printerr(loader.error)
		quit(1)
		return
	var logic = loader.rules(info)
	if logic == null:
		printerr(loader.error)
		quit(1)
		return
	var state: Dictionary = logic.initial_state(42)
	var result: Dictionary = logic.apply(state, 0, {"type": "place", "x": 7, "y": 7})
	if not result.has("state") or result.state.board[112] != 0:
		quit(1)
		return
	var view_script = load(mod_root.path_join(info.manifest.view))
	var view = view_script.new()
	root.add_child(view)
	view.render({"seat": 0, "players": [{}, {}], "view": logic.view_for(result.state, 0)})
	view.queue_free()
	print("PACK_LOADED custom_rules_and_view " + info.fingerprint)
	quit(0)
