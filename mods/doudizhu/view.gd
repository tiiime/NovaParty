extends Control
# Dou Dizhu presentation. Reads only the filtered view; never mutates game state.
# Layouts: phone portrait (540x1100), landscape/TV player (1920x1080) and a public table
# for a display seat. Everything is placed on a logical stage that scales to fit.
signal command(action: Dictionary)
signal platform_action(action: String)
const Cards = preload("cards.gd")
const Rules = preload("rules.gd")
# Mod-local tactile palette; this Mod also runs without platform UI resources.
const INK = Color("18254d")
const MUTED = Color("4d6079")
const SKY = Color("304ce0")
const SKY_LIP = Color("2739a2")
const SKY_SOFT = Color("e9edff")
const STAR = Color("ffde46")
const STAR_LIP = Color("d4a524")
const STAR_SOFT = Color("fff3bb")
const PAGE = Color("f8f7f2")
const LINE = Color("e2e6f1")
const LINE_LIP = Color("c8d0e4")
const DANGER = Color("ab3558")
const DANGER_LINE = Color("f0b3c8")
const RED = Color("d23c3c")
const FOCUS = Color("ff8a1c")

var snapshot := {}
var platform := {"connected": true, "input_paused": false}
var services
var messages := {}
var legal: Array = []
var selected: Array = []
var hint_index := -1
var hint_lead := ""
var seen_round := -1
var rematch_intent := -1
var logical_size := Vector2(540, 1100)
var wide := false
var public_layout := false
var focus_card := -1

var stage: Control
var felt: Panel
var header: Label
var chips: Label
var menu_button: Button
var menu_panel: PanelContainer
var status: Label
var notice: Label
var bottom_row: Control
var seats_layer: Control
var my_play: Control
var my_bubble: Label
var hand_row: Control
var hand_buttons: Array = []
var action_row: HBoxContainer
var bid_buttons: Array = []
var pass_button: Button
var hint_button: Button
var play_button: Button
var self_label: Label
var lobby_panel: PanelContainer
var lobby_title: Label
var lobby_players: Label
var lobby_address: Label
var qr: TextureRect
var qr_source: Texture2D
var start_button: Button
var result_panel: PanelContainer
var result_title: Label
var result_body: Label
var result_rematch: Button
var result_review: Button
var result_exit: Button
var rules_panel: PanelContainer
var rules_body: Label
var rules_scroll: ScrollContainer
var rules_close: Button
var menu_rules: Button
var menu_settings: Button
var menu_invite: Button
var menu_reconnect: Button
var menu_exit: Button
var pending_action := false

func _ready() -> void:
	custom_minimum_size = Vector2(280, 360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var page := ColorRect.new()
	page.color = PAGE
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	stage = Control.new()
	stage.name = "Stage"
	add_child(stage)
	felt = Panel.new()
	felt.name = "Felt"
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.add_theme_stylebox_override("panel", _box(SKY_SOFT, 36, LINE_LIP, 2, 6))
	stage.add_child(felt)
	header = _label(stage, 30, INK)
	chips = _label(stage, 20, INK)
	chips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chips.add_theme_stylebox_override("normal", _box(STAR_SOFT, 14, STAR_LIP, 2))
	bottom_row = Control.new()
	bottom_row.name = "Bottom"
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bottom_row)
	seats_layer = Control.new()
	seats_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(seats_layer)
	status = _label(stage, 24, INK)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_stylebox_override("normal", _box(SKY_SOFT, 16, LINE_LIP, 2))
	notice = _label(stage, 20, DANGER)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_stylebox_override("normal", _box(Color("fff0f6"), 14, DANGER_LINE, 2))
	notice.hide()
	my_play = Control.new()
	my_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(my_play)
	my_bubble = _bubble(stage)
	action_row = HBoxContainer.new()
	action_row.name = "Actions"
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 12)
	stage.add_child(action_row)
	for amount in range(4):
		var button := _button(action_row, "Bid%d" % amount, func(): _submit({"type": "bid", "amount": amount}), "secondary" if amount == 0 else "primary")
		bid_buttons.append(button)
	pass_button = _button(action_row, "Pass", func(): _submit({"type": "pass"}), "secondary")
	hint_button = _button(action_row, "Hint", _hint, "secondary")
	play_button = _button(action_row, "Play", _play, "primary")
	hand_row = Control.new()
	hand_row.name = "Hand"
	stage.add_child(hand_row)
	self_label = _label(stage, 20, MUTED)
	menu_button = _button(stage, "Menu", func(): _toggle_menu(not menu_panel.visible), "secondary")
	menu_button.text = "☰"
	menu_button.accessibility_name = _t("MENU")
	_build_menu()
	_build_lobby()
	_build_result()
	_build_rules()
	resized.connect(_layout)
	_layout()

