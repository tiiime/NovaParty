extends VBoxContainer
signal command(action: Dictionary)
const INK := Color("18254d")
const BLUE := Color("304ce0")
const SOFT := Color("e9edff")
const GOLD := Color("ffde46")
var snapshot := {}
var platform := {"connected": true, "input_paused": false, "message": ""}
var pending := -1
var note := ""
var heading: Label
var cards: HBoxContainer
var history_box: VBoxContainer
var localized_text := {}

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	heading = _label(self, 22, SOFT)
	cards = HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", 12)
	add_child(cards)
	history_box = VBoxContainer.new()
	history_box.add_theme_constant_override("separation", 8)
	add_child(history_box)

func render(data: Dictionary) -> void:
	var before: Dictionary = snapshot.get("view", {})
	var state: Dictionary = data.view
	if before.get("round") != state.round or state.chosen != -1:
		pending = -1
		note = ""
	snapshot = data
	_refresh()

func _refresh() -> void:
	if snapshot.is_empty(): return
	var focused := get_viewport().gui_get_focus_owner()
	var owned_focus := focused != null and cards.is_ancestor_of(focused)
	var focused_card: int = int(focused.get_meta("card", -1)) if owned_focus else -1
	var state: Dictionary = snapshot.view
	var seat := int(snapshot.seat)
	var online: bool = snapshot.players.size() == 2 and snapshot.players[1 - seat].get("connected", true)
	var phase := _t("CHOOSE_CARD")
	if state.finished:
		phase = _t("DRAW") if state.scores[seat] == state.scores[1 - seat] else _t("WIN") if state.scores[seat] > state.scores[1 - seat] else _t("LOSS")
	elif not platform.connected:
		phase = str(platform.message) if not str(platform.message).is_empty() else _t("PAUSED")
	elif not online:
		phase = _t("WAIT_FRIEND")
	elif pending != -1:
		phase = _t("SENDING")
	elif state.chosen != -1:
		phase = _t("LOCKED") % _card(int(state.chosen))
	heading.text = _t("MATCH_STATUS") % [mini(int(state.round) + 1, 3), int(state.scores[seat]), int(state.scores[1 - seat]), phase]
	if not note.is_empty(): heading.text += "\n" + note
	var can_choose: bool = online and platform.connected and not platform.input_paused and not state.finished and state.chosen == -1 and pending == -1
	# Keep existing controls on presence, locale and submission updates.
	var existing := []
	for button in cards.get_children(): existing.append(int(button.get_meta("card")))
	var hand := []
	for value in state.hand: hand.append(int(value))
	if existing != hand:
		_clear(cards)
		for card in hand: _add_card(card)
	var target: Button
	for button in cards.get_children():
		var card: int = button.get_meta("card")
		button.add_theme_stylebox_override("disabled", _box(GOLD if card in [int(state.chosen), pending] else SOFT, Color("c8d0e4"), 0))
		button.disabled = not can_choose
		if can_choose and (target == null or card == focused_card): target = button
	if target != null and (owned_focus or focused == null): target.grab_focus()
	_clear(history_box)
	for values in state.history:
		_label(history_box, 18, Color.WHITE).text = _t("REVEAL") % [_card(int(values[seat])), _card(int(values[1 - seat]))]

@warning_ignore("integer_division")
func _add_card(card: int) -> void:
	var button := Button.new()
	button.name = "Card_" + str(card)
	button.text = _card(card)
	button.set_meta("card", card)
	button.custom_minimum_size.y = 116
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 36)
	var suit := card / 13
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(key, Color("ab3558") if suit in [1, 3] else INK)
	button.add_theme_stylebox_override("normal", _box(Color.WHITE, Color("c8d0e4"), 4))
	button.add_theme_stylebox_override("hover", _box(SOFT, BLUE, 4))
	button.add_theme_stylebox_override("pressed", _box(GOLD, Color("d4a524"), 0))
	var ring := _box(Color.TRANSPARENT, Color("ff8a1c"), 0)
	ring.draw_center = false
	ring.set_border_width_all(4)
	ring.set_expand_margin_all(3)
	button.add_theme_stylebox_override("focus", ring)
	button.pressed.connect(func(): _choose_card(card))
	cards.add_child(button)

func _label(parent: Node, extent: int, fill: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", extent)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_stylebox_override("normal", _box(fill, Color("c8d0e4"), 0))
	parent.add_child(label)
	return label

func _box(fill: Color, edge: Color, lip: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.border_width_bottom += lip
	box.set_corner_radius_all(18)
	box.set_content_margin_all(12)
	return box

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _card(card: int) -> String:
	return ["♠", "♥", "♣", "♦"][card / 13] + ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"][card % 13]

func _choose_card(card: int) -> void:
	if pending != -1 or not platform.connected or platform.input_paused: return
	pending = card
	note = ""
	_submit_card.call_deferred(card)

func _submit_card(card: int) -> void:
	if not is_inside_tree(): return
	if not platform.connected or platform.input_paused:
		pending = -1
		_refresh()
		return
	_refresh()
	command.emit({"type": "choose", "card": card})

func set_platform_state(state: Dictionary) -> void:
	platform.merge(state, true)
	if not platform.connected: pending = -1
	_refresh()

func on_command_notice(code: String) -> bool:
	if pending == -1 or not code in ["stale_revision", "already_chosen", "card_not_owned", "waiting_for_players", "invalid_action"]: return false
	pending = -1
	note = _t("RETRY")
	_refresh()
	return true

func focus_default() -> void:
	for button in cards.get_children():
		if not button.disabled and button.focus_mode != FOCUS_NONE: button.grab_focus(); return

func capture_view_state() -> Dictionary:
	var focused := get_viewport().gui_get_focus_owner()
	return {"focused_card": focused.get_meta("card", -1) if focused != null and cards.is_ancestor_of(focused) else -1}

func restore_view_state(state: Dictionary) -> void:
	for button in cards.get_children():
		if not button.disabled and button.get_meta("card", -1) == int(state.get("focused_card", -1)):
			button.grab_focus()
			return

func _t(key: String) -> String:
	if localized_text.is_empty():
		var root: String = get_script().resource_path.get_base_dir()
		for language in ["en", "zh"]:
			var data = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("locale-" + language + ".json")))
			localized_text[language] = data if data is Dictionary else {}
	var locale := TranslationServer.get_locale().get_slice("_", 0)
	var messages: Dictionary = localized_text.get(locale, localized_text.en)
	return str(messages.get(key, localized_text.en.get(key, key)))
