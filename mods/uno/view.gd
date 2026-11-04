extends Control
signal command(action: Dictionary)
signal platform_action(action: String)
const Cards = preload("cards.gd")
const Rules = preload("rules.gd")
const INK = Color("382923")
const PALETTE = [Color("e4584b"), Color("f3c747"), Color("46a780"), Color("4b8dcc")]
var snapshot := {}
var platform := {"connected": true, "input_paused": false}
var services
var messages := {}
var root_box: VBoxContainer
var roster: Control
var header: Label
var status: Label
var detail: Label
var notice: Label
var top_card: Button
var hand_scroll: ScrollContainer
var table_row: HBoxContainer
var qr_source: Texture2D
var qr: TextureRect
var actions: GridContainer
var hand_row: Control
var draw_button: Button
var start_button: Button
var table_toggle: CheckButton
var settings_button: Button
var exit_button: Button
var result_exit: Button
var result_rematch: Button
var uno_toggle: CheckButton
var catch_button: Button
var result_dialog: AcceptDialog
var color_dialog: AcceptDialog
var help_dialog: AcceptDialog
var color_buttons := []
var rules_button: Button
var chosen_wild := -1
var seen_round := -1
var rematch_intent := -1
var armed := false
var card_focus := -1
var hand_buttons := []
var legal := []
var stage: Control
var table_art: TextureRect
var menu_button: Button
var menu_panel: PanelContainer
var deck_art: TextureRect
var direction_label: Label
var self_label: Label
var selected_card := -1
var art_cache := {}
var logical_size := Vector2(1920, 1080)
var wide_layout := true
var public_layout := true


func _ready() -> void:
	custom_minimum_size = Vector2(280, 360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", _box(Color("edf4ff"), 26))
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	header = _label(root_box, 28)
	roster = Control.new()
	root_box.add_child(roster)
	status = _label(root_box, 23)
	var table := HBoxContainer.new()
	table_row = table
	table.alignment = BoxContainer.ALIGNMENT_CENTER
	table.add_theme_constant_override("separation", 16)
	root_box.add_child(table)
	top_card = _button(table, "TopCard", func(): pass)
	top_card.custom_minimum_size = Vector2(100, 128)
	top_card.disabled = true
	top_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qr = TextureRect.new()
	qr.custom_minimum_size = Vector2(128, 128)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	table.add_child(qr)
	detail = _label(root_box, 18)
	notice = _label(root_box, 18)
	notice.add_theme_color_override("font_color", Color("9c441f"))
	notice.hide()
	actions = GridContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	root_box.add_child(actions)
	start_button = _button(actions, "Start", func(): _submit({"type": "start" if snapshot.view.phase == "lobby" else "rematch"}))
	table_toggle = CheckButton.new()
	table_toggle.name = "TableMode"
	_style_button(table_toggle)
	table_toggle.text = _t("TABLE_MODE")
	table_toggle.toggled.connect(func(value): _submit({"type": "table_mode", "enabled": value}))
	actions.add_child(table_toggle)
	draw_button = _button(actions, "Draw", func(): _submit({"type": "pass" if snapshot.view.drawn != -1 else "draw"}))
	uno_toggle = CheckButton.new()
	uno_toggle.name = "DeclareUNO"
	_style_button(uno_toggle)
	uno_toggle.toggled.connect(func(value): armed = value)
	actions.add_child(uno_toggle)
	catch_button = _button(actions, "CallUNO", func(): _submit({"type": "uno" if snapshot.view.uno_target == snapshot.seat else "catch"}))
	var scroller := ScrollContainer.new()
	hand_scroll = scroller
	scroller.name = "HandScroll"
	scroller.custom_minimum_size.y = 170
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	root_box.add_child(scroller)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: padding.add_theme_constant_override("margin_" + side, 8)
	scroller.add_child(padding)
	hand_row = Control.new()
	hand_row.name = "Hand"
	padding.add_child(hand_row)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root_box.add_child(footer)
	rules_button = _button(footer, "Rules", func():
		if not snapshot.is_empty() and snapshot.view.phase == "finished": result_dialog.popup_centered(Vector2i(mini(620, int(get_viewport_rect().size.x) - 32), 240))
		else: help_dialog.popup_centered(Vector2i(mini(680, int(get_viewport_rect().size.x) - 32), 420))
	)
	rules_button.text = _t("RULES_TITLE")
	settings_button = _button(footer, "Settings", func(): platform_action.emit("settings"))
	settings_button.text = _t("SETTINGS")
	exit_button = _button(footer, "Exit", func(): platform_action.emit("exit"))
	exit_button.text = _t("EXIT")
	_build_dialogs()
	stage = Control.new()
	stage.name = "TableStage"
	add_child(stage)
	table_art = _art(stage, "table-wide")
	table_art.z_index = 0
	deck_art = _art(stage, "back")
	deck_art.rotation_degrees = -9
	direction_label = _label(stage, 72)
	direction_label.text = "↻"
	direction_label.add_theme_color_override("font_color", Color("ebc18b"))
	direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	self_label = _label(stage, 24)
	for node in [header, roster, status, top_card, qr, detail, notice, start_button, table_toggle, draw_button, uno_toggle, catch_button, hand_scroll]:
		node.reparent(stage)
	root_box.hide()
	margin.hide()
	background.hide()
	menu_button = _button(stage, "Menu", func():
		menu_panel.visible = not menu_panel.visible
		if menu_panel.visible: rules_button.grab_focus()
		else: menu_button.grab_focus()
	)
	menu_button.text = "☰"
	menu_panel = PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", _box(Color("fff3d8"), 24))
	stage.add_child(menu_panel)
	var menu_list := VBoxContainer.new()
	menu_panel.add_child(menu_list)
	for button in [rules_button, settings_button, exit_button]: button.reparent(menu_list)
	menu_panel.hide()
	resized.connect(_layout)
	_layout()

func _box(fill: Color, radius: int = 16, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _style_button(button: BaseButton) -> void:
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_stylebox_override("normal", _box(Color("fff3d8"), 18, Color("88583e"), 2))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 16, Color("ff8a1c"), 5))
	button.add_theme_stylebox_override("hover", _box(Color("fff0b3")))
	button.add_theme_stylebox_override("pressed", _box(Color("ffd961")))
	button.add_theme_stylebox_override("disabled", _box(Color("624c40"), 18))
	button.add_theme_color_override("font_disabled_color", Color("c0ab91"))