# ---- small builders --------------------------------------------------------------------
func _box(fill: Color, radius: int, border: Color = Color.TRANSPARENT, width: int = 0, lip: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(width)
	box.border_width_bottom = width + lip
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6 + lip
	return box

func _style(button: Button, kind: String) -> void:
	var fill: Color = {"primary": STAR, "secondary": Color.WHITE, "danger": Color.WHITE, "accent": SKY}[kind]
	var lip: Color = {"primary": STAR_LIP, "secondary": LINE_LIP, "danger": DANGER_LINE, "accent": SKY_LIP}[kind]
	var text: Color = {"primary": INK, "secondary": SKY, "danger": DANGER, "accent": Color.WHITE}[kind]
	var outlined := kind in ["secondary", "danger"]
	var stroke := 2 if outlined else 0
	var normal := _box(fill, 16, lip, stroke, 4)
	var hover := _box(fill.lerp(SKY_SOFT if outlined else Color.WHITE, 0.4 if outlined else 0.2), 16, lip, stroke, 4)
	var pressed := _box(fill.lerp(lip, 0.25), 16, lip, stroke, 0)
	pressed.expand_margin_top = -4
	pressed.content_margin_top += 4
	var disabled := _box(Color("e1eaf0"), 16, Color("e1eaf0"), 0, 4)
	var focus := _box(Color.TRANSPARENT, 19, FOCUS, 5)
	focus.draw_center = false
	focus.set_expand_margin_all(3)
	for pair in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["disabled", disabled], ["focus", focus]]:
		button.add_theme_stylebox_override(pair[0], pair[1])
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, text)
	button.add_theme_color_override("font_disabled_color", Color("8294a3"))

func _button(parent: Node, node_name: String, callback: Callable, kind: String = "secondary") -> Button:
	var button := Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_ALL
	_style(button, kind)
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(96, 64)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _bubble(parent: Node) -> Label:
	var bubble := _label(parent, 22, INK)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.autowrap_mode = TextServer.AUTOWRAP_OFF
	bubble.add_theme_stylebox_override("normal", _box(Color.WHITE, 18, LINE_LIP, 2, 4))
	bubble.hide()
	return bubble

func _sheet() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color.WHITE, 24, LINE_LIP, 2, 4))
	panel.get_theme_stylebox("panel").set_content_margin_all(24)
	panel.z_index = 40
	stage.add_child(panel)
	panel.hide()
	return panel

func _build_menu() -> void:
	menu_panel = _sheet()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	menu_panel.add_child(list)
	menu_reconnect = _button(list, "Reconnect", func(): _toggle_menu(false); platform_action.emit("reconnect"))
	menu_reconnect.hide()
	menu_rules = _button(list, "Rules", func(): _toggle_menu(false); _show_rules(), "secondary")
	menu_settings = _button(list, "Settings", func(): _toggle_menu(false); platform_action.emit("settings"), "secondary")
	menu_invite = _button(list, "Invite", func(): _toggle_menu(false); platform_action.emit("invite"), "secondary")
	menu_invite.hide()
	menu_exit = _button(list, "Exit", func(): _toggle_menu(false); platform_action.emit("exit"), "danger")

func _build_lobby() -> void:
	lobby_panel = _sheet()
	lobby_panel.z_index = 10
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	lobby_panel.add_child(box)
	lobby_title = _label(box, 30, INK)
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_players = _label(box, 22, MUTED)
	lobby_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qr = TextureRect.new()
	qr.custom_minimum_size = Vector2(220, 220)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(qr)
	lobby_address = _label(box, 18, MUTED)
	lobby_address.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_button = _button(box, "Start", _start_round, "primary")

func _start_round() -> void:
	if platform.get("can_start", false) and not start_button.disabled: platform_action.emit("start_round")

func _build_result() -> void:
	result_panel = _sheet()
	result_panel.z_index = 50
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	result_panel.add_child(box)
	result_title = _label(box, 32, INK)
	result_body = _label(box, 21, INK)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	result_rematch = _button(row, "Rematch", func(): _submit({"type": "rematch"}), "primary")
	result_review = _button(row, "Review", func(): result_panel.hide(); focus_default(), "secondary")
	result_exit = _button(row, "ResultExit", func(): platform_action.emit("exit"), "danger")
	for button in [result_rematch, result_review, result_exit]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _build_rules() -> void:
	rules_panel = _sheet()
	rules_panel.z_index = 60
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	rules_panel.add_child(box)
	rules_scroll = ScrollContainer.new()
	rules_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rules_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rules_scroll.scroll_deadzone = 12
	rules_scroll.focus_mode = FOCUS_ALL
	rules_scroll.gui_input.connect(_scroll_rules)
	box.add_child(rules_scroll)
	rules_body = _label(rules_scroll, 20, INK)
	rules_body.size_flags_horizontal = SIZE_EXPAND_FILL
	rules_close = _button(box, "RulesClose", func(): rules_panel.hide(); menu_button.grab_focus(), "primary")

func _scroll_rules(event: InputEvent) -> void:
	var step := 54 if event.is_action_pressed("ui_down", true) else -54 if event.is_action_pressed("ui_up", true) else 0
	if step == 0: return
	var previous := rules_scroll.scroll_vertical
	rules_scroll.scroll_vertical += step
	if rules_scroll.scroll_vertical != previous: rules_scroll.accept_event()

