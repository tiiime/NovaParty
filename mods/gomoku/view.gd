extends Control
signal command(action: Dictionary)
signal platform_action(action: String)
const UI = preload("ui.gd")
const Board = preload("board.gd")
var label: Label
var board
var turn_label: Label
var clock_hint: Label
var notice_label: Label
var players_row: BoxContainer
var player_panels: Array[PanelContainer] = []
var names: Array[Label] = []
var details: Array[Label] = []
var times: Array[Label] = []
var sidebar: Control
var actions: VBoxContainer
var result_button: Button
var settings_button: Button
var reconnect_button: Button
var exit_button: Button
var overlay: Control
var dialog_panel: PanelContainer
var dialog_title: Label
var dialog_summary: Label
var dialog_hint: Label
var rematch_button: Button
var dialog_exit: Button
var review_button: Button
var snapshot := {}
var platform := {"enabled": false, "connected": true, "can_reconnect": false, "message": ""}
var clock_elapsed := [0, 0]
var clock_running := -1
var clock_anchor := 0
var clock_available := false
var refresh_elapsed := 0.0
var result_seen_round := -1
var request_pending := false
var rematch_intent := -1
var localized_text := {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(280, 520)
	board = Board.new()
	board.name = "Board"
	var theme_path: String = get_script().resource_path.get_base_dir().path_join("theme.json")
	if FileAccess.file_exists(theme_path):
		var config = JSON.parse_string(FileAccess.get_file_as_string(theme_path))
		if config is Dictionary and config.get("board_color") is String:
			board.board_color = Color.from_string(config.board_color, board.board_color)
	board.place.connect(func(x, y): command.emit({"type": "place", "x": x, "y": y}))
	board.focus_actions.connect(_focus_actions)
	add_child(board)
	sidebar = Control.new()
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sidebar)
	label = _label(sidebar, 30)
	label.name = "GameTitle"
	turn_label = _label(sidebar, 24)
	turn_label.add_theme_stylebox_override("normal", UI.box(Color("e0edff"), 16))
	players_row = BoxContainer.new()
	players_row.add_theme_constant_override("separation", 12)
	sidebar.add_child(players_row)
	for seat in range(2):
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_panels.append(card)
		players_row.add_child(card)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 4)
		card.add_child(stack)
		var name_label := _label(stack, 23)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		names.append(name_label)
		var detail := _label(stack, 15)
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		details.append(detail)
		var time_label := _label(stack, 32)
		times.append(time_label)
	clock_hint = _label(sidebar, 18)
	clock_hint.add_theme_color_override("font_color", Color("5c708d"))
	notice_label = _label(sidebar, 18)
	notice_label.add_theme_color_override("font_color", Color("8b4d24"))
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	sidebar.add_child(actions)
	result_button = _button(actions, func(): _show_result())
	reconnect_button = _button(actions, func(): platform_action.emit("reconnect"))
	settings_button = _button(actions, func(): platform_action.emit("settings"))
	exit_button = _button(actions, func(): platform_action.emit("exit"))
	result_button.name = "Result"
	reconnect_button.name = "Reconnect"
	settings_button.name = "Settings"
	exit_button.name = "Exit"
	_build_dialog()
	resized.connect(_layout)
	_layout()
	_refresh_text()

func _label(parent: Node, font_size: int) -> Label:
	var item := Label.new()
	item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", UI.INK)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func _button(parent: Node, callback: Callable, primary: bool = false) -> Button:
	var item := Button.new()
	item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	UI.button(item, primary)
	parent.add_child(item)
	item.pressed.connect(callback)
	return item

func wants_fullscreen() -> bool:
	return true

func focus_default() -> void:
	board.grab_focus()

func restore_platform_focus(action: String) -> void:
	if overlay.visible:
		(review_button if rematch_button.disabled else rematch_button).grab_focus()
	elif action == "settings" and settings_button.visible:
		settings_button.grab_focus()
	elif action == "exit" and exit_button.visible:
		exit_button.grab_focus()
	else:
		board.grab_focus()

