extends SceneTree
var app
var captured := false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	root.show()
	app = load("res://app/main.tscn").instantiate()
	root.add_child(app)
	app.port.value = int(args[1])
	app.address.text = "127.0.0.1"
	app.nickname.text = args[2]
	if args[2] != "lobby":
		for index in range(app.choices.item_count):
			var info: Dictionary = app.loader.inspect(app.choices.get_item_metadata(index))
			if info.manifest.id == args[0]:
				app.choices.select(index)
				break
		app._start(args[2] == "host")
		if app.game_view == null:
			printerr("HOT_START_FAILED " + app.status.text + " port=" + str(app.port.value))
			quit(1)
			return
		if args[0] == "gomoku":
			app.game_view.board.cursor = Vector2i(4, 5)
			app.game_view.board.grab_focus()
	for argument in args:
		if argument.begins_with("--capture="):
			var path: String = argument.trim_prefix("--capture=")
			RenderingServer.frame_post_draw.connect(func():
				if not captured and is_instance_valid(app.game_view) and app.mod_info.manifest.has("build_id"):
					captured = true
					root.get_texture().get_image().save_png(path)
			)
	print("HOT_READY")