func _button(parent: Node, key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_style_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff3d8"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_dialogs() -> void:
	color_dialog = AcceptDialog.new()
	color_dialog.title = _t("CHOOSE_COLOR")
	color_dialog.get_ok_button().hide()
	var grid := GridContainer.new()
	grid.columns = 2
	color_dialog.add_child(grid)
	for color in range(4):
		var button := _button(grid, "Color_" + str(color), func():
			color_dialog.hide()
			_submit({"type": "play", "card": chosen_wild, "color": color, "uno": armed})
			armed = false
		)
		color_buttons.append(button)
		button.text = _t(Cards.COLORS[color])
		button.custom_minimum_size = Vector2(120, 64)
		button.add_theme_stylebox_override("normal", _box(PALETTE[color]))
		button.add_theme_color_override("font_color", Color.WHITE if color != 1 else INK)
	add_child(color_dialog)
	help_dialog = AcceptDialog.new()
	help_dialog.title = _t("RULES_TITLE")
	help_dialog.dialog_text = _t("RULES_BODY")
	help_dialog.dialog_autowrap = true
	add_child(help_dialog)
	result_dialog = AcceptDialog.new()
	result_dialog.title = _t("RESULT")
	result_dialog.dialog_autowrap = true
	result_dialog.ok_button_text = _t("REVIEW")
	result_rematch = result_dialog.add_button(_t("REMATCH"), false, "rematch")
	result_exit = result_dialog.add_button(_t("EXIT"), true, "exit")
	result_dialog.custom_action.connect(func(action):
		result_dialog.hide()
		if action == "rematch": _submit({"type": "rematch"})
		else: platform_action.emit("exit")
	)
	add_child(result_dialog)
	for dialog in [color_dialog, help_dialog, result_dialog]:
		dialog.theme = Theme.new()
		dialog.theme.default_font = get_theme_default_font()
		dialog.theme.default_font_size = 22
		dialog.add_theme_stylebox_override("panel", _box(Color("fff3d8"), 24))
		dialog.add_theme_color_override("font_color", INK)
		_style_button(dialog.get_ok_button())
	_style_button(result_rematch)
	_style_button(result_exit)

func _texture(key: String) -> Texture2D:
	if not art_cache.has(key):
		var image := Image.new()
		var path: String = get_script().resource_path.get_base_dir().path_join("art/" + key + ".svg.txt")
		if image.load_svg_from_string(FileAccess.get_file_as_string(path)) != OK: return null
		art_cache[key] = ImageTexture.create_from_image(image)
	return art_cache[key]

func _art(parent: Node, key: String) -> TextureRect:
	var node := TextureRect.new()
	node.texture = _texture(key)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _place(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)

func _layout() -> void:
	if not is_node_ready() or stage == null: return
	var previous_wide := wide_layout
	wide_layout = size.x > size.y
	if previous_wide != wide_layout and not snapshot.is_empty(): _build_roster(snapshot.view)
	public_layout = not snapshot.is_empty() and snapshot.seat == snapshot.view.display_seat
	logical_size = Vector2(1920,1080) if wide_layout else Vector2(540,1100)
	var factor := minf(size.x / logical_size.x, size.y / logical_size.y)
	stage.scale = Vector2.ONE * factor
	stage.size = logical_size
	stage.position = (size - logical_size * factor) * .5
	_place(table_art, 0, 0, logical_size.x, logical_size.y)
	table_art.texture = _texture("table-wide" if wide_layout else "table-phone")
	_place(header, 96 if wide_layout else 24, 45 if wide_layout else 20, 1300 if wide_layout else 420, 52)
	header.add_theme_font_size_override("font_size", 36 if wide_layout else 26)
	_place(menu_button, 1760 if wide_layout else 452, 50 if wide_layout else 20, 64, 60)
	_place(menu_panel, 1450 if wide_layout else 210, 120 if wide_layout else 90, 370 if wide_layout else 306, 210)
	menu_panel.z_index = 30
	_place(roster, 0, 0, logical_size.x, logical_size.y)
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_seats()
	var lobby: bool = snapshot.is_empty() or snapshot.view.phase == "lobby"
	_place(status, 550 if wide_layout else 50, 132 if wide_layout else 265, 820 if wide_layout else 440, 60)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 30 if wide_layout else 24)
	status.add_theme_stylebox_override("normal", _box(Color("fff3d8"), 28))
	status.add_theme_color_override("font_color", INK)
	_place(top_card, 1000 if wide_layout else 292, 405 if wide_layout else 356, 190 if wide_layout else 110, 282 if wide_layout else 162)
	_place(deck_art, 760 if wide_layout else 142, 420 if wide_layout else 370, 160 if wide_layout else 98, 238 if wide_layout else 144)
	deck_art.visible = not lobby
	_place(direction_label, 680 if wide_layout else 95, 330 if wide_layout else 318, 560 if wide_layout else 350, 370 if wide_layout else 260)
	direction_label.visible = not lobby
	direction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	direction_label.text = "↻" if snapshot.is_empty() or snapshot.view.direction == 1 else "↺"
	direction_label.z_index = 0
	_place(draw_button, 720 if wide_layout else 110, 675 if wide_layout else 530, 240 if wide_layout else 160, 60)
	_place(detail, 650 if wide_layout else 70, 750 if wide_layout else 610, 620 if wide_layout else 400, 85)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(notice, 500 if wide_layout else 30, 215 if wide_layout else 700, 920 if wide_layout else 480, 65)
	_place(qr, 820 if wide_layout else 160, 355 if wide_layout else 360, 280 if wide_layout else 220, 280 if wide_layout else 220)
	_place(start_button, 770 if wide_layout else 120, 850 if wide_layout else 885, 380 if wide_layout else 300, 64)
	_place(table_toggle, 770 if wide_layout else 120, 925 if wide_layout else 960, 380 if wide_layout else 300, 60)
	_place(uno_toggle, 1400 if wide_layout else 345, 790 if wide_layout else 710, 260 if wide_layout else 170, 60)
	_place(catch_button, 1400 if wide_layout else 300, 710 if wide_layout else 640, 300 if wide_layout else 216, 60)
	_place(hand_scroll, 250 if wide_layout else 8, 830 if wide_layout else 790, 1420 if wide_layout else 524, 220 if wide_layout else 230)
	hand_scroll.custom_minimum_size = Vector2.ZERO

	_place(self_label, 96 if wide_layout else 24, 1010 if wide_layout else 1040, 500, 44)
	self_label.visible = not lobby and not public_layout
	var card_width := 112.0 if wide_layout else 94.0
	var step := 85.0 if wide_layout else 58.0
	var hand_width := maxf(0, hand_buttons.size() - 1) * step + card_width + 40
	hand_row.custom_minimum_size = Vector2(maxf(hand_scroll.size.x - 16, hand_width), 205)
	var left := maxf(20, (hand_scroll.size.x - hand_width) * .5)
	var index := 0
	for button in hand_buttons:
		button.custom_minimum_size = Vector2(112, 168) if wide_layout else Vector2(94, 150)
		button.add_theme_font_size_override("font_size", 52 if wide_layout else 44)
		var delta := index - (hand_buttons.size() - 1) * .5
		button.size = button.custom_minimum_size
		button.position = Vector2(left + index * step, 25 + minf(20, absf(delta) * 5) - (18 if int(button.get_meta("card")) == selected_card else 0))
		button.pivot_offset = button.custom_minimum_size * .5
		button.rotation_degrees = clampf(delta * 3, -12, 12)
		index += 1
		button.scale = Vector2.ONE * (1.06 if int(button.get_meta("card")) == selected_card else 1.0)
		button.z_index = 5 if int(button.get_meta("card")) == selected_card else 0