func set_platform_state(value: Dictionary) -> void:
	var was_connected: bool = platform.connected
	var elapsed := [_elapsed(0), _elapsed(1)]
	platform.merge(value, true)
	if was_connected and not platform.connected:
		clock_elapsed = elapsed
		clock_anchor = Time.get_ticks_msec()
		clock_running = -1
	if is_node_ready():
		if not snapshot.is_empty():
			board.active = not snapshot.view.finished and int(snapshot.view.turn) == int(snapshot.seat) and _both_online() and platform.connected
		_refresh_text()
		_layout()

func render(data: Dictionary) -> void:
	var previous_round: int = int(snapshot.get("view", {}).get("round", 0))
	snapshot = data.duplicate(true)
	if previous_round > 0 and int(snapshot.view.get("round", 1)) != previous_round:
		board.cursor = Vector2i(7, 7)
		rematch_intent = -1
	if overlay.theme.default_font != get_theme_default_font():
		overlay.theme.default_font = get_theme_default_font()
	request_pending = false
	var state: Dictionary = snapshot.view
	board.cells = state.board
	board.last_move = int(state.get("last_move", -1))
	board.winning_line = state.get("winning_line", [])
	board.active = not state.finished and int(state.turn) == int(snapshot.seat) and _both_online() and platform.connected
	board.queue_redraw()
	clock_available = snapshot.get("clock") is Dictionary and snapshot.clock.get("elapsed_ms") is Array and snapshot.clock.elapsed_ms.size() == 2
	if clock_available:
		clock_elapsed = snapshot.clock.elapsed_ms.duplicate()
		clock_running = int(snapshot.clock.get("running_seat", -1))
		clock_anchor = Time.get_ticks_msec()
	else:
		clock_running = -1
	_refresh_text()
	if state.finished:
		if result_seen_round != int(state.get("round", 1)):
			_show_result()
	else:
		if overlay.visible:
			_hide_result()
	_layout()

func _both_online() -> bool:
	return snapshot.get("players", []).size() == 2 and snapshot.players[0].get("connected", true) and snapshot.players[1].get("connected", true)

func _name(seat: int) -> String:
	if snapshot.get("players", []).size() <= seat:
		return _t("WAITING_PLAYER")
	var value: String = str(snapshot.players[seat].get("nickname", "")).strip_edges()
	return value if not value.is_empty() else _t("PLAYER") % [seat + 1]

