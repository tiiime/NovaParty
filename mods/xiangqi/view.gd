extends Control
signal command(action: Dictionary)
signal platform_action(action: String)

const Board = preload("board.gd")
const BG := Color("faf6ed")
const INK := Color("2c2924")
const MUTED := Color("63584c")
const ACCENT := Color("a1392d")
var snapshot := {}
var platform := {"connected": true, "can_invite": false, "can_reconnect": false, "input_paused": false}
var board: Control
var frame: BoxContainer
var panel: VBoxContainer
var headline: VBoxContainer
var title_label: Label
var players_label: Label
var status_label: Label
var hint_label: Label
var buttons := {}
var words := {}
var pending := false
var rematch_round := -1
var notice := ""
var resign_prompt := false

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	var bg := ColorRect.new()
	bg.color = BG
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: inset.add_theme_constant_override("margin_" + edge, 16)
	add_child(inset)
	frame = BoxContainer.new()
	frame.add_theme_constant_override("separation", 20)
	inset.add_child(frame)
	board = Board.new()
	board.name = "Board"
	board.size_flags_horizontal = SIZE_EXPAND_FILL
	board.size_flags_vertical = SIZE_EXPAND_FILL
	board.chosen.connect(_board_pick)
	board.escape_requested.connect(_focus_actions)
	frame.add_child(board)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	frame.add_child(panel)
	headline = VBoxContainer.new()
	headline.add_theme_constant_override("separation", 8)
	panel.add_child(headline)
	title_label = _label(headline, 30, INK)
	players_label = _label(headline, 18, MUTED)
	status_label = _label(headline, 22, ACCENT)
	hint_label = _label(panel, 17, MUTED)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)
	for key in ["decline_undo", "accept_undo", "cancel_undo", "request_undo", "rematch", "reconnect", "settings", "invite", "exit", "resign", "confirm_resign", "cancel"]:
		var button := Button.new()
		button.name = key
		button.custom_minimum_size.y = 52
		button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
		button.add_theme_font_size_override("font_size", 18)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_style(button, key in ["invite", "rematch", "accept_undo"], key == "confirm_resign")
		grid.add_child(button)
		buttons[key] = button
		button.pressed.connect(_action.bind(key))
	resized.connect(_layout)
	_layout()
	_refresh()

func _label(parent: Control, extent: int, tint: Color) -> Label:
	var item := Label.new()
	item.auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
	item.add_theme_font_size_override("font_size", extent)
	item.add_theme_color_override("font_color", tint)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func _box(fill: Color, border: Color, bottom: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(2)
	b.border_width_bottom = bottom
	b.set_corner_radius_all(12)
	b.set_content_margin_all(10)
	return b

func _style(button: Button, primary: bool, danger: bool) -> void:
	var fill := Color("ffe079") if primary else Color("fffef9")
	var edge := Color("967031") if primary else Color("b7aa96")
	if danger:
		fill = Color("ffe6de")
		edge = ACCENT
	button.add_theme_stylebox_override("normal", _box(fill, edge, 4))
	button.add_theme_stylebox_override("hover", _box(fill.darkened(.06), edge, 4))
	button.add_theme_stylebox_override("pressed", _box(fill.darkened(.13), edge, 2))
	button.add_theme_stylebox_override("disabled", _box(Color("ebe4d8"), Color("c4b8a5"), 2))
	var ring := _box(Color.TRANSPARENT, Color("284ac4"), 4)
	ring.set_border_width_all(4)
	ring.set_expand_margin_all(2)
	button.add_theme_stylebox_override("focus", ring)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)

func _layout() -> void:
	var wide := size.x >= 760
	frame.vertical = not wide
	var header_parent: Control = panel if wide else frame
	if headline.get_parent() != header_parent:
		headline.reparent(header_parent, false)
		header_parent.move_child(headline, 0)
	frame.add_theme_constant_override("separation", 20 if wide else 8)
	panel.custom_minimum_size.x = clampf(size.x * .32, 272, 390) if wide else 0.0
	panel.size_flags_vertical = SIZE_SHRINK_CENTER if wide else SIZE_FILL
	title_label.add_theme_font_size_override("font_size", 36 if wide else 26)

func wants_fullscreen() -> bool: return true
func fullscreen_background() -> Color: return BG

func render(value: Dictionary) -> void:
	var changed: bool = snapshot.get("revision", -1) != value.get("revision", -1)
	var before: Dictionary = snapshot.get("view", {})
	snapshot = value
	if changed:
		pending = false
		notice = ""
		board.selected = -1
	if before.get("round") != value.view.round: rematch_round = -1
	if before.get("round") != value.view.round or value.view.phase == "finished" or int(value.view.undo_by) >= 0: resign_prompt = false
	_refresh()
	if before.get("undo_by", -1) != value.view.undo_by and buttons.decline_undo.visible and _enabled():
		var focused := get_viewport().gui_get_focus_owner()
		if is_visible_in_tree() and (focused == null or is_ancestor_of(focused)):
			buttons.decline_undo.grab_focus()