# ---- cards -----------------------------------------------------------------------------
func _card(parent: Node, card: int, card_size: Vector2, interactive: bool) -> Button:
	var button := Button.new()
	button.name = "Card_%d" % card
	button.set_meta("card", card)
	button.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	button.size = card_size
	button.custom_minimum_size = card_size
	var chosen := interactive and Cards.contains_number(selected, card)
	var radius := int(card_size.x * 0.14)
	var face := _box(STAR_SOFT if chosen else Color.WHITE, radius, STAR_LIP if chosen else LINE_LIP, 2, 4 if interactive else 2)
	var focus := _box(Color.TRANSPARENT, radius + 3, FOCUS, 4)
	focus.draw_center = false
	focus.set_expand_margin_all(3)
	for key in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: button.add_theme_stylebox_override(key, face)
	button.add_theme_stylebox_override("focus", focus)
	var r := Cards.rank(card)
	var red := Cards.suit(card) in [1, 3] or card == 53
	var color := RED if red else INK
	var corner := Label.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_color_override("font_color", color)
	corner.position = Vector2(card_size.x * 0.1, card_size.y * 0.02)
	if r >= 13:
		corner.text = "大\n王" if card == 53 else "小\n王"
		corner.add_theme_font_size_override("font_size", int(card_size.x * 0.27))
		corner.add_theme_constant_override("line_spacing", -int(card_size.x * 0.08))
	else:
		corner.text = Cards.RANK_NAMES[r] + "\n" + Cards.SUITS[Cards.suit(card)]
		corner.add_theme_font_size_override("font_size", int(card_size.x * (0.27 if r == 7 else 0.32)))
		corner.add_theme_constant_override("line_spacing", -int(card_size.x * 0.1))
	button.add_child(corner)
	if card_size.x >= 80:
		var pip := Label.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.text = "★" if r >= 13 else Cards.SUITS[Cards.suit(card)]
		pip.add_theme_font_size_override("font_size", int(card_size.x * 0.42))
		pip.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.15))
		pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		pip.size = card_size - Vector2(card_size.x * 0.12, card_size.y * 0.1)
		button.add_child(pip)
	parent.add_child(button)
	return button

func _back(parent: Node, card_size: Vector2) -> Panel:
	var back := Panel.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.size = card_size
	back.add_theme_stylebox_override("panel", _box(SKY, int(card_size.x * 0.14), SKY_LIP, 2, 2))
	var star := Label.new()
	star.text = "★"
	star.add_theme_color_override("font_color", STAR)
	star.add_theme_font_size_override("font_size", int(card_size.x * 0.5))
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star.size = card_size
	back.add_child(star)
	parent.add_child(back)
	return back

# Lays out face-up cards overlapped inside `area`, aligned left/center/right.
func _fan(area: Control, cards: Array, card_size: Vector2, align: int) -> void:
	for child in area.get_children(): area.remove_child(child); child.queue_free()
	if cards.is_empty(): return
	var step := minf(card_size.x * 0.42, (area.size.x - card_size.x) / maxf(1, cards.size() - 1))
	var width := step * (cards.size() - 1) + card_size.x
	var left := 0.0 if align == HORIZONTAL_ALIGNMENT_LEFT else area.size.x - width if align == HORIZONTAL_ALIGNMENT_RIGHT else (area.size.x - width) * 0.5
	for i in range(cards.size()):
		var card := _card(area, int(cards[i]), card_size, false)
		card.position = Vector2(left + i * step, 0)

# ---- helpers ---------------------------------------------------------------------------
func _t(key: String) -> String:
	if messages.is_empty():
		for locale in ["en", "zh"]:
			messages[locale] = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("locale-" + locale + ".json")))
	var locale := TranslationServer.get_locale().get_slice("_", 0)
	return str(messages.get(locale, messages.en).get(key, messages.en.get(key, key)))

func _name(seat: int) -> String:
	var players: Array = snapshot.get("players", [])
	if seat < 0 or seat >= players.size(): return _t("PLAYER") % [seat]
	return str(players[seat].nickname)

func _avatar(seat: int) -> Texture2D:
	if services == null or not services.has_method("get_player_profile"): return null
	return services.get_avatar_texture(services.get_player_profile(seat))

func _spectating() -> bool:
	return snapshot.get("role") == "spectator"

func _local_seat() -> int:
	return int(snapshot.get("seat", -1))

func _is_player() -> bool:
	return not snapshot.is_empty() and not _spectating() and Cards.contains_number(snapshot.view.participants, _local_seat())

func _allowed(kind: String) -> bool:
	if pending_action or not platform.get("connected", true) or platform.get("input_paused", false): return false
	for action in legal:
		if action.type == kind: return true
	return false

func _free_lead() -> bool:
	var view: Dictionary = snapshot.view
	return view.lead.is_empty() or int(view.lead_seat) == _local_seat()

func _selection_combo() -> Dictionary:
	return Cards.classify(selected)

func _can_play_selection() -> bool:
	if pending_action: return false
	# Any legal combination may be played; the hint list is only a subset.
	var view: Dictionary = snapshot.view
	if not _my_turn() or view.phase != "playing" or view.paused or not platform.get("connected", true) or platform.get("input_paused", false):
		return false
	var combo := _selection_combo()
	return not combo.is_empty() and (_free_lead() or Cards.beats(combo, snapshot.view.lead))

func _my_turn() -> bool:
	return _is_player() and int(snapshot.view.turn) == _local_seat()

func _combo_name(combo: Dictionary) -> String:
	return _t("TYPE_" + str(combo.get("type", "")).to_upper()) if not combo.is_empty() else ""

func _role(seat: int) -> String:
	var landlord := int(snapshot.view.landlord)
	if landlord < 0: return ""
	return _t("LANDLORD") if seat == landlord else _t("FARMER")

