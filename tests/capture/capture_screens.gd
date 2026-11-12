extends SceneTree
# Renders every platform screen in phone and TV form for visual review.
# Output: build/validation/screens/<name>-<phone|tv>.png
var app
var form := "phone"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/validation/screens/%s-%s.png" % [name, form])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/validation/screens"))
	for entry in [["phone", Vector2i(540, 1170)], ["tv", Vector2i(1920, 1080)]]:
		form = entry[0]
		root.size = entry[1]
		app = load("res://app/main.tscn").instantiate()
		app.profile_path = "user://screens-capture-" + str(Time.get_ticks_usec()) + ".json"
		root.add_child(app)
		app.set_language("zh_CN")
		await shot("home")
		app._open_settings()
		await shot("settings")
		app.settings_dialog.close()
		app._open_user_profile()
		await shot("profile")
		app.user_panel.close()
		app._open_setup(true)
		await shot("library")
		app._open_setup(false)
		app.join_browser.populate([
			{"key": "a", "name": "五子棋", "version": "0.2.0", "source_name": "客厅电视", "address": "192.0.2.10", "port": 27840, "session_id": "a"},
			{"key": "b", "name": "UNO · 聚会叠加版", "version": "0.1.0", "source_name": "小熊的手机", "address": "192.0.2.11", "port": 27840, "session_id": "b"}])
		await shot("join")
		app._show_manual_join()
		await shot("manual-join")
		app._open_setup(false)
		app.download_dialog.ask(app.tr("DOWNLOAD_GAME_DETAILS") % ["UNO", "0.1.0", "客厅电视", "192.0.2.10", "182.4"])
		await shot("download")
		app.download_dialog.confirm.pressed.emit()
		app.download_dialog.update_progress(62, 100)
		await shot("downloading")
		app.download_dialog.hide()
		app._open_setup(true)
		app.choices.select(0)
		app.port.value = 29790 + (0 if form == "phone" else 1)
		app._start(true)
		await shot("game-invite")
		app.join_invite.hide()
		app.invite_dismissed = true
		app.session.room.hello({"protocol": 1, "fingerprint": app.session.room.info.fingerprint, "player_id": "capture-guest", "nickname": "测试玩家"})
		app.session._publish()
		await shot("game")
		app._request_leave()
		await shot("leave")
		app.leave_dialog.confirmed.emit()
		DirAccess.remove_absolute(app.profile_path)
		app.queue_free()
		await process_frame
	print("SCREENS_CAPTURE_OK")
	quit()