func _refresh_text() -> void:
	label.text = _t("GOMOKU")
	settings_button.text = _t("SETTINGS")
	exit_button.text = _t("EXIT_GAME")
	reconnect_button.text = _t("RECONNECT")
	result_button.text = _t("VIEW_RESULT")
	settings_button.visible = bool(platform.enabled)
	exit_button.visible = bool(platform.enabled)
	reconnect_button.visible = bool(platform.enabled) and bool(platform.can_reconnect)
	dialog_exit.disabled = not bool(platform.enabled)
	if snapshot.is_empty():
		turn_label.text = str(platform.message) if not str(platform.message).is_empty() else _t("WAITING_PLAYER")
		result_button.hide()
		return
	var state: Dictionary = snapshot.view
	var local: int = int(snapshot.seat)
	var round_number: int = int(state.get("round", 1))
	var finished: bool = state.finished
	if finished:
		turn_label.text = _t("MATCH_FINISHED")
	elif not platform.connected or not _both_online():
		turn_label.text = _t("WAITING_PLAYER") if snapshot.players.size() < 2 else _t("PAUSED_DISCONNECTED")
	else:
		turn_label.text = (_t("YOUR_TURN") if int(state.turn) == local else _t("THEIR_TURN")) + " · " + _t("BLACK" if int(state.turn) == 0 else "WHITE")
	for seat in range(2):
		var present: bool = snapshot.players.size() > seat
		var online: bool = present and snapshot.players[seat].get("connected", true)
		var active: bool = not finished and int(state.turn) == seat and _both_online() and platform.connected
		player_panels[seat].add_theme_stylebox_override("panel", UI.box(Color("e2efff") if active else Color.WHITE, 20, UI.BLUE if active else Color("d4e1f1"), 3 if active else 1))
		names[seat].text = ("● " if seat == 0 else "○ ") + _name(seat)
		names[seat].tooltip_text = _name(seat)
		var code := str(snapshot.players[seat].get("code", "%02d" % [seat + 1])) if present else "—"
		details[seat].text = "#" + code + " · " + _t("BLACK" if seat == 0 else "WHITE") + (" · " + _t("YOU") if seat == local else "") + " · " + (_t("ONLINE") if online else _t("OFFLINE"))
	clock_hint.text = _t("CLOCK_TOTAL") if clock_available else _t("CLOCK_UNAVAILABLE")
	if not bool(platform.enabled):
		clock_hint.text += "\n" + _t("HOST_CONTROLS")
	notice_label.text = str(platform.message)
	notice_label.visible = not notice_label.text.is_empty()
	result_button.visible = finished and not reconnect_button.visible
	var votes: Array = state.get("rematch_votes", [false, false])
	rematch_button.text = _t("WAITING_REMATCH") if votes[local] else _t("ACCEPT_REMATCH") if votes[1 - local] else _t("PLAY_AGAIN")
	rematch_button.disabled = bool(votes[local]) or request_pending or not _both_online() or not platform.connected
	dialog_exit.text = _t("EXIT_GAME")
	review_button.text = _t("REVIEW_BOARD")
	if finished:
		var winner: int = int(state.winner)
		dialog_title.text = _t("DRAW") if winner == -1 else _t("WINNER_NAME") % [_name(winner)]
		var outcome := _t("DRAW") if winner == -1 else _t("YOU_WIN") if winner == local else _t("YOU_LOSE")
		dialog_summary.text = outcome + "\n" + _t("RESULT_META") % [round_number, int(state.moves)] + "\n" + _t("RESULT_CLOCKS") % [_name(0), _clock_string(0), _name(1), _clock_string(1)]
		dialog_hint.text = _t("WAITING_REMATCH") if votes[local] else _t("FRIEND_REQUESTED") if votes[1 - local] else _t("REMATCH_HELP")
		if not _both_online() or not platform.connected:
			dialog_hint.text = _t("PAUSED_DISCONNECTED")
	_update_clocks()
	_update_focus()

func _elapsed(seat: int) -> int:
	return int(clock_elapsed[seat]) + (maxi(0, Time.get_ticks_msec() - clock_anchor) if clock_running == seat and platform.connected else 0)

func _clock_string(seat: int) -> String:
	if not clock_available:
		return "—:—"
	var seconds := int(_elapsed(seat) / 1000)
	return "%02d:%02d" % [int(seconds / 60), seconds % 60]

func _update_clocks() -> void:
	for seat in range(times.size()):
		times[seat].text = _clock_string(seat)

func _process(delta: float) -> void:
	refresh_elapsed += delta
	if refresh_elapsed >= .1:
		refresh_elapsed = 0
		_update_clocks()

func _focus_actions() -> void:
	for item in actions.get_children():
		if item.visible and not item.disabled:
			item.grab_focus()
			return

func _update_focus() -> void:
	var buttons := []
	for item in actions.get_children():
		if item.visible and not item.disabled:
			buttons.append(item)
	for index in range(buttons.size()):
		var item: Button = buttons[index]
		item.focus_neighbor_left = item.get_path_to(board)
		item.focus_neighbor_top = item.get_path_to(board if index == 0 else buttons[index - 1])
		item.focus_neighbor_bottom = item.get_path_to(buttons[(index + 1) % buttons.size()])
		item.focus_next = item.focus_neighbor_bottom
		item.focus_previous = item.focus_neighbor_top
	if not buttons.is_empty():
		board.focus_next = board.get_path_to(buttons[0])