func _layout_seats() -> void:
	var total := roster.get_child_count()
	var positions := [Vector2(.22,.23),Vector2(.78,.23),Vector2(.88,.54),Vector2(.78,.83),Vector2(.22,.83),Vector2(.12,.54)]
	if total == 2: positions = [Vector2(.22,.28),Vector2(.78,.28)]
	elif total == 3: positions = [Vector2(.22,.23),Vector2(.78,.23),Vector2(.50,.83)]
	elif total == 4: positions = [Vector2(.22,.23),Vector2(.78,.23),Vector2(.78,.83),Vector2(.22,.83)]
	elif total == 5: positions = [Vector2(.22,.23),Vector2(.78,.23),Vector2(.88,.60),Vector2(.50,.84),Vector2(.12,.60)]
	var i := 0
	for node in roster.get_children():
		var pos: Vector2 = positions[mini(i,5)] * logical_size if wide_layout else Vector2(270 if total == 1 else 65 + i * 410.0 / maxi(1,total-1), 165 + absf(i-(total-1)*.5)*18)
		if wide_layout and not public_layout: pos = Vector2(300 + i * 1320.0 / maxi(1,total-1), 250)
		_place(node, pos.x - (130 if wide_layout else 52), pos.y - (85 if wide_layout else 52), 260 if wide_layout else 104, 180 if wide_layout else 115)
		for child in node.get_children():
			if child is TextureRect:
				if child.name.begins_with("Back"):
					_place(child, 150 + int(child.get_meta("back_index")) * 10, 0, 40, 60)
				else: _place(child, 65 if wide_layout else 22, -28 if wide_layout else -10, 130 if wide_layout else 62, 140 if wide_layout else 70)
			elif child is Label:
				var count: bool = child.name == "Count"
				_place(child, 180 if count and wide_layout else 64 if count else 0, 58 if count and wide_layout else 30 if count else 116 if wide_layout else 70, (64 if wide_layout else 40) if count else 260 if wide_layout else 104, 44 if wide_layout else 34)
				child.add_theme_font_size_override("font_size", 28 if wide_layout else 18 if count else 16)
		i += 1

