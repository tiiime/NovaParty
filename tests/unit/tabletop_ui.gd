extends SceneTree
const TYPICAL_FOCUS_SCALE := preload("res://app/ui/theme/tokens.gd").FOCUS_BUTTON_SCALE
var checks := 0
var failures := 0
var out := ""
var app
var requests := []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + title)

func settle() -> void:
	for _i in range(4): await process_frame

func action_rings_fit(view: Control, buttons: Array, game: String) -> void:
	for button in buttons:
		if not button.is_visible_in_tree(): continue
		check(view.get_global_rect().encloses(button.get_global_rect().grow(4)), "%s action and ring fit: %s" % [game, button.name])

func capture(name: String) -> void:
	if out.is_empty() or DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(out.path_join(name + ".png")) == OK, "save " + name)

func press(key: String) -> void:
	var e := InputEventAction.new()
	e.action = key
	e.pressed = true
	root.push_input(e)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)

func click(board: Control, at: int) -> void:
	board._geometry()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = board.get_global_transform_with_canvas() * board._pos(at)
	root.push_input(e, true)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e, true)

func fake_guest(id: String = "ui-fixture") -> void:
	var r = app.session.room
	r.hello({"protocol": 2, "rules_fingerprint": r.info.rules_fingerprint, "player_id": id, "nickname": "月亮"})
	app.session._publish()

func action(seat: int, body: Dictionary) -> void:
	var r = app.session.room
	var receipt: Dictionary = r.command(seat, {"request_id": "ui-" + str(r.revision), "expected_revision": r.revision, "action": body})
	check(receipt.accepted, "fixture action accepted: " + str(body))
	app.session._publish()

func start(game: String, options: Dictionary = {}) -> void:
	app._open_setup(true)
	app._add_choice("res://mods/" + game)
	for i in range(app.choices.item_count):
		if app.choices.get_item_metadata(i) == "res://mods/" + game: app.choices.select(i)
	var port := 0
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") == OK:
		port = probe.get_local_port()
		probe.stop()
	var err: Error = app._start(true, port, options) if port > 0 else ERR_CANT_CREATE
	check(err == OK, "start " + game + ": " + error_string(err))
	if err != OK:
		quit(1)
		return
	if app.join_invite.visible: app.join_invite.close()
	await settle()

