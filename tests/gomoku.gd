extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Room = preload("res://sdk/room.gd")
var checks := 0
var failures := 0
var host

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL GOMOKU: " + message)

func _initialize() -> void:
	call_deferred("run")

func request(id: String, revision: int, action: Dictionary) -> Dictionary:
	return {"request_id": id, "expected_revision": revision, "action": action}

func run() -> void:
	var loader := Loader.new()
	var info: Dictionary = loader.inspect("res://mods/gomoku")
	var rules = loader.rules(info)
	var timed := Room.new(info, rules, "alpha", "小星", 42)
	timed.advance_clock(1000)
	timed.advance_clock(3000)
	check(timed.clock_elapsed == [0, 0] and timed.clock_turn == -1, "waiting time is not charged")
	timed.players.append({"id": "beta", "nickname": "月亮", "token": "private", "connected": true})
	timed.advance_clock(3000)
	timed.advance_clock(6000)
	check(timed.clock_elapsed == [3000, 0], "black turn accumulates")
	timed.state.turn = 1
	timed.advance_clock(6000)
	timed.advance_clock(8000)
	check(timed.clock_elapsed == [3000, 2000], "only current seat accumulates")
	timed.players[1].connected = false
	timed.advance_clock(8000)
	timed.advance_clock(13000)
	check(timed.clock_elapsed == [3000, 2000] and timed.clock_turn == -1, "disconnect pauses both clocks")
	timed.players[1].connected = true
	timed.advance_clock(13000)
	timed.advance_clock(14000)
	check(timed.clock_elapsed == [3000, 3000], "reconnect resumes without charging offline time")
	timed.state.finished = true
	timed.advance_clock(14000)
	timed.advance_clock(20000)
	check(timed.clock_elapsed == [3000, 3000], "finished game freezes clocks")
	timed.state = rules.initial_state(42)
	timed.state.round = 2
	timed.advance_clock(20000)
	check(timed.clock_elapsed == [0, 0] and timed.clock_turn == 0, "rematch resets clocks")
	var room := Room.new(info, rules, "alpha", "小星", 42)
	var hello := {"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "beta", "nickname": "月亮"}
	room.hello(hello)
	check(room.command(0, request("early-rematch", 0, {"type": "rematch"})).code == "game_not_finished", "cannot reset a live game")
	for x in range(5):
		check(room.command(0, request("black-" + str(x), room.revision, {"type": "place", "x": x, "y": 0})).accepted, "black move")
		if x < 4:
			check(room.command(1, request("white-" + str(x), room.revision, {"type": "place", "x": x, "y": 2})).accepted, "white move")
	check(room.state.finished and room.state.winner == 0 and room.state.winning_line.size() == 5, "winner and winning stones recorded")
	var final := room.snapshot(0)
	var board_copy: Array = room.state.board.duplicate()
	var game_id: String = room.game_session_id
	var revision: int = room.revision
	check(final.clock.running_seat == -1, "authoritative final clock is stopped")
	var consent := request("rematch-black", revision, {"type": "rematch", "round": 1})
	check(room.command(0, consent).accepted, "first consent accepted")
	check(room.state.finished and room.state.board == board_copy, "one consent never clears board")
	check(room.command(0, consent).accepted and room.revision == revision + 1, "consent retry is idempotent")
	check(room.command(0, request("rematch-repeat", room.revision, {"type": "rematch"})).code == "already_requested", "duplicate independent consent rejected")
	check(room.command(1, request("rematch-white", room.revision, {"type": "rematch", "round": 1})).accepted, "second consent accepted")
	check(room.game_session_id == game_id and room.revision == revision + 2 and room.state.round == 2 and room.state.moves == 0 and not room.state.finished, "new round preserves session and monotonic revision")
	check(room.snapshot(0).clock.elapsed_ms[0] < 100 and room.snapshot(0).clock.elapsed_ms[1] == 0, "new round timer reset")
	check(room.command(0, request("stale-round", room.revision, {"type": "rematch", "round": 1})).code == "stale_revision", "old round consent cannot reset next round")
	check(final.players[0].code != final.players[1].code and not final.players[0].has("token") and not final.players[0].has("id"), "distinct public codes do not expose credentials")

	# Validate the real host integration, geometry, platform actions and modal focus.
	root.size = Vector2i(1920, 1080)
	host = load("res://app/main.tscn").instantiate()
	host.profile_path = "user://gomoku-ui-test-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(host)
	host.set_language("zh_CN")
	host.port.value = 29463
	host._start(true)
	host.session.room.hello(hello)
	host.session._publish()
	await process_frame
	await process_frame
	await process_frame
	var view = host.game_view
	check(host.immersive_game and not host.footer.visible and not host.page_title.visible, "fullscreen Mod hides duplicate platform chrome")
	check(view.board.get_global_rect().end.x <= view.sidebar.global_position.x, "TV board stays left of information")
	check(view.actions.global_position.y > view.players_row.global_position.y, "TV actions are below player information")
	check(view.settings_button.global_position.y < view.exit_button.global_position.y, "TV operations form a vertical list")
	check(view.names[0].text.contains("玩家") and view.names[1].text.contains("月亮") and view.clock_available, "both real identities and clocks shown")
	view.settings_button.pressed.emit()
	check(host.settings_dialog.visible, "Mod settings invokes platform setting panel")
	check(host.settings_dialog.get_theme_default_font().has_char("设".unicode_at(0)), "settings overlay inherits Chinese font across CanvasLayer")
	host.settings_dialog.close()
	check(root.gui_get_focus_owner() == view.settings_button, "closing settings returns to Mod action")
	root.size = Vector2i(540, 1170)
	await process_frame
	await process_frame
	await process_frame
	check(view.board.size.x >= 400, "phone preserves a large touch board")
	check(view.players_row.global_position.y >= view.board.get_global_rect().end.y, "phone identities move below board")
	check(view.actions.get_global_rect().end.y <= root.get_visible_rect().size.y, "phone actions fit safe viewport")
	check(view.player_panels[0].get_global_rect().end.x <= view.player_panels[1].global_position.x, "phone identities are side by side")
	var before_move: int = host.session.room.revision
	var pointer := InputEventMouseButton.new()
	pointer.button_index = MOUSE_BUTTON_LEFT
	pointer.pressed = true
	pointer.position = view.board.global_position + view.board.cell_center(7 * 15 + 7)
	root.push_input(pointer, true)
	pointer = pointer.duplicate()
	pointer.pressed = false
	root.push_input(pointer, true)
	await process_frame
	check(host.session.room.revision == before_move + 1, "phone board receives real viewport pointer input through sidebar")
	final.players = [{"nickname": "小星", "code": "aa1100", "connected": true}, {"nickname": "月亮", "code": "bb2200", "connected": true}]
	view.render(final)
	await process_frame
	await process_frame
	check(view.dialog_title.get_theme_font("font").has_char("赢".unicode_at(0)), "result overlay inherits a Chinese font across CanvasLayer")
	check(view.overlay.visible and view.dialog_title.text.contains("小星"), "game end opens dialog with actual winner name")
	check(view.dialog_summary.text.contains("9") and view.rematch_button.visible and view.dialog_exit.visible, "result shows moves, times and rematch/exit")
	check(view.board.focus_mode == Control.FOCUS_NONE, "result dialog traps game focus")
	check(view.dialog_panel.get_global_rect().end.x <= root.get_visible_rect().size.x and view.dialog_panel.get_global_rect().end.y <= root.get_visible_rect().size.y, "phone result dialog fits viewport")
	host._go_back()
	check(not view.overlay.visible and not host.leave_dialog.visible, "native back closes game dialog before requesting exit")
	view.render(final)
	check(not view.overlay.visible, "repeated snapshots do not reopen reviewed result")
	var next := final.duplicate(true)
	next.view = rules.initial_state(42)
	next.view.round = 2
	view.board.cursor = Vector2i(5, 4)
	view.render(next)
	check(view.board.cursor == Vector2i(7, 7), "new round recenters the TV cursor")
	check(not view.overlay.visible and view.board.focus_mode == Control.FOCUS_ALL, "new round restores board focusability")
	# Rendering alone cannot submit rematch consent. A stale response to an explicit
	# click can retry against the next authoritative snapshot, within the same round.
	var standalone = load("res://mods/gomoku/view.gd").new()
	root.add_child(standalone)
	standalone.set_platform_state({"enabled": true, "connected": true})
	var emitted := []
	standalone.command.connect(func(action): emitted.append(action))
	standalone.render(final)
	check(emitted.is_empty(), "render never sends consent")
	standalone._ask_rematch()
	check(emitted.size() == 1 and emitted[0].round == 1, "click carries explicit round consent")
	check(standalone.on_command_notice("stale_revision"), "concurrent consent revision is handled")
	var waiting := final.duplicate(true)
	waiting.view.rematch_votes = [false, true]
	standalone.render(waiting)
	check(emitted.size() == 1, "new snapshot does not itself send consent")
	await process_frame
	check(emitted.size() == 2, "explicit stale consent retries after snapshot")
	standalone.render(next)
	check(not standalone.on_command_notice("stale_revision"), "old consent cannot retry in a new round")
	standalone.queue_free()
	host._leave()
	check(not host.immersive_game and host.home.visible, "exit restores lobby and platform layout")
	DirAccess.remove_absolute(host.profile_path)
	host.queue_free()
	await process_frame
	print("GOMOKU_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