func _layout() -> void:
	if not is_instance_valid(sidebar):
		return
	var portrait := size.x < 760
	var width := size.x
	var height := size.y
	players_row.vertical = not portrait
	if portrait:
		sidebar.position = Vector2.ZERO
		sidebar.size = size
		label.position = Vector2.ZERO
		label.size = Vector2(width, 38)
		turn_label.position = Vector2(0, 44)
		turn_label.size = Vector2(width, 46)
		var extent := maxf(240, minf(width, height - 440))
		board.position = Vector2((width - extent) / 2, 106)
		board.size = Vector2.ONE * extent
		players_row.position = Vector2(0, 124 + extent)
		players_row.size = Vector2(width, 142)
		for panel in player_panels:
			panel.custom_minimum_size = Vector2(0, 142)
		for item in details:
			item.add_theme_font_size_override("font_size", 13)
		for item in names:
			item.add_theme_font_size_override("font_size", 20)
		for item in times:
			item.add_theme_font_size_override("font_size", 28)
		clock_hint.position = Vector2(0, 276 + extent)
		clock_hint.size = Vector2(width, 28)
	else:
		var side_width := clampf(width * .30, 300, 390)
		var left_width := width - side_width - 32
		var extent := minf(left_width - 12, height - 12)
		board.position = Vector2((left_width - extent) / 2, (height - extent) / 2)
		board.size = Vector2.ONE * extent
		sidebar.position = Vector2(left_width + 32, 0)
		sidebar.size = Vector2(side_width, height)
		label.position = Vector2.ZERO
		label.size = Vector2(side_width, 40)
		turn_label.position = Vector2(0, 50)
		turn_label.size = Vector2(side_width, 62)
		players_row.position = Vector2(0, 128)
		players_row.size = Vector2(side_width, 284)
		for panel in player_panels:
			panel.custom_minimum_size = Vector2(0, 136)
		for item in details:
			item.add_theme_font_size_override("font_size", 15)
		for item in names:
			item.add_theme_font_size_override("font_size", 22)
		for item in times:
			item.add_theme_font_size_override("font_size", 30)
		clock_hint.position = Vector2(0, 424)
		clock_hint.size = Vector2(side_width, 44)
	var action_height := actions.get_combined_minimum_size().y
	actions.position = Vector2(0, maxf(0, sidebar.size.y - action_height))
	actions.size = Vector2(sidebar.size.x, action_height)
	notice_label.position = Vector2(0, actions.position.y - 62)
	notice_label.size = Vector2(sidebar.size.x, 54)
	if notice_label.visible and notice_label.position.y < clock_hint.position.y + clock_hint.size.y + 6:
		notice_label.hide()
		clock_hint.text = str(platform.message)
	_layout_dialog()

func _build_dialog() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	overlay = Control.new()
	# CanvasLayer is a theme boundary on iOS: carry the host font explicitly.
	overlay.theme = Theme.new()
	overlay.theme.default_font = get_theme_default_font()
	overlay.theme.default_font_size = 22
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(.025, .07, .18, .55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	dialog_panel = PanelContainer.new()
	dialog_panel.add_theme_stylebox_override("panel", UI.box(Color("f5f9ff"), 28, Color("d6e7fa"), 2))
	overlay.add_child(dialog_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	dialog_panel.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	dialog_title = _label(body, 30)
	dialog_summary = _label(body, 21)
	dialog_hint = _label(body, 20)
	dialog_hint.add_theme_color_override("font_color", Color("546e8a"))
	rematch_button = _button(content, _ask_rematch, true)
	rematch_button.name = "Rematch"
	dialog_exit = _button(content, func(): platform_action.emit("exit"))
	dialog_exit.name = "DialogExit"
	review_button = _button(content, _hide_result)
	review_button.flat = true
	overlay.resized.connect(_layout_dialog)
	overlay.hide()

func _layout_dialog() -> void:
	if not is_instance_valid(dialog_panel) or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var available := viewport_size - Vector2(48, 96)
	dialog_panel.size = Vector2(minf(560, available.x), minf(580, available.y))
	dialog_panel.position = (viewport_size - dialog_panel.size) / 2

func _show_result() -> void:
	if snapshot.is_empty() or not snapshot.view.finished:
		return
	result_seen_round = int(snapshot.view.get("round", 1))
	overlay.show()
	_layout_dialog()
	for item in [board, result_button, settings_button, reconnect_button, exit_button]:
		item.focus_mode = Control.FOCUS_NONE
	var buttons := [rematch_button, dialog_exit, review_button]
	for i in range(buttons.size()):
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i + 2) % 3])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % 3])
		buttons[i].focus_next = buttons[i].focus_neighbor_bottom
		buttons[i].focus_previous = buttons[i].focus_neighbor_top
		buttons[i].focus_neighbor_left = buttons[i].get_path()
		buttons[i].focus_neighbor_right = buttons[i].get_path()
	if not rematch_button.disabled:
		rematch_button.grab_focus()
	else:
		review_button.grab_focus()

