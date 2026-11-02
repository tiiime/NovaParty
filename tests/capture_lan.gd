extends SceneTree
var app
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/validation/lan-ui-" + name + ".png")
func run() -> void:
	root.size = Vector2i(540, 1170)
	app = load("res://app/main.tscn").instantiate()
	app.profile_path = "user://lan-capture-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	app._add_choice("res://mods/jump_rope") # Explicit external fixture for the Mod-owned QR layout.
	app.set_language("zh_CN")
	app._open_setup(false)
	app.join_browser.populate([{"key":"fixture", "session_id":"0123456789abcdef0123456789abcdef", "name":"跳绳", "version":"0.1.1", "source_name":"电视小星", "address":"192.0.2.20", "port":27840}])
	await capture("nearby-phone")
	app.download_dialog.ask(tr("DOWNLOAD_GAME_DETAILS") % ["跳绳", "0.1.1", "电视小星", "192.0.2.20", "24.6"])
	await capture("confirm-phone")
	app.download_dialog.hide()
	app.set_language("en")
	app.download_dialog.ask(tr("DOWNLOAD_GAME_DETAILS") % ["Jump Rope", "0.1.1", "TV Star", "192.0.2.20", "24.6"])
	await capture("confirm-en")
	app.download_dialog.hide()
	app.set_language("zh_CN")
	app.choices.select(0)
	app.port.value = 29645
	app._start(true)
	await capture("qr-default-phone")
	app._leave()
	root.size = Vector2i(1920,1080)
	for i in range(app.choices.item_count):
		if str(app.choices.get_item_metadata(i)).ends_with("jump_rope"):app.choices.select(i)
	app._start(true)
	var room = app.session.room
	room.command(0,{"request_id":"display", "expected_revision":room.revision, "action":{"type":"role", "role":"display", "generation":room.state.slots[0].generation}})
	app.session._publish()
	await capture("qr-mod-tv")
	app.queue_free()
	await process_frame
	print("LAN_UI_CAPTURE_OK (nearby list and package details use fixtures)")
	quit()