func fullscreen() -> void:
	var vp := root.get_visible_rect()
	var v: Control = app.game_view
	check(not app.content_margin.visible and not app.footer.visible, "immersive shell has no scroll or footer")
	check(app.immersive_surface.get_global_rect().is_equal_approx(vp), "immersive surface fills viewport")
	check(v.get_parent() == app.immersive_area and vp.encloses(v.get_global_rect()), "view takes safe viewport")
	check(v.size.distance_to(vp.size - Vector2(16, 16)) <= 2, "no page padding or minimum-height clamp")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): out = arg.trim_prefix("--captures=")
	if not out.is_empty(): DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	app = load("res://app/main.tscn").instantiate()
	app.profile_path = "user://tabletop-ui-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	app.profile.reduce_motion = true
	app.home.set_reduced_motion(true)
	app.set_language("zh_CN")
	app.nickname.text = "小星"
	await start("gomoku")
	fullscreen()
	var gomoku = app.game_view
	# Loopback-only hosts may have no real invite interface: simulate availability for this layout assertion.
	gomoku.set_platform_state({"can_invite": true})
	await settle()
	check(gomoku.settings_button.position.x == gomoku.invite_button.position.x and gomoku.settings_button.position.y < gomoku.invite_button.position.y, "Invite sits immediately below Settings")
	action_rings_fit(gomoku, gomoku.actions.get_children(), "Gomoku TV")
	await capture("gomoku-tv-invite")
	gomoku.settings_button.grab_focus()
	gomoku.settings_button.pressed.emit()
	await settle()
	check(gomoku.board.focus_mode == Control.FOCUS_NONE, "focus trapped in settings")
	for item in [app.language_choice, app.sound_choice, app.haptic_choice, app.motion_choice]:
		item.grab_focus()
		await settle()
		var area: Rect2 = app.settings_dialog.scroll.get_global_rect().grow(-3)
		check(area.encloses(item.get_global_rect()), "settings row and ring fit: %s %s in %s" % [item.name, item.get_global_rect(), area])
	var halo: Rect2 = app.motion_choice.get_global_rect().grow(9 * TYPICAL_FOCUS_SCALE)
	check(app.settings_dialog.scroll.get_global_rect().encloses(halo), "scaled focus halo fits inside scroll clip")
	var done: Button = app.settings_dialog.done
	check(root.get_visible_rect().encloses(done.get_global_rect()), "close stays visible")
	await capture("gomoku-tv-settings")
	root.size = Vector2i(375, 667)
	await settle()
	app.language_choice.grab_focus()
	await settle()
	check(app.settings_dialog.scroll.get_global_rect().grow(-3).encloses(app.language_choice.get_global_rect()), "phone language row fits")
	await capture("gomoku-phone-settings")
	app.settings_dialog.close()
	check(root.gui_get_focus_owner() == gomoku.settings_button, "closing restores settings entry")
	action_rings_fit(gomoku, gomoku.actions.get_children(), "Gomoku phone")
	check(gomoku.players_row.get_global_rect().end.y < gomoku.actions.global_position.y, "phone actions do not cover player cards")
	app._leave()
	root.size = Vector2i(1280, 720)
	await start("uno")
	fake_guest()
	for shape in [Vector2i(1280, 720), Vector2i(1024, 640), Vector2i(480, 1000)]:
		root.size = shape
		await settle()
		fullscreen()
		var uno = app.game_view
		var table: Rect2 = uno.table_art.get_global_rect()
		var rect: Rect2 = uno.get_global_rect()
		check(table.grow(1).encloses(rect), "UNO art fills safe viewport at " + str(shape))
		check(rect.encloses(uno.menu_button.get_global_rect()), "UNO menu stays tappable")
		uno._toggle_menu(true)
		check(uno.menu_panel.is_ancestor_of(root.gui_get_focus_owner()), "UNO focuses open menu")
		uno._toggle_menu(false)
		await capture("uno-" + str(shape.x))
	# A playing host gets a private hand at multiple ratios.
	check(not app.game_view.start_button.disabled, "playing UNO host can start with two players")
	app.game_view.start_button.pressed.emit()
	for shape in [Vector2i(1280, 720), Vector2i(480, 1000)]:
		root.size = shape
		await settle()
		var uno = app.game_view
		check(uno.hand_buttons.size() == 7 and uno.hand_scroll.is_visible_in_tree(), "UNO private hand renders")
		check(uno.get_global_rect().encloses(uno.hand_scroll.get_global_rect()), "UNO hand stays in safe viewport")
		await capture("uno-playing-" + str(shape.x))
	app._leave()
	# The seatless host retains the invite QR and can start, but never connects commands.
	await start("uno", {"role": "spectator"})
	var public_uno = app.game_view
	check(public_uno.start_button.visible and public_uno.start_button.disabled, "seatless host waits for players")
	check(not public_uno.command.is_connected(app.session.submit), "seatless view has no player command binding")
	check(public_uno.services != null and not public_uno.services.has_method("submit") and not public_uno.services.has_method("start_round"), "observer receives only narrow presentation services")
	fake_guest()
	fake_guest("another")
	check(not public_uno.start_button.disabled, "seatless host can start when ready")
	public_uno.start_button.pressed.emit()
	check(app.session.snapshot.role == "spectator" and not app.session.snapshot.has("seat") and not app.session.snapshot.view.has("hand"), "seatless host starts and continues seeing only the public view")
	app._leave()
	await start("xiangqi")
	fullscreen()
	check(app.game_view.status_label.text == "等一位棋友", "localized waiting")
	fake_guest()
	var chess = app.game_view
	chess.command.connect(func(body): requests.append(body))
	await settle()
	click(chess.board, 54)
	check(chess.board.selected == 54 and root.gui_get_focus_owner() == chess.board, "pointer selects soldier")
	await capture("xiangqi-phone-selection")
	click(chess.board, 19)
	check(requests.size() == 1 and requests[0].to == 19 and chess.snapshot.view.board[19] == 7, "pointer moves freely and captures through SDK")
	check(chess.buttons.request_undo.visible, "last mover can request undo")
	await settle()
	action_rings_fit(chess, chess.buttons.values(), "Xiangqi phone")
	chess.buttons.request_undo.pressed.emit()
	check(chess.snapshot.view.undo_by == 0 and chess.snapshot.view.board[19] == 7 and chess.buttons.cancel_undo.visible and not chess.buttons.accept_undo.visible, "requester waits without changing the board")
	action(1, {"type": "accept_undo"})
	check(chess.snapshot.view.board[54] == 7 and chess.snapshot.view.board[19] == -6 and chess.snapshot.view.turn == 0, "peer approval restores both pieces")
	action(0, {"type": "move", "from": 54, "to": 45})
	action(1, {"type": "move", "from": 27, "to": 36})
	root.size = Vector2i(1280, 720)
	await settle()
	chess.board.cursor = 55
	chess.board.grab_focus()
	press("ui_right")
	press("ui_accept")
	press("ui_up")
	press("ui_accept")
	check(requests.size() == 3 and chess.snapshot.view.board[47] == 7, "DPAD move")
	chess.board.cursor = 53
	press("ui_right")
	check(root.gui_get_focus_owner() == chess.buttons.request_undo, "DPAD reaches request undo from board edge")
	chess.buttons.resign.pressed.emit()
	check(chess.resign_prompt and root.gui_get_focus_owner() == chess.buttons.cancel, "resign opens on safe action")
	check(chess.handle_platform_back() and not chess.resign_prompt, "back cancels resignation")
	await capture("xiangqi-tv")
	action(1, {"type": "move", "from": 36, "to": 82})
	action(1, {"type": "request_undo"})
	await settle()
	check(chess.buttons.decline_undo.visible and chess.buttons.accept_undo.visible and root.gui_get_focus_owner() == chess.buttons.decline_undo, "incoming request focuses the safe choice")
	var revision: int = chess.snapshot.revision
	click(chess.board, 85)
	click(chess.board, 0)
	check(chess.snapshot.revision == revision and chess.board.selected < 0, "cannot move while deciding")
	await capture("xiangqi-tv-undo")
	chess.buttons.decline_undo.pressed.emit()
	check(chess.snapshot.view.board[82] == -7 and chess.snapshot.view.undo_by == -1, "decline preserves position")
	action(1, {"type": "request_undo"})
	chess.buttons.accept_undo.pressed.emit()
	check(chess.snapshot.view.board[82] == 4 and chess.snapshot.view.board[36] == -7 and chess.snapshot.view.turn == 1, "accept restores capture and turn")
	app._leave()
	await start("go")
	fake_guest()
	action(0, {"type": "move", "to": 30})
	action(1, {"type": "move", "to": 31})
	action(0, {"type": "move", "to": 21})
	action(1, {"type": "move", "to": 32})
	action(0, {"type": "pass"})
	action(1, {"type": "pass"})
	var go = app.game_view
	await settle()
	click(go.board, 31)
	check(go.snapshot.view.dead == [31, 32], "touch marks whole Go group")
	app.set_language("en")
	await settle()
	check(go.status_label.text == "Review the score" and go.buttons.confirm_score.visible, "live locale update in scoring")
	await capture("go-tv-score")
	root.size = Vector2i(480, 860)
	await settle()
	action_rings_fit(go, go.buttons.values(), "Go phone scoring")
	await capture("go-phone-score")
	go.buttons.confirm_score.pressed.emit()
	check(go.snapshot.view.phase == "score" and go.buttons.confirm_score.disabled, "own vote waits")
	action(1, {"type": "confirm_score"})
	check(go.snapshot.view.phase == "finished" and go.buttons.rematch.visible, "both votes reveal result")
	app._leave()
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	await settle()
	print("TABLETOP_UI checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