func _build_roster(state: Dictionary) -> void:
	for child in roster.get_children(): roster.remove_child(child); child.queue_free()
	var kinds := ["bear", "fox", "panda", "bunny", "dog", "cat"]
	var index := 0
	for seat in range(snapshot.players.size()):
		if seat == state.display_seat or (not wide_layout and seat == snapshot.seat): continue
		if state.phase != "lobby" and not Cards.contains_number(state.participants, seat): continue
		var node := Control.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		roster.add_child(node)
		_art(node, kinds[seat % 6]).name = "Avatar"
		if state.phase != "lobby" and wide_layout:
			for back_index in range(mini(3,int(state.counts[seat]))):
				var back := _art(node, "back")
				back.name = "Back" + str(back_index)
				back.rotation_degrees = 9 + back_index * 8
				back.set_meta("back_index", back_index)
		var name_label := _label(node, 28)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text = ("▶ " if seat == state.turn and state.phase == "playing" else "") + str(snapshot.players[seat].nickname) + (" · " + _t("OFFLINE") if not state.connected[seat] else "")
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.add_theme_color_override("font_color", INK)
		name_label.add_theme_stylebox_override("normal", _box(Color("fff3d8"), 22, Color("ffd575") if seat == state.turn else Color.TRANSPARENT, 4 if seat == state.turn else 0))
		if state.phase != "lobby":
			var count := _label(node, 28)
			count.name = "Count"
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count.text = str(int(state.counts[seat]))
			count.add_theme_stylebox_override("normal", _box(Color("88583e"), 22))
		index += 1