func set_platform_state(value: Dictionary) -> void:
	platform.merge(value, true)
	if not platform.connected:
		pending = false
		rematch_round = -1
		resign_prompt = false
	_refresh()

func _both_online() -> bool:
	var players: Array = snapshot.get("players", [])
	return players.size() == 2 and players[0].get("connected", true) and players[1].get("connected", true)

func _enabled() -> bool:
	return not snapshot.is_empty() and _both_online() and platform.connected and not platform.input_paused and not pending

func _name(seat: int) -> String:
	var players: Array = snapshot.get("players", [])
	if seat >= players.size(): return _t("open_seat")
	return str(players[seat].get("nickname", "")).strip_edges().left(16)

func _refresh() -> void:
	if board == null: return
	var focused := get_viewport().gui_get_focus_owner()
	var was_in_actions := focused != null and panel.is_ancestor_of(focused)
	var seat := int(snapshot.get("seat", 0))
	var state: Dictionary = snapshot.get("view", {})
	var phase := str(state.get("phase", "play"))
	var ready := _enabled()
	var finished := phase == "finished"
	var my_turn := int(state.get("turn", -1)) == seat
	var requester := int(state.get("undo_by", -1))
	var can_request := bool(state.get("can_undo", false)) and not my_turn
	title_label.text = _t("name")
	players_label.text = "%s · %s\n%s · %s" % [_t("side0"), _name(0), _t("side1"), _name(1)]
	status_label.text = _status(state, seat, my_turn)
	hint_label.text = _hint(state, seat, ready, my_turn)
	if not notice.is_empty(): hint_label.text = _t(notice)
	if resign_prompt:
		status_label.text = _t("resign_question")
		hint_label.text = _t("resign_help")
	var show_buttons := {
		"settings": true, "exit": true, "reconnect": platform.can_reconnect,
		"invite": platform.can_invite and snapshot.get("players", []).size() < 2,
		"resign": _both_online() and not finished and requester < 0, "rematch": finished and requester < 0,
		"request_undo": can_request and requester < 0 and _both_online(),
		"accept_undo": requester >= 0 and requester != seat, "decline_undo": requester >= 0 and requester != seat,
		"cancel_undo": requester == seat,
	}
	if resign_prompt: show_buttons = {"confirm_resign": true, "cancel": true}
	for key in buttons:
		buttons[key].text = _t(key)
		buttons[key].visible = show_buttons.get(key, false)
		buttons[key].disabled = (not ready and key not in ["settings", "invite", "exit", "reconnect", "cancel"]) or (key == "rematch" and bool(state.get("votes", [false, false])[seat]))
	board.apply_view(state, seat, _can_move())
	_link_focus()
	if was_in_actions and (not focused.visible or focused.disabled) and not platform.input_paused:
		_focus_actions()

func _status(state: Dictionary, seat: int, my_turn: bool) -> String:
	if not platform.connected:
		var message := str(platform.get("message", ""))
		return message if not message.is_empty() else _t("offline")
	if snapshot.get("players", []).size() < 2: return _t("waiting")
	if not _both_online(): return _t("offline")
	if pending: return _t("sending")
	if int(state.get("undo_by", -1)) >= 0:
		return _t("undo_wait" if int(state.undo_by) == seat else "undo_incoming")
	if state.get("phase") == "finished": return _t("win" if int(state.winner) == seat else "loss")
	return _t("your_turn" if my_turn else "their_turn")

func _hint(state: Dictionary, seat: int, ready: bool, my_turn: bool) -> String:
	if not platform.connected or (snapshot.get("players", []).size() == 2 and not _both_online()): return _t("offline_help")
	if int(state.get("undo_by", -1)) >= 0:
		return _t("undo_help_wait" if int(state.undo_by) == seat else "undo_help_incoming")
	if not str(state.get("undo_result", "")).is_empty(): return _t(str(state.undo_result))
	if state.get("phase") == "finished":
		var result := _t(str(state.reason)) if not state.reason.is_empty() else ""
		return result + ("\n" + _t("rematch_wait") if state.votes[seat] else "")
	if snapshot.get("players", []).size() < 2: return _t("invite_help")
	if ready and my_turn: return _t("play_help")
	return _t("round") % int(state.get("round", 1))

func _can_move() -> bool:
	return _enabled() and not resign_prompt and snapshot.view.phase == "play" and int(snapshot.view.undo_by) < 0 and int(snapshot.view.turn) == int(snapshot.seat)

func _own_piece(index: int) -> bool:
	var cells: Array = snapshot.get("view", {}).get("board", [])
	return index >= 0 and index < cells.size() and int(cells[index]) * (1 if int(snapshot.seat) == 0 else -1) > 0

