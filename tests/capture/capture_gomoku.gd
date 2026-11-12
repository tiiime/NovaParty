extends SceneTree
var app
var path := "res://build/validation/"

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path + name + ".png")

func move(seat: int, x: int, y: int) -> void:
	var room = app.session.room
	room.command(seat, {"request_id": "capture-" + str(room.revision), "expected_revision": room.revision, "action": {"type": "place", "x": x, "y": y}})
	app.session._publish()

func run() -> void:
	root.size = Vector2i(1920, 1080)
	app = load("res://app/main.tscn").instantiate()
	app.profile_path = "user://gomoku-capture-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	app.set_language("zh_CN")
	app.nickname.text = "小星"
	app.port.value = 29635
	app._start(true)
	var room = app.session.room
	room.hello({"protocol": 2, "rules_fingerprint": room.info.rules_fingerprint, "player_id": "capture-guest", "nickname": "月亮"})
	move(0, 5, 7)
	move(1, 4, 9)
	move(0, 6, 7)
	room.clock_elapsed = [123400, 84500]
	app.session._publish()
	await capture("gomoku-tv")
	root.size = Vector2i(540, 1170)
	await capture("gomoku-phone")
	root.size = Vector2i(540, 960)
	await capture("gomoku-phone-short")
	root.size = Vector2i(540, 1170)
	app.set_language("en")
	await capture("gomoku-phone-en")
	app.set_language("zh_CN")
	for x in range(7, 10):
		move(1, x - 2, 9)
		move(0, x, 7)
	await capture("gomoku-result-phone")
	root.size = Vector2i(1920, 1080)
	await capture("gomoku-result-tv")
	app.game_view._hide_result()
	await capture("gomoku-finished-tv")
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	await process_frame
	print("GOMOKU_CAPTURE_OK")
	quit()