func _name(seat: int) -> String:
	if seat < 0 or seat >= snapshot.get("players", []).size(): return _t("PLAYER") % [seat + 1]
	var player: Dictionary = snapshot.players[seat]
	return str(player.nickname)

func _allowed(kind: String) -> bool:
	if not platform.get("connected", true) or platform.get("input_paused", false): return false
	for action in legal:
		if action.type == kind: return true
	return false

func render(data: Dictionary) -> void:
	var old_focus := capture_view_state()
	var focused := get_viewport().gui_get_focus_owner()
	var own_focus := focused == null or is_ancestor_of(focused)
	if not snapshot.is_empty() and snapshot.view.round != data.view.round: rematch_intent = -1
	var changed: bool = snapshot.is_empty() or snapshot.get("revision", -1) != data.get("revision", -1)
	snapshot = data.duplicate(true)
	var state: Dictionary = snapshot.view
	if state.hand.size() != 2:
		armed = false
		old_focus.armed = false
	if changed:
		notice.hide()
		selected_card = -1
	legal = Rules.new().describe_actions(state, int(snapshot.seat)).legal_actions
	settings_button.text = _t("SETTINGS")
	exit_button.text = _t("EXIT")
	table_toggle.text = _t("TABLE_MODE")
	color_dialog.title = _t("CHOOSE_COLOR")
	for i in range(color_buttons.size()): color_buttons[i].text = _t(Cards.COLORS[i])
	help_dialog.title = _t("RULES_TITLE")
	help_dialog.dialog_text = _t("RULES_BODY")
	result_dialog.title = _t("RESULT")
	result_dialog.ok_button_text = _t("REVIEW")
	result_rematch.text = _t("REMATCH")
	result_exit.text = _t("EXIT")
	header.text = "UNO · " + _t("ROUND") % [maxi(1, int(state.round))]
	wide_layout = size.x > size.y
	_build_roster(state)
	status.text = _t("WAITING") % [snapshot.players.size() - (1 if state.display_seat == 0 else 0)] if state.phase == "lobby" else _t("FINISHED") if state.phase == "finished" else _t("PAUSED") if state.paused or not platform.get("connected", true) else _t("YOUR_TURN") if state.turn == snapshot.seat else _t("TURN") % [_name(int(state.turn))]
	qr.visible = state.phase == "lobby" and int(snapshot.seat) == 0 and services != null
	if qr.visible:
		var source: Texture2D = services.get_join_qr()
		if source != qr_source:
			qr_source = source
			qr.texture = ImageTexture.create_from_image(source.get_image()) if source != null else null
		qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		qr.visible = qr.texture != null
	top_card.visible = state.top != -1
	if state.top != -1: _paint_card(top_card, int(state.top), true)
	detail.text = _t("LOBBY_HINT") if state.phase == "lobby" else _t("TABLE") % [_t(Cards.COLORS[int(state.color)]), "→" if state.direction == 1 else "←", int(state.hand.size())]
	if state.phase == "lobby" and snapshot.seat == 0 and services != null:
		var invite: Dictionary = services.get_join_info()
		if not invite.is_empty(): detail.text += "\n" + _t("JOIN_ADDRESS") % [invite.address, int(invite.port)]
	if snapshot.seat == state.display_seat and state.phase != "lobby": detail.text = _t("PUBLIC_STATUS") % [_t(Cards.COLORS[int(state.color)]), "→" if state.direction == 1 else "←", state.participants.size(), int(state.deck_count)]
	if state.phase != "lobby": detail.text = _t(Cards.COLORS[int(state.color)]) + "  ·  " + ("→" if state.direction == 1 else "←") + ("  ·  +" + str(state.debt) if int(state.debt) > 0 else "")
	self_label.text = str(snapshot.players[snapshot.seat].nickname) + " · " + _t("CARD_COUNT") % [state.hand.size()]
	actions.visible = state.phase == "lobby" or Cards.contains_number(state.participants, int(snapshot.seat))
	hand_scroll.visible = state.phase != "lobby" and snapshot.seat != state.display_seat
	rules_button.text = _t("RESULT") if state.phase == "finished" else _t("RULES_TITLE")
	table_toggle.visible = state.phase == "lobby" and snapshot.seat == 0
	table_toggle.set_pressed_no_signal(state.display_seat == 0)
	table_toggle.disabled = not _allowed("table_mode")
	result_rematch.visible = Cards.contains_number(state.participants, int(snapshot.seat))
	start_button.visible = state.phase == "lobby" or (state.phase == "finished" and Cards.contains_number(state.participants, int(snapshot.seat)))
	start_button.text = _t("START") if state.phase == "lobby" else _t("VOTED") if Cards.contains_number(state.votes, int(snapshot.seat)) else _t("REMATCH")
	start_button.disabled = not _allowed("start" if state.phase == "lobby" else "rematch") or (state.phase == "finished" and rematch_intent == int(state.round))
	result_rematch.disabled = not _allowed("rematch") or rematch_intent == int(state.round)
	draw_button.visible = state.phase == "playing" and snapshot.seat != state.display_seat
	draw_button.text = _t("PASS") if state.drawn != -1 else _t("DRAW_DEBT") % [int(state.debt)] if int(state.debt) > 0 else _t("DRAW")
	draw_button.disabled = not (_allowed("draw") or _allowed("pass"))
	uno_toggle.visible = state.phase == "playing" and state.hand.size() == 2 and snapshot.seat != state.display_seat
	uno_toggle.text = _t("DECLARE_UNO")
	uno_toggle.set_pressed_no_signal(armed)
	uno_toggle.disabled = state.turn != snapshot.seat or state.hand.size() != 2 or state.paused or not platform.get("connected", true) or platform.get("input_paused", false)
	catch_button.visible = state.phase == "playing" and (_allowed("uno") or _allowed("catch"))
	catch_button.text = _t("CALL_UNO") if state.uno_target == snapshot.seat else _t("CATCH")
	catch_button.disabled = not (_allowed("uno") or _allowed("catch"))
	hand_buttons.clear()
	for child in hand_row.get_children(): hand_row.remove_child(child); child.queue_free()
	for card in state.hand:
		var button := _button(hand_row, "Card_" + str(int(card)), func(): _choose(int(card)))
		button.set_meta("card", int(card))
		button.custom_minimum_size = Vector2(102, 144)
		var playable := false
		for action in legal:
			if action.type == "play" and int(action.card) == int(card): playable = true
		button.disabled = not playable or not platform.get("connected", true) or platform.get("input_paused", false)
		_paint_card(button, int(card), false)
		hand_buttons.append(button)
	if state.phase == "finished": result_dialog.dialog_text = _t("WINNER") % [_name(int(state.winner)), int(state.score)]
	if state.phase == "finished" and int(state.round) != seen_round:
		seen_round = int(state.round)
		result_dialog.dialog_text = _t("WINNER") % [_name(int(state.winner)), int(state.score)]
		result_dialog.popup_centered(Vector2i(mini(620, int(get_viewport_rect().size.x) - 32), 240))
	elif state.phase != "finished": result_dialog.hide()
	_layout()
	if own_focus and not result_dialog.visible and not color_dialog.visible and not menu_panel.visible:
		restore_view_state(old_focus)