func _board_pick(index: int) -> void:
	if not _can_move() or index < 0 or index >= Board.POINTS: return
	if _own_piece(index):
		board.selected = -1 if index == board.selected else index
		notice = ""
		_refresh()
	elif board.selected >= 0:
		_submit({"type": "move", "from": board.selected, "to": index})
	else:
		notice = "choose_piece"
		_refresh()

func _action(key: String) -> void:
	if key in ["settings", "invite", "reconnect", "exit"]:
		platform_action.emit(key)
		return
	if key == "cancel":
		resign_prompt = false
		_refresh()
		if buttons.resign.visible: buttons.resign.grab_focus()
		return
	if not _enabled() or not buttons.has(key) or not buttons[key].visible or buttons[key].disabled: return
	if key == "resign":
		resign_prompt = true
		_refresh()
		buttons.cancel.grab_focus()
		return
	if key == "confirm_resign":
		if not resign_prompt: return
		resign_prompt = false
		key = "resign"
	if key == "rematch": rematch_round = int(snapshot.view.round)
	_submit({"type": key})

func _submit(action: Dictionary) -> void:
	if not _enabled(): return
	pending = true
	notice = ""
	_refresh()
	platform_action.emit("haptic:select")
	command.emit(action)

func on_command_notice(code: String) -> bool:
	if not pending: return false
	pending = false
	platform_action.emit("haptic:warn")
	if code == "stale_revision" and rematch_round >= 0:
		_retry_rematch(int(snapshot.get("revision", -1)))
		return true
	rematch_round = -1
	notice = code if code in ["illegal_move", "undo_unavailable", "undo_pending"] else "retry"
	_refresh()
	return true

func _can_retry_rematch() -> bool:
	return _enabled() and snapshot.view.phase == "finished" and int(snapshot.view.round) == rematch_round and not snapshot.view.votes[int(snapshot.seat)]

func _retry_rematch(old_revision: int) -> void:
	await get_tree().create_timer(.15).timeout
	if not is_inside_tree() or not _can_retry_rematch(): return
	if int(snapshot.revision) > old_revision:
		_submit({"type": "rematch"})
	else:
		rematch_round = -1
		notice = "retry"
		_refresh()

func focus_default() -> void:
	if buttons.invite.visible: buttons.invite.grab_focus()
	elif buttons.decline_undo.visible and not buttons.decline_undo.disabled: buttons.decline_undo.grab_focus()
	elif buttons.cancel_undo.visible and not buttons.cancel_undo.disabled: buttons.cancel_undo.grab_focus()
	else: board.grab_focus()

func restore_platform_focus(action: String) -> void:
	var button: Button = buttons.get(action)
	if button != null and button.visible and not button.disabled: button.grab_focus()
	else: focus_default()

func _focus_actions() -> void:
	for button in buttons.values():
		if button.visible and not button.disabled and button.focus_mode != FOCUS_NONE:
			button.grab_focus()
			return

func _link_focus() -> void:
	var entries := []
	for button in buttons.values():
		if button.visible and not button.disabled: entries.append(button)
	if entries.is_empty(): return
	board.focus_next = board.get_path_to(entries.front())
	board.focus_previous = board.get_path_to(entries.back())
	for index in range(entries.size()):
		var b: Button = entries[index]
		b.focus_next = b.get_path_to(entries[index + 1] if index + 1 < entries.size() else board)
		b.focus_previous = b.get_path_to(entries[index - 1] if index > 0 else board)
		b.focus_neighbor_left = b.get_path_to(entries[index - 1] if index % 2 == 1 else board)
		b.focus_neighbor_right = b.get_path_to(entries[index + 1] if index % 2 == 0 and index + 1 < entries.size() else b)
		b.focus_neighbor_top = b.get_path_to(entries[index - 2] if index >= 2 else board)
		b.focus_neighbor_bottom = b.get_path_to(entries[index + 2] if index + 2 < entries.size() else b)

func handle_platform_back() -> bool:
	if resign_prompt:
		_action("cancel")
		return true
	if board.selected >= 0:
		board.selected = -1
		_refresh()
		return true
	return false

func capture_view_state() -> Dictionary:
	return {"cursor": board.cursor, "selected": board.selected}

func restore_view_state(value: Dictionary) -> void:
	board.cursor = clampi(int(value.get("cursor", 40)), 0, Board.POINTS - 1)
	var wanted := int(value.get("selected", -1))
	board.selected = wanted if _own_piece(wanted) and int(snapshot.view.turn) == int(snapshot.seat) else -1
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): _refresh()

func _t(key: String) -> String:
	var lang := "zh" if TranslationServer.get_locale().begins_with("zh") else "en"
	if not words.has(lang):
		var dir: String = get_script().resource_path.get_base_dir()
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("locale-" + lang + ".json")))
		words[lang] = data if data is Dictionary else {}
	return str(words[lang].get(key, key))
