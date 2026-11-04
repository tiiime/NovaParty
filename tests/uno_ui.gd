extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Room = preload("res://sdk/room.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("UNO_UI FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var loader := Loader.new()
	var info := loader.inspect("res://mods/uno")
	var room = Room.new(info, loader.rules(info), "tv", "电视小星", 43)
	for seat in range(1, 4):
		room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "phone-" + str(seat), "nickname": "手机玩家 " + str(seat)})
	root.size = Vector2i(1920, 1080)
	var view = load(info.root.path_join(info.manifest.view)).new()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.render(room.snapshot(0))
	await process_frame
	check(view.hand_buttons.is_empty() and view.start_button.visible and not view.start_button.disabled, "public lobby has start and no cards")
	var received := []
	view.command.connect(func(action): received.append(action))
	view.start_button.pressed.emit()
	await process_frame
	check(received.size() == 1 and received[0].type == "start", "one deferred lobby action")
	check(room.command(0, {"request_id": "begin", "expected_revision": room.revision, "action": {"type": "start"}}).accepted, "public host starts")
	view.render(room.snapshot(0))
	await process_frame
	check(view.hand_buttons.is_empty(), "TV has no private hand")
	check(view.draw_button.disabled and view.catch_button.disabled and view.uno_toggle.disabled, "public screen cannot play or catch")
	check(room.state.participants == [1, 2, 3] and room.state.hands[0].is_empty(), "screen is excluded from deal")
	var public: Dictionary = room.snapshot(0).view
	check(public.hand.is_empty() and not public.has("hands") and not public.has("deck"), "public snapshot contains no hand payload")
	room.state.hands[0] = [42] # Even corrupt internal observer data is filtered out.
	check(room.snapshot(0).view.hand.is_empty(), "screen privacy is enforced in rules, not UI")
	room.state.hands[0] = []
	if OS.get_cmdline_user_args().has("--capture"):
		await create_timer(.5).timeout
		root.get_texture().get_image().save_png("res://build/validation/uno-tv.png")
	var seat: int = int(room.state.turn)
	view.render(JSON.parse_string(JSON.stringify(room.snapshot(seat))))
	await process_frame
	for player in view.roster.get_children():
		var count_label = player.get_node_or_null("Count")
		if count_label != null: check(count_label.text.is_valid_int(), "wire-decoded card counts render whole numbers")
	check(view.hand_buttons.size() == 7, "phone gets exactly own seven cards")
	var playable := []
	for button in view.hand_buttons:
		if not button.disabled: playable.append(button)
	check(not playable.is_empty() or not view.draw_button.disabled, "phone always has actionable choice")
	view.focus_default()
	check(view.is_ancestor_of(root.gui_get_focus_owner()), "remote focus lands inside game")
	root.size = Vector2i(540, 1100)
	view.render(room.snapshot(seat))
	await process_frame
	await process_frame
	check(not view.wide_layout and view.logical_size == Vector2(540,1100), "portrait uses dedicated table and hand composition")
	check(view.stage.position.x >= 0 and view.stage.size.x * view.stage.scale.x <= 540, "phone table fits horizontal viewport")
	check(view.hand_scroll.position.y + view.hand_scroll.size.y <= view.logical_size.y, "phone hand stays inside stage")
	view.on_command_notice("card_not_playable")
	view.render(room.snapshot(seat))
	check(view.notice.visible, "rejected action remains visible across same-revision render")
	view.notice.hide()
	if OS.get_cmdline_user_args().has("--capture"):
		await create_timer(.5).timeout
		root.get_texture().get_image().save_png("res://build/validation/uno-phone.png")
	view._choose(100)
	check(view.color_dialog.visible and view.color_buttons.size() == 4, "wild card exposes four colour choices")
	view.color_buttons[2].pressed.emit()
	await process_frame
	check(received.back().card == 100 and received.back().color == 2, "wild submits chosen colour")
	view.set_platform_state({"connected": false, "input_paused": false})
	check(view.draw_button.disabled, "connection loss disables drawing")
	view.set_platform_state({"connected": true, "input_paused": true})
	check(view.draw_button.disabled, "platform modal pauses game input")
	view.set_platform_state({"connected": true, "input_paused": false})
	TranslationServer.set_locale("en")
	view.render(room.snapshot(seat))
	check(view.settings_button.text == "Settings" and view.color_dialog.title == "Choose a colour", "live locale change refreshes footer and dialogs")
	view.queue_free()
	await process_frame
	view = load(info.root.path_join(info.manifest.view)).new()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.render(room.snapshot(seat))
	await process_frame
	check(view.header.text.contains("Round"), "English mod-owned catalogue")
	check(view.menu_button.position.x + view.menu_button.size.x <= view.logical_size.x, "English phone menu fits")
	room.state.phase = "finished"
	room.state.winner = seat
	room.state.score = 123
	view.render(room.snapshot(seat))
	check(view.result_dialog.visible and view.result_dialog.dialog_text.contains("123"), "winner dialog contains score")
	var six = Room.new(info, loader.rules(info), "six-tv", "TV", 99)
	for i in range(1, 7): six.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "six-" + str(i), "nickname": "Phone " + str(i)})
	six.command(0, {"request_id": "six-start", "expected_revision": six.revision, "action": {"type": "start"}})
	root.size = Vector2i(540, 960)
	view.render(six.snapshot(1))
	await process_frame
	await process_frame
	check(view.roster.get_child_count() == 5, "phone shows five opponents; own name and hand stay at bottom")
	check(view.stage.size.y * view.stage.scale.y <= view.size.y + .1, "six-player table fits short portrait viewport")
	six.state.phase = "finished"
	six.state.winner = 1
	view.render(six.snapshot(1))
	var retry_results := []
	var player_view = view
	player_view.command.connect(func(action):
		var result: Dictionary = six.command(1, {"request_id": "ui-vote-" + str(retry_results.size()), "expected_revision": player_view.snapshot.revision, "action": action})
		retry_results.append(result)
		if not result.accepted: player_view.on_command_notice(str(result.code))
		player_view.render(six.snapshot(1))
	)
	# Another player's vote wins the race before our UI receives the new snapshot.
	six.command(2, {"request_id": "other-vote", "expected_revision": six.revision, "action": {"type": "rematch"}})
	player_view._submit({"type": "rematch"})
	await create_timer(.2).timeout
	check(retry_results.size() == 2 and not retry_results[0].accepted and retry_results[1].accepted, "stale rematch consent retries explicit intent against refreshed revision")
	check(six.state.votes.has(1) and six.state.votes.has(2) and six.state.phase == "finished", "concurrent consent preserves other votes and quorum")
	view.queue_free()
	print("UNO_UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
