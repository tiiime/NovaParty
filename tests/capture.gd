extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1920, 1080) if OS.get_cmdline_user_args().has("landscape") else Vector2i(1000, 900)
	var scene = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for index in range(2):
		scene._leave()
		await process_frame
		scene.choices.select(index)
		scene.port.value = 29780 + index
		scene._start(true)
		var room = scene.session.room
		room.hello({"protocol": 1, "fingerprint": room.info.fingerprint, "player_id": "capture-guest", "nickname": "测试玩家"})
		scene.session._publish()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("/tmp/novaparty-ui-%d.png" % index)
	quit(0)
