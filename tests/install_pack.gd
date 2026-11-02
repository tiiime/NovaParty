extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := args[0]
	var phase := args[1]
	var loader = Loader.new()
	var destination := "user://mods/" + FileAccess.get_sha256(source) + ".zip"
	if phase == "cleanup":
		DirAccess.remove_absolute(destination)
		quit()
		return
	var info: Dictionary
	if phase == "install":
		info = loader.install_zip(source)
	else:
		if not loader.installed_packages().has(destination):
			printerr("package not persisted")
			quit(1)
			return
		var mod_root: String = loader.mount_zip(destination)
		info = loader.inspect(mod_root) if not mod_root.is_empty() else {}
	if info.is_empty():
		printerr(loader.error)
		quit(1)
		return
	var rules = loader.rules(info)
	if rules == null or rules.initial_state(42).board.size() != 225:
		printerr("installed rules unavailable")
		quit(1)
		return
	print("INSTALL_PHASE_OK " + phase)
	quit()