func _paint_card(button: Button, card: int, face_up: bool) -> void:
	var info := Cards.info(card)
	var color_key: String = "wild" if info.color == -1 else Cards.COLORS[int(info.color)]
	var symbols := {"draw2": "+2", "draw4": "+4", "wild": "◆", "skip": "⊘", "reverse": "↔"}
	button.text = str(symbols.get(info.rank, info.rank))
	button.tooltip_text = _t(info.rank) if not info.rank.is_valid_int() else info.rank
	button.add_theme_font_size_override("font_size", 76 if face_up else 48)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]: button.add_theme_color_override(key, INK)
	var normal := StyleBoxTexture.new()
	normal.texture = _texture(color_key)
	for key in ["normal", "disabled", "hover", "pressed"]: button.add_theme_stylebox_override(key, normal)
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 16, Color("ffd575"), 5))
	if not face_up:
		button.modulate = Color.WHITE if not button.disabled else Color(.64,.60,.56)
		var corner := Label.new()
		corner.text = button.text
		corner.position = Vector2(12,10)
		corner.add_theme_font_size_override("font_size", 18)
		corner.add_theme_color_override("font_color", INK)
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(corner)

func _choose(card: int) -> void:
	card_focus = card
	if DisplayServer.is_touchscreen_available() and selected_card != card:
		selected_card = card
		_layout()
		return
	selected_card = -1
	if Cards.info(card).color == -1:
		chosen_wild = card
		color_dialog.popup_centered(Vector2i(300, 190))
		color_buttons[0].grab_focus()
	else:
		_submit({"type": "play", "card": card, "uno": armed})
		armed = false

