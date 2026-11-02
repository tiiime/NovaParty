extends SceneTree
const Session = preload("res://sdk/session.gd")
const Loader = preload("res://sdk/mod_loader.gd")
var session
var mod_info := {}
var room_generation := 0

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var args := OS.get_cmdline_user_args()
	var game := args[0]
	var loader = Loader.new()
	var info: Dictionary = loader.inspect("res://mods/" + game)
	session = Session.new()
	root.add_child(session)
	var error: Error
	if args[2] == "host":
		error = session.create(info, loader.rules(info), {"id": "debug-host", "nickname": "Host"}, int(args[1]))
	else:
		error = session.join(info, {"id": "debug-guest", "nickname": "Guest"}, "127.0.0.1", int(args[1]))
	assert(error == OK)
	var service = load("res://debug/service.gd").new()
	service.app = self
	root.add_child(service)
	print("DEBUG_READY")