# ---- render ----------------------------------------------------------------------------
func render(data: Dictionary) -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var own_focus := focused == null or is_ancestor_of(focused)
	var previous_focus := capture_view_state()
	var changed: bool = snapshot.is_empty() or snapshot.get("revision", -1) != data.get("revision", -1)
	if not snapshot.is_empty() and snapshot.view.round != data.view.round: rematch_intent = -1
	snapshot = data.duplicate(true)
	var view: Dictionary = snapshot.view
	# Keep a selection across other players' moves, but drop cards that left the hand.
	selected = [] if _spectating() else selected.filter(func(c): return Cards.contains_number(view.get("hand", []), int(c)))
	var lead_key := str(view.lead) + str(view.lead_seat)
	if changed and lead_key != hint_lead:
		hint_index = -1
		hint_lead = lead_key
	if changed:
		pending_action = false
		notice.hide()
	legal = [] if _spectating() else Rules.new().describe_actions(view, _local_seat()).legal_actions
	public_layout = _spectating()
	_texts()
	_layout()
	if own_focus and not result_panel.visible and not rules_panel.visible and not menu_panel.visible:
		restore_view_state(previous_focus)

func _texts() -> void:
	var view: Dictionary = snapshot.view
	header.text = _t("TITLE") + ("  ·  " + _t("ROUND") % [int(view.round)] if int(view.round) > 0 else "") + ("  ·  " + _t("SPECTATING") if _spectating() else "")
	chips.text = _t("STAKES") % [maxi(1, int(view.bid)), int(view.multiplier)]
	chips.visible = view.phase in ["playing", "finished"] or int(view.bid) > 0
	menu_button.accessibility_name = _t("MENU")
	menu_button.tooltip_text = _t("MENU")
	menu_reconnect.text = _t("RECONNECT")
	menu_reconnect.visible = platform.get("can_reconnect", false)
	menu_rules.text = _t("RULES")
	menu_settings.text = _t("SETTINGS")
	menu_invite.text = _t("INVITE")
	menu_invite.visible = platform.get("can_invite", false)
	menu_exit.text = _t("EXIT")
	rules_body.text = _t("RULES_BODY")
	rules_close.text = _t("CLOSE")
	for amount in range(4): bid_buttons[amount].text = _t("NO_BID") if amount == 0 else _t("BID") % [amount]
	pass_button.text = _t("PASS")
	hint_button.text = _t("HINT")
	play_button.text = _t("PLAY")
	start_button.text = _t("START")
	result_review.text = _t("REVIEW")
	result_exit.text = _t("EXIT")
	var paused: bool = view.paused or not platform.get("connected", true)
	status.visible = view.phase != "lobby"
	if view.phase == "lobby":
		var count: int = view.connected.count(true)
		status.text = _t("WAITING") % [count]
	elif paused: status.text = str(platform.get("message", "")) if not str(platform.get("message", "")).is_empty() else _t("PAUSED")
	elif pending_action: status.text = _t("SENDING")
	elif view.phase == "finished": status.text = _t("FINISHED")
	elif view.phase == "bidding": status.text = _t("YOUR_BID") if _my_turn() else _t("BIDDING") % [_name(int(view.turn))]
	elif _my_turn(): status.text = _t("YOUR_LEAD") if _free_lead() else _t("YOUR_TURN") % [_combo_name(view.lead)]
	else: status.text = _t("TURN") % [_name(int(view.turn))]
	# Lobby sheet.
	lobby_panel.visible = view.phase == "lobby"
	var players: Array = []
	for seat in range(snapshot.players.size()):
		if seat < view.connected.size() and view.connected[seat]: players.append(_name(seat))
	lobby_title.text = _t("LOBBY_TITLE") % [players.size()]
	lobby_players.text = "  ·  ".join(players) if not players.is_empty() else _t("LOBBY_EMPTY")
	var host: bool = platform.get("host", false)
	qr.visible = view.phase == "lobby" and host and services != null and services.has_method("get_join_qr")
	if qr.visible:
		var source: Texture2D = services.get_join_qr()
		if source != qr_source:
			qr_source = source
			qr.texture = ImageTexture.create_from_image(source.get_image()) if source != null else null
		qr.visible = qr.texture != null
	lobby_address.text = _t("SENDING") if pending_action else _t("LOBBY_HINT_HOST") if host else _t("LOBBY_HINT_GUEST")
	if host and services != null and services.has_method("get_join_info"):
		var invite: Dictionary = services.get_join_info()
		if not invite.is_empty(): lobby_address.text += "\n" + _t("ADDRESS") % [invite.address]
	if platform.get("password_required", false): lobby_address.text += "\n" + _t("PASSWORD_INVITE")
	start_button.visible = host
	start_button.disabled = not platform.get("can_start", false) or platform.get("input_paused", false)
	# Actions.
	var my_turn: bool = _my_turn() and not paused and not pending_action and not platform.get("input_paused", false)
	for amount in range(4):
		bid_buttons[amount].visible = view.phase == "bidding" and _is_player()
		bid_buttons[amount].disabled = not my_turn or (amount != 0 and amount <= int(view.bid))
	var playing: bool = view.phase == "playing" and _is_player()
	pass_button.visible = playing
	pass_button.disabled = not (my_turn and _allowed("pass"))
	hint_button.visible = playing
	hint_button.disabled = not my_turn
	play_button.visible = playing
	play_button.disabled = not _can_play_selection()
	var me := _local_seat()
	self_label.visible = _is_player() and view.phase != "lobby"
	if self_label.visible:
		self_label.text = _name(me) + ("  ·  " + _role(me) if _role(me) != "" else "") + "  ·  " + _t("CARDS") % [view.hand.size()] + "  ·  " + _t("SCORE") % [int(view.scores.get(str(me), 0))]
	var combo := _selection_combo()
	my_bubble.visible = false
	if _is_player() and view.phase == "bidding" and view.bids.has(str(me)):
		my_bubble.visible = true
		my_bubble.text = _bid_text(int(view.bids[str(me)]))
	elif _is_player() and view.phase == "playing" and str(view.table.get(str(me), "")) == "pass":
		my_bubble.visible = true
		my_bubble.text = _t("PASSED")
	elif not selected.is_empty() and playing:
		my_bubble.visible = true
		my_bubble.text = _combo_name(combo) if not combo.is_empty() else _t("NOT_A_COMBO")
	# Result sheet.
	if view.phase == "finished":
		_result_text()
		if int(view.round) != seen_round:
			seen_round = int(view.round)
			result_panel.show()
			_haptic("confirm")
	else:
		result_panel.hide()
	result_rematch.visible = _is_player()
	var voted := Cards.contains_number(view.votes, me) or rematch_intent == int(view.round)
	result_rematch.text = _t("VOTED") % [view.votes.size()] if voted else _t("REMATCH")
	result_rematch.disabled = voted or not _allowed("rematch")