func _hide_result() -> void:
	overlay.hide()
	for item in [board, result_button, settings_button, reconnect_button, exit_button]:
		item.focus_mode = Control.FOCUS_ALL
	if result_button.visible:
		result_button.grab_focus()
	else:
		board.grab_focus()

func _ask_rematch() -> void:
	if rematch_button.disabled or request_pending:
		return
	request_pending = true
	rematch_intent = int(snapshot.view.get("round", 1))
	rematch_button.disabled = true
	command.emit({"type": "rematch", "round": rematch_intent})

# Concurrent consent can arrive against the same revision. Retry only this explicit
# user intent after the authoritative snapshot catches up, never from render().
func on_command_notice(code: String) -> bool:
	if code == "stale_revision" and rematch_intent == int(snapshot.view.get("round", 1)) and snapshot.view.finished:
		_retry_rematch.call_deferred()
		return true
	return false

func _retry_rematch() -> void:
	if not is_inside_tree() or snapshot.is_empty() or not snapshot.view.finished or int(snapshot.view.get("round", 1)) != rematch_intent or not _both_online() or not platform.connected:
		return
	var votes: Array = snapshot.view.get("rematch_votes", [false, false])
	if not votes[int(snapshot.seat)]:
		command.emit({"type": "rematch", "round": rematch_intent})

func handle_platform_back() -> bool:
	if overlay.visible:
		_hide_result()
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and handle_platform_back():
		get_viewport().set_input_as_handled()

func capture_view_state() -> Dictionary:
	return {"cursor": [board.cursor.x, board.cursor.y], "focused": board.has_focus(), "board_color": board.board_color.to_html(false), "result_seen_round": result_seen_round, "result_open": overlay.visible, "rematch_intent": rematch_intent}

func restore_view_state(state: Dictionary) -> void:
	var cursor = state.get("cursor", [7, 7])
	if cursor is Array and cursor.size() == 2:
		board.cursor = Vector2i(clampi(int(cursor[0]), 0, 14), clampi(int(cursor[1]), 0, 14))
	rematch_intent = int(state.get("rematch_intent", -1))
	if state.has("result_seen_round"):
		result_seen_round = int(state.result_seen_round)
		if state.get("result_open", false):
			_show_result()
		else:
			_hide_result()
	if state.get("focused", false):
		board.grab_focus()
	board.queue_redraw()

func _t(key: String) -> String:
	if localized_text.is_empty():
		var root: String = get_script().resource_path.get_base_dir()
		for language in ["en", "zh"]:
			var data = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("locale-" + language + ".json")))
			localized_text[language] = data if data is Dictionary else {}
	var locale := TranslationServer.get_locale().get_slice("_", 0)
	var messages: Dictionary = localized_text.get(locale, localized_text.en)
	return str(messages.get(key, localized_text.en.get(key, key)))
