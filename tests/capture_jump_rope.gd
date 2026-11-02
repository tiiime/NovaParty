extends SceneTree
var app
func _initialize() -> void:
	call_deferred("run")
func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/validation/jump-rope-" + name + ".png")
func role(seat: int, value: String) -> void:
	var room = app.session.room
	room.command(seat, {"request_id": str(Time.get_ticks_usec()), "expected_revision": room.revision, "action": {"type": "role", "role": value, "generation": room.state.slots[seat].generation}})
	app.session._publish()
func run() -> void:
	root.size = Vector2i(1920, 1080)
	app = load("res://app/main.tscn").instantiate()
	app.profile_path = "user://jump-capture-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	app.set_language("zh_CN")
	for i in range(app.choices.item_count):
		if str(app.choices.get_item_metadata(i)).ends_with("jump_rope"):
			app.choices.select(i)
	app.port.value = 29636
	app._start(true)
	role(0, "display")
	await capture("tv-waiting")
	var room = app.session.room
	for i in range(1, 5):
		room.hello({"protocol": 2, "rules_fingerprint": room.info.rules_fingerprint, "player_id": "animal" + str(i), "nickname": ["小兔", "小橘", "小云", "薄荷"][i - 1]})
		role(i, "controller")
		room.state.slots[i].count = i * 27
		app.session._publish()
		if i in [1, 2, 4]:
			await capture("tv-" + str(i))
	root.size = Vector2i(540, 960)
	role(0, "none")
	await capture("phone-role")
	for i in range(1, 5):
		room.set_connected(i, false)
	role(0, "controller")
	await capture("phone-controller")
	app.set_language("en")
	await capture("phone-en")
	app.queue_free()
	await process_frame
	print("JUMP_CAPTURE_OK")
	quit()