func _bid_text(amount: int) -> String:
	return _t("NO_BID") if amount == 0 else _t("BID") % [amount]

func _result_text() -> void:
	var view: Dictionary = snapshot.view
	var result: Dictionary = view.result
	var me := _local_seat()
	var landlord := int(view.landlord)
	var won: bool = result.get("landlord_won", false) == (me == landlord)
	result_title.text = (_t("LANDLORD_WINS") if result.get("landlord_won", false) else _t("FARMERS_WIN")) + ("  ·  " + (_t("YOU_WIN") if won else _t("YOU_LOSE")) if _is_player() else "")
	var lines: Array = [_t("RESULT_STAKES") % [int(result.get("bid", 1)), int(result.get("multiplier", 1)), int(result.get("bombs", 0))]]
	if result.get("spring", false): lines.append(_t("SPRING") if result.get("landlord_won", false) else _t("ANTI_SPRING"))
	for seat in view.participants:
		var delta := int(result.get("deltas", {}).get(str(int(seat)), 0))
		lines.append("%s%s  %s%d  ·  %s" % [_name(int(seat)), " (" + _t("LANDLORD") + ")" if int(seat) == landlord else "", "+" if delta >= 0 else "", delta, _t("TOTAL") % [int(view.scores.get(str(int(seat)), 0))]])
	result_body.text = "\n".join(lines)

# ---- layout ----------------------------------------------------------------------------
func _place(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)

func _layout() -> void:
	if stage == null or not is_node_ready(): return
	wide = size.x > size.y
	logical_size = Vector2(1920, 1080) if wide else Vector2(540, 1100)
	var factor := minf(size.x / logical_size.x, size.y / logical_size.y) if size.x > 0 and size.y > 0 else 1.0
	stage.scale = Vector2.ONE * factor
	stage.size = logical_size
	stage.position = (size - logical_size * factor) * 0.5
	var big := wide
	_place(header, 48 if big else 20, 28 if big else 16, 900 if big else 380, 50)
	header.add_theme_font_size_override("font_size", 36 if big else 26)
	_place(menu_button, logical_size.x - (128 if big else 84), 24 if big else 12, 80 if big else 64, 60)
	_place(menu_panel, logical_size.x - (380 if big else 300), 96 if big else 80, 330 if big else 280, menu_panel.get_combined_minimum_size().y)
	if menu_panel.visible: _link_menu_focus()
	_place(chips, 48 if big else 20, 84 if big else 60, 300 if big else 200, 40)
	_place(felt, 24 if big else 8, 150 if big else 140, logical_size.x - (48 if big else 16), (610 if big else 600))
	_place(status, (logical_size.x - (720 if big else 480)) * 0.5, 430 if big else 470, 720 if big else 480, 60)
	status.add_theme_font_size_override("font_size", 28 if big else 22)
	_place(notice, (logical_size.x - (720 if big else 480)) * 0.5, 360 if big else 405, 720 if big else 480, 56)
	_place(lobby_panel, (logical_size.x - (640 if big else 480)) * 0.5, 160 if big else 150, 640 if big else 480, 700 if big else 760)
	var result_width := 760 if big else 500
	_place(result_panel, (logical_size.x - result_width) * 0.5, 220 if big else 240, result_width, 0)
	var rules_width := 900 if big else 500
	_place(rules_panel, (logical_size.x - rules_width) * 0.5, 100, rules_width, logical_size.y - 200)
	if snapshot.is_empty(): return
	var view: Dictionary = snapshot.view
	var in_game: bool = view.phase != "lobby"
	# Bottom cards: face down until a landlord is known.
	var bottom_x := (logical_size.x - 300) * 0.5 if big else 185.0 if public_layout else 236.0
	var bottom_y := 24 if big else 66 if public_layout else 60
	_place(bottom_row, bottom_x, bottom_y, 300 if big else 170, 120 if big else 76)
	for child in bottom_row.get_children(): bottom_row.remove_child(child); child.queue_free()
	bottom_row.visible = in_game
	var bottom_size := Vector2(84, 118) if big else Vector2(50, 70)
	for i in range(3):
		var node: Control
		if view.bottom.size() == 3: node = _card(bottom_row, int(view.bottom[i]), bottom_size, false)
		else: node = _back(bottom_row, bottom_size)
		node.position = Vector2(i * (bottom_size.x + 10), 0)
	_layout_seats(view, big, in_game)
	# My table play and hand.
	var me := _local_seat()
	_place(my_play, (logical_size.x - (900 if big else 480)) * 0.5, 520 if big else 545, 900 if big else 480, 130 if big else 92)
	var mine = view.table.get(str(me), [])
	_fan(my_play, mine if mine is Array else [], Vector2(90, 126) if big else Vector2(64, 90), HORIZONTAL_ALIGNMENT_CENTER)
	my_play.visible = _is_player() and in_game
	_place(my_bubble, (logical_size.x - 220) * 0.5, 580 if big else 560, 220, 52)
	_place(action_row, (logical_size.x - (1000 if big else 520)) * 0.5, 680 if big else 660, 1000 if big else 520, 64)
	for button in action_row.get_children():
		button.custom_minimum_size = Vector2(200 if big else 112, 64)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 26 if big else 22)
	_layout_hand(view, big)
	_place(self_label, 48 if big else 20, logical_size.y - (56 if big else 50), logical_size.x - 96, 40)
	_link_focus()