func _submit(action: Dictionary) -> void:
	notice.hide()
	if action.type == "rematch":
		if rematch_intent == int(snapshot.view.round): return
		rematch_intent = int(snapshot.view.round)
	call_deferred("_emit_action", action)

func _emit_action(action: Dictionary) -> void:
	command.emit(action)

func _t(key: String) -> String:
	if messages.is_empty():
		for locale in ["en", "zh"]:
			messages[locale] = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("locale-" + locale + ".json")))
	var locale := TranslationServer.get_locale().get_slice("_", 0)
	return str(messages.get(locale, messages.en).get(key, messages.en.get(key, key)))

func wants_fullscreen() -> bool: return true
func controls_join_qr() -> bool: return true
func set_session_services(value) -> void: services = value
func set_platform_state(value: Dictionary) -> void:
	platform = value.duplicate(true)
	if not platform.get("connected", true): rematch_intent = -1
	if not platform.get("connected", true) or platform.get("input_paused", false): color_dialog.hide()
	if is_node_ready() and not snapshot.is_empty(): render(snapshot)
func on_command_notice(code: String) -> bool:
	if code == "stale_revision" and not snapshot.is_empty() and snapshot.view.phase == "finished" and rematch_intent == int(snapshot.view.round):
		_retry_rematch.call_deferred()
		return true
	rematch_intent = -1
	notice.show()
	notice.text = _t("ERROR_" + code) if messages.en.has("ERROR_" + code) else _t("ERROR")
	return true
func _retry_rematch() -> void:
	if not is_inside_tree(): return
	await get_tree().create_timer(.05).timeout
	if not is_inside_tree() or snapshot.is_empty() or not platform.get("connected", true): return
	if snapshot.view.phase == "finished" and rematch_intent == int(snapshot.view.round) and not snapshot.view.paused and not Cards.contains_number(snapshot.view.votes, int(snapshot.seat)):
		command.emit({"type": "rematch"})
	elif snapshot.view.paused:
		rematch_intent = -1

func focus_default() -> void:
	for button in hand_buttons:
		if not button.disabled: button.grab_focus(); return
	if start_button.visible and not start_button.disabled: start_button.grab_focus()
	elif draw_button.visible and not draw_button.disabled: draw_button.grab_focus()
	else: menu_button.grab_focus()
func capture_view_state() -> Dictionary:
	var focused := get_viewport().gui_get_focus_owner()
	return {"card": focused.get_meta("card", card_focus) if focused != null and is_ancestor_of(focused) else card_focus, "armed": armed, "selected_card": selected_card, "qr_visible": qr.visible}
func restore_view_state(value: Dictionary) -> void:
	armed = bool(value.get("armed", false))
	selected_card = int(value.get("selected_card", -1))
	_layout()
	uno_toggle.set_pressed_no_signal(armed)
	for button in hand_buttons:
		if not button.disabled and int(button.get_meta("card")) == int(value.get("card", -1)):
			button.grab_focus()
			return
	focus_default()

func _input(event: InputEvent) -> void:
	if menu_panel != null and menu_panel.visible and event.is_action_pressed("ui_cancel"):
		menu_panel.hide()
		menu_button.grab_focus()
		get_viewport().set_input_as_handled()
