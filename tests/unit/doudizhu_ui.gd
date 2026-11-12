extends SceneTree
# Dou Dizhu presentation: lobby, public table privacy, bidding and play controls, selection,
# hints, remote focus, result sheet and translations. `-- --capture` saves screenshots to
# build/validation/doudizhu/.
const Loader = preload("res://sdk/mods/mod_loader.gd")
const Room = preload("res://sdk/session/room.gd")
const Cards = preload("res://mods/doudizhu/cards.gd")
var failures := 0
var checks := 0
var capture := false
var room
var view
var received: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("DOUDIZHU_UI FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if not capture: return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/validation/doudizhu/" + name + ".png")

# Wire round trip: JSON numbers arrive as floats on real clients.
func show_seat(seat: int, size: Vector2i) -> void:
	root.size = size
	view.render(JSON.parse_string(JSON.stringify(room.snapshot(seat))))
	await process_frame
	await process_frame

func act(seat: int, action: Dictionary) -> bool:
	var result: Dictionary = room.command(seat, {"request_id": str(Time.get_ticks_usec()), "expected_revision": room.revision, "action": action})
	return result.get("accepted", false)

func run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	if capture: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/validation/doudizhu"))
	TranslationServer.set_locale("zh_CN")
	var loader := Loader.new()
	var info := loader.inspect("res://mods/doudizhu")
	check(not info.is_empty(), "manifest: " + loader.error)
	room = Room.new(info, loader.rules(info), "tv", "客厅电视", 2026)
	view = load(info.root.path_join(info.manifest.view)).new()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.command.connect(func(action): received.append(action))
	await show_seat(0, Vector2i(1920, 1080))
	check(view.lobby_panel.visible and view.start_button.visible and view.start_button.disabled, "empty lobby: start waits for three players")
	check(view.lobby_title.text.contains("0/3"), "lobby counts players: " + view.lobby_title.text)
	for seat in range(1, 4):
		room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "phone-%d" % seat, "nickname": ["小熊", "狐狸", "熊猫"][seat - 1]})
	await show_seat(0, Vector2i(1920, 1080))
	check(not view.start_button.disabled and view.lobby_title.text.contains("3/3"), "three players enable start")
	check(view.table_toggle.visible and view.table_toggle.button_pressed, "public table mode is on by default")
	await shot("lobby-tv")
	view.start_button.pressed.emit()
	await process_frame
	check(received.size() == 1 and received[0].type == "start", "start emits one deferred action")
	check(act(0, {"type": "start"}), "host starts the round")
	await show_seat(0, Vector2i(1920, 1080))
	check(view.public_layout and view.hand_buttons.is_empty() and not view.hand_row.visible, "public table shows no hand")
	check(view.seats_layer.get_child_count() == 6, "public table shows three seats with play areas")
	check(view.bottom_row.get_child_count() == 3 and view.bottom_row.get_child(0) is Panel, "bottom cards face down before a landlord")
	for button in view.action_row.get_children(): check(not button.visible, "public table has no actions: " + button.name)
	var first: int = room.state.turn
	await show_seat(first, Vector2i(540, 1100))
	check(not view.public_layout and view.hand_buttons.size() == 17, "phone shows exactly its 17 cards")
	check(view.bid_buttons[0].visible and not view.bid_buttons[0].disabled and not view.bid_buttons[3].disabled, "bidder can pass or bid")
	check(view.status.text.contains("叫分"), "Chinese bidding status: " + view.status.text)
	view.focus_default()
	check(root.gui_get_focus_owner() == view.bid_buttons[1], "remote focus goes to the lowest raise")
	await shot("bidding-phone")
	check(act(first, {"type": "bid", "amount": 1}), "first bid")
	var second: int = room.state.turn
	await show_seat(second, Vector2i(540, 1100))
	check(view.bid_buttons[1].disabled and not view.bid_buttons[2].disabled, "cannot bid at or below the current bid")
	check(act(second, {"type": "bid", "amount": 3}), "bid 3 decides the landlord")
	var landlord: int = room.state.landlord
	await show_seat(landlord, Vector2i(540, 1100))
	check(view.hand_buttons.size() == 20, "landlord holds 20 cards")
	check(view.bottom_row.get_child(0) is Button, "bottom cards revealed after bidding")
	check(view.pass_button.visible and view.pass_button.disabled, "landlord cannot pass a free lead")
	check(view.play_button.disabled, "play disabled without a selection")
	# Select one card by touch: it rises and becomes playable.
	var lowest: Button = view.hand_buttons.back()
	var rest_y: float = lowest.position.y
	lowest.pressed.emit()
	await process_frame
	var raised: Button = view.hand_buttons.back()
	check(view.selected.size() == 1 and raised.position.y < rest_y, "selected card rises")
	check(not view.play_button.disabled and view.my_bubble.text == "单张", "single is playable and named")
	# Two different ranks are not a combination.
	view.hand_buttons[0].pressed.emit()
	await process_frame
	var two_kinds: bool = Cards.classify(view.selected).is_empty()
	if two_kinds: check(view.play_button.disabled and view.my_bubble.text == "不成牌型", "invalid selection cannot be played")
	view.handle_platform_back()
	check(view.selected.is_empty(), "back clears the selection first")
	view.hint_button.pressed.emit()
	await process_frame
	check(not view.selected.is_empty() and not view.play_button.disabled, "hint selects a playable combination")
	var hinted: Array = Cards.sort_hand(view.selected)
	await shot("lead-phone")
	received.clear()
	view.play_button.pressed.emit()
	# Actions are deferred; after a post-draw capture they flush one frame later.
	await process_frame
	await process_frame
	check(received.size() == 1 and received[0].type == "play" and received[0].cards == hinted, "play sends the selected cards")
	check(act(landlord, received[0]), "rules accept the hinted lead")
	var follower: int = room.state.turn
	await show_seat(follower, Vector2i(540, 1100))
	check(view.status.text.contains("要大过"), "follower is told what to beat: " + view.status.text)
	check(not view.pass_button.disabled, "follower may pass")
	check(view.seats_layer.get_child_count() == 4, "phone shows two opponents with play areas")
	view.focus_default()
	var focused: Control = root.gui_get_focus_owner()
	check(focused != null and str(focused.name).begins_with("Card_"), "remote focus starts on a card")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	focused.pressed.emit()
	await process_frame
	check(view.selected.size() == 1, "remote accept toggles the focused card")
	view.handle_platform_back()
	await show_seat(follower, Vector2i(1920, 1080))
	check(view.wide and view.hand_buttons.size() == 17 and view.hand_buttons[0].size.x >= 100, "TV player layout uses large cards")
	await shot("follow-tv-player")
	# Finish the round quickly: empty the landlord's hand through real rules.
	check(act(follower, {"type": "pass"}), "follower passes")
	check(act(room.state.turn, {"type": "pass"}), "second follower passes")
	room.state.hands[landlord] = [room.state.hands[landlord][0]]
	check(act(landlord, {"type": "play", "cards": room.state.hands[landlord]}), "landlord plays the last card")
	await show_seat(follower, Vector2i(540, 1100))
	check(view.result_panel.visible and view.result_title.text.contains("地主获胜") and view.result_title.text.contains("惜败"), "result sheet for a farmer: " + view.result_title.text)
	check(view.result_body.text.contains("春天"), "spring is announced")
	check(not view.result_rematch.disabled, "rematch available")
	await shot("result-phone")
	view.handle_platform_back()
	check(not view.result_panel.visible, "back closes the result sheet to review the table")
	await show_seat(0, Vector2i(1920, 1080))
	await shot("result-tv")
	# English catalog.
	TranslationServer.set_locale("en")
	await show_seat(landlord, Vector2i(540, 1100))
	check(view.result_title.text.contains("Landlord wins") and view.result_rematch.text == "Play again", "English texts")
	TranslationServer.set_locale("zh_CN")
	# Platform pause disables controls.
	view.set_platform_state({"connected": false, "input_paused": false})
	check(view.status.text.contains("掉线"), "disconnected status")
	view.queue_free()
	await process_frame
	print("DOUDIZHU_UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