func _layout_seats(view: Dictionary, big: bool, in_game: bool) -> void:
	for child in seats_layer.get_children(): seats_layer.remove_child(child); child.queue_free()
	seats_layer.visible = in_game
	if not in_game: return
	var me := _local_seat()
	var order: Array = view.participants.duplicate()
	var slots: Array = []
	if public_layout or not Cards.contains_number(order, me):
		for i in range(order.size()):
			var panel := Rect2(120 + i * 600, 180, 480, 230) if big else Rect2(20 + i * 170, 175, 158, 174)
			var plays := Rect2(60 + i * 600, 540, 600, 150) if big else Rect2(panel.position.x, 365, 158, 90)
			slots.append({"seat": int(order[i]), "rect": panel, "align": HORIZONTAL_ALIGNMENT_CENTER, "plays": plays})
	else:
		var index: int = Cards.index_number(order, me)
		var right := int(order[(index + 1) % 3])
		var left := int(order[(index + 2) % 3])
		if big:
			slots = [{"seat": left, "rect": Rect2(48, 160, 300, 220), "align": HORIZONTAL_ALIGNMENT_LEFT, "plays": Rect2(370, 200, 520, 140)},
				{"seat": right, "rect": Rect2(1572, 160, 300, 220), "align": HORIZONTAL_ALIGNMENT_RIGHT, "plays": Rect2(1030, 200, 520, 140)}]
		else:
			slots = [{"seat": left, "rect": Rect2(16, 150, 160, 200), "align": HORIZONTAL_ALIGNMENT_LEFT, "plays": Rect2(16, 360, 250, 90)},
				{"seat": right, "rect": Rect2(364, 150, 160, 200), "align": HORIZONTAL_ALIGNMENT_RIGHT, "plays": Rect2(274, 360, 250, 90)}]
	for slot in slots:
		_seat(slot, view, big)

func _seat(slot: Dictionary, view: Dictionary, big: bool) -> void:
	var seat: int = slot.seat
	var rect: Rect2 = slot.rect
	var turn: bool = int(view.turn) == seat and view.phase in ["bidding", "playing"]
	var panel := Panel.new()
	panel.name = "Seat%d" % seat
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(STAR_SOFT if turn else Color.WHITE, 20, STAR_LIP if turn else LINE_LIP, 3 if turn else 2, 4))
	seats_layer.add_child(panel)
	_place(panel, rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	var side := 96.0 if big else 72.0
	var texture := _avatar(seat)
	if texture == null:
		# Without platform profile services, show the name's first letter in a coin.
		var coin := _label(panel, int(side * 0.45), Color.WHITE)
		coin.autowrap_mode = TextServer.AUTOWRAP_OFF
		coin.text = _name(seat).left(1)
		coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		coin.add_theme_stylebox_override("normal", _box(SKY, int(side / 2)))
		_place(coin, (rect.size.x - side) * 0.5, 10, side, side)
	var avatar := TextureRect.new()
	avatar.texture = texture
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(avatar)
	_place(avatar, (rect.size.x - side) * 0.5, 10, side, side)
	var name_label := _label(panel, 24 if big else 18, INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text = ("▶ " if turn else "") + _name(seat) + ("" if view.connected[seat] else "  ·  " + _t("OFFLINE"))
	_place(name_label, 8, side + 14, rect.size.x - 16, 34)
	var info := _label(panel, 20 if big else 16, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var role := _role(seat)
	info.text = (role + "  ·  " if role != "" else "") + _t("CARDS") % [int(view.counts[seat])]
	_place(info, 8, side + 48, rect.size.x - 16, 30)
	if role != "":
		var badge := _label(panel, 18 if big else 14, INK if seat == int(view.landlord) else Color.WHITE)
		badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		badge.text = "★" if seat == int(view.landlord) else "●"
		badge.add_theme_stylebox_override("normal", _box(STAR if seat == int(view.landlord) else SKY, 12))
		_place(badge, 8, 8, 40, 30)
	# What this seat did on the table: cards, "pass", bid, or revealed hand after the round.
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seats_layer.add_child(area)
	var plays: Rect2 = slot.plays
	_place(area, plays.position.x, plays.position.y, plays.size.x, plays.size.y)
	var card_size := Vector2(90, 126) if big else Vector2(56, 80)
	var shown = view.table.get(str(seat), [])
	if view.phase == "finished" and _is_player() and seat != _local_seat(): shown = view.revealed[seat]
	if shown is Array and not shown.is_empty():
		_fan(area, shown, card_size if view.phase != "finished" else card_size * 0.8, slot.align)
	else:
		var text := ""
		if view.phase == "bidding" and view.bids.has(str(seat)): text = _bid_text(int(view.bids[str(seat)]))
		elif view.phase == "playing" and str(shown) == "pass": text = _t("PASSED")
		if text != "":
			var bubble := _bubble(area)
			bubble.show()
			bubble.text = text
			_place(bubble, 0 if slot.align == HORIZONTAL_ALIGNMENT_LEFT else plays.size.x - 160 if slot.align == HORIZONTAL_ALIGNMENT_RIGHT else (plays.size.x - 160) * 0.5, 10, 160, 52)

func _layout_hand(view: Dictionary, big: bool) -> void:
	for child in hand_row.get_children(): hand_row.remove_child(child); child.queue_free()
	hand_buttons.clear()
	var visible_hand: bool = _is_player() and view.phase != "lobby" and not public_layout
	hand_row.visible = visible_hand
	if not visible_hand: return
	var card_size := Vector2(120, 168) if big else Vector2(68, 96)
	var area := Rect2(80, 790, logical_size.x - 160, 230) if big else Rect2(10, 780, 520, 200)
	_place(hand_row, area.position.x, area.position.y, area.size.x, area.size.y)
	var cards: Array = view.hand
	const EDGE := 8.0
	var step := minf(card_size.x * 0.62, (area.size.x - card_size.x - 2 * EDGE) / maxf(1, cards.size() - 1))
	var width := step * (cards.size() - 1) + card_size.x
	var left := (area.size.x - width) * 0.5
	var can_act: bool = not pending_action and platform.get("connected", true) and not platform.get("input_paused", false)
	for i in range(cards.size()):
		var card := int(cards[i])
		var button := _card(hand_row, card, card_size, true)
		button.disabled = not can_act or view.phase == "finished"
		var chosen := Cards.contains_number(selected, card)
		button.position = Vector2(left + i * step, 36 - (28 if chosen else 0))
		button.z_index = 1 if chosen else 0
		button.pressed.connect(func(): _toggle(card))
		button.focus_entered.connect(func(): focus_card = card; button.z_index = 2)
		button.focus_exited.connect(func(): button.z_index = 1 if chosen else 0)
		hand_buttons.append(button)

# Explicit remote navigation: cards form one row; up goes to the action row.
func _link_focus() -> void:
	var actions: Array = action_row.get_children().filter(func(b): return b.visible and not b.disabled)
	for i in range(hand_buttons.size()):
		var button: Button = hand_buttons[i]
		button.focus_neighbor_left = button.get_path_to(hand_buttons[i - 1] if i > 0 else button)
		button.focus_neighbor_right = button.get_path_to(hand_buttons[i + 1] if i + 1 < hand_buttons.size() else button)
		if not actions.is_empty(): button.focus_neighbor_top = button.get_path_to(actions[mini(actions.size() - 1, i * actions.size() / maxi(1, hand_buttons.size()))])
		button.focus_neighbor_bottom = button.get_path_to(button)
	for button in actions:
		if not hand_buttons.is_empty(): button.focus_neighbor_bottom = button.get_path_to(hand_buttons[hand_buttons.size() / 2])
		button.focus_neighbor_top = button.get_path_to(menu_button)

# ---- input -----------------------------------------------------------------------------
func _haptic(kind: String) -> void:
	# Unknown platform actions are ignored by older hosts.
	platform_action.emit("haptic:" + kind)

func _toggle(card: int) -> void:
	focus_card = card
	var index := Cards.index_number(selected, card)
	if index >= 0: selected.remove_at(index)
	else: selected.append(card)
	_haptic("tap")
	_refresh_selection()

func _refresh_selection() -> void:
	_texts()
	_layout_hand(snapshot.view, wide)
	_link_focus()
	for button in hand_buttons:
		if int(button.get_meta("card")) == focus_card: button.grab_focus()

func _hint() -> void:
	var view: Dictionary = snapshot.view
	var options: Array = Cards.hints(view.hand, {} if _free_lead() else view.lead)
	if options.is_empty():
		notice.text = _t("NO_ANSWER")
		notice.show()
		selected = []
		_refresh_selection()
		pass_button.grab_focus()
		return
	hint_index = (hint_index + 1) % options.size()
	selected = options[hint_index].duplicate()
	_haptic("select")
	_refresh_selection()
	if not play_button.disabled: play_button.grab_focus()

func _play() -> void:
	if not _can_play_selection(): return
	_submit({"type": "play", "cards": Cards.sort_hand(selected)})

func _submit(action: Dictionary) -> void:
	if not _is_player() or pending_action or not platform.get("connected", true) or platform.get("input_paused", false): return
	notice.hide()
	if action.type == "rematch":
		if rematch_intent == int(snapshot.view.round): return
		rematch_intent = int(snapshot.view.round)
	pending_action = true
	_haptic("confirm" if action.type in ["play", "start", "rematch"] else "select")
	call_deferred("_emit", action)

func _emit(action: Dictionary) -> void:
	if not is_inside_tree(): return
	if not platform.get("connected", true) or platform.get("input_paused", false):
		pending_action = false
		return
	_texts()
	for button in hand_buttons: button.disabled = true
	command.emit(action)

func _toggle_menu(open: bool) -> void:
	menu_panel.visible = open
	if not open:
		menu_button.grab_focus()
		return
	_link_menu_focus()

func _link_menu_focus() -> void:
	var entries: Array = menu_panel.get_child(0).get_children().filter(func(button): return button.visible)
	for i in range(entries.size()):
		var b: Button = entries[i]
		b.focus_previous = b.get_path_to(entries[i - 1])
		b.focus_next = b.get_path_to(entries[(i + 1) % entries.size()])
		b.focus_neighbor_top = b.focus_previous
		b.focus_neighbor_bottom = b.focus_next
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.focus_neighbor_left
	if not platform.get("input_paused", false) and get_viewport().gui_get_focus_owner() not in entries:
		entries[0].grab_focus()

func _show_rules() -> void:
	rules_panel.show()
	rules_scroll.scroll_vertical = 0
	rules_scroll.grab_focus()

# ---- platform contract -------------------------------------------------------------------
func wants_fullscreen() -> bool: return true
func controls_join_qr() -> bool: return true
func set_session_services(value) -> void: services = value

func set_platform_state(value: Dictionary) -> void:
	platform = value.duplicate(true)
	if not platform.get("connected", true):
		rematch_intent = -1
		pending_action = false
	if is_node_ready() and not snapshot.is_empty(): render(snapshot)

func on_command_notice(code: String) -> bool:
	pending_action = false
	if code == "stale_revision" and not snapshot.is_empty() and snapshot.view.phase == "finished" and rematch_intent == int(snapshot.view.round):
		_retry_rematch.call_deferred()
		return true
	rematch_intent = -1
	if not snapshot.is_empty(): render(snapshot)
	var key := "ERROR_" + code
	notice.text = _t(key) if _t(key) != key else _t("ERROR")
	notice.show()
	_haptic("warn")
	return true

func _retry_rematch() -> void:
	if not is_inside_tree(): return
	await get_tree().create_timer(0.05).timeout
	if not is_inside_tree() or snapshot.is_empty() or not platform.get("connected", true): return
	if snapshot.view.phase == "finished" and rematch_intent == int(snapshot.view.round) and not snapshot.view.paused and _is_player() and not Cards.contains_number(snapshot.view.votes, _local_seat()):
		command.emit({"type": "rematch"})

func handle_platform_back() -> bool:
	for panel in [rules_panel, menu_panel]:
		if panel.visible:
			panel.hide()
			menu_button.grab_focus()
			return true
	if result_panel.visible:
		result_panel.hide()
		focus_default()
		return true
	if not selected.is_empty():
		selected = []
		_refresh_selection()
		return true
	return false

func restore_platform_focus(_kind: String) -> void:
	menu_button.grab_focus()

func focus_default() -> void:
	if snapshot.is_empty(): return
	var view: Dictionary = snapshot.view
	if result_panel.visible:
		(result_rematch if not result_rematch.disabled and result_rematch.visible else result_review).grab_focus()
	elif view.phase == "lobby":
		if start_button.visible and not start_button.disabled: start_button.grab_focus()
		else: menu_button.grab_focus()
	elif view.phase == "bidding" and _my_turn():
		# Lowest raise still available, else "no bid".
		var raise := int(view.bid) + 1
		(bid_buttons[raise] if raise <= 3 and not bid_buttons[raise].disabled else bid_buttons[0]).grab_focus()
	elif not hand_buttons.is_empty() and _my_turn():
		hand_buttons[hand_buttons.size() - 1].grab_focus()
	else:
		menu_button.grab_focus()

func capture_view_state() -> Dictionary:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_name := ""
	if focused != null and is_ancestor_of(focused): focus_name = str(focused.name)
	return {"selected": selected.duplicate(), "focus": focus_name, "card": focus_card, "hint_index": hint_index, "qr_visible": qr != null and qr.visible and lobby_panel.visible}

func restore_view_state(value: Dictionary) -> void:
	if value.has("selected") and not snapshot.is_empty():
		selected = value.selected.filter(func(c): return Cards.contains_number(snapshot.view.get("hand", []), int(c)))
	hint_index = int(value.get("hint_index", hint_index))
	if not snapshot.is_empty():
		_texts()
		_layout()
	var focus_name := str(value.get("focus", ""))
	if focus_name.begins_with("Card_"):
		for button in hand_buttons:
			if button.name == focus_name and not button.disabled:
				button.grab_focus()
				return
	elif focus_name != "":
		var target := stage.find_child(focus_name, true, false)
		if target is Control and target.is_visible_in_tree() and not (target is BaseButton and target.disabled):
			target.grab_focus()
			return
	focus_default()
