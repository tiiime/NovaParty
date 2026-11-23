extends GridContainer
signal selected(index: int)
signal add_requested
signal navigation_changed
const Style = preload("res://app/ui/theme/party_theme.gd")
const Icons = preload("res://app/ui/theme/party_icons.gd")
const T = Style.T
const BADGE_SIZE := 28
var cards: Array[Button] = []
var entries: Array = []
var selection := 0
var last_focus := 0
var launch_target: Button
var covers := {}

func _ready() -> void:
	add_theme_constant_override("h_separation", 16)
	add_theme_constant_override("v_separation", 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_adapt)

func populate(items: Array, current: int) -> void:
	entries = items
	selection = current
	for child in get_children():
		remove_child(child)
		child.queue_free()
	cards.clear()
	for index in range(items.size() + 1):
		var adding := index == items.size()
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 246)
		card.toggle_mode = not adding
		card.accessibility_name = tr("ADD_GAME") if adding else str(items[index].name)
		card.set_meta("haptic", "tap" if adding else "select")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.clip_contents = false # Focus halo must extend beyond the rounded card.
		card.tooltip_text = tr("ADD_GAME") if adding else str(items[index].name)
		card.pressed.connect(func():
			if adding:
				add_requested.emit()
			else:
				select_game(index)
				selected.emit(index)
		)
		card.focus_entered.connect(func():
			last_focus = index
			navigation_changed.emit()
		)
		add_child(card)
		cards.append(card)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top"]:
			margin.add_theme_constant_override("margin_" + edge, 14)
		margin.add_theme_constant_override("margin_bottom", 14 + T.LIP)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(margin)
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 8)
		margin.add_child(body)
		if adding:
			var plus := TextureRect.new()
			plus.texture = Icons.get_icon("plus", T.SKY, 64)
			plus.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			plus.size_flags_vertical = Control.SIZE_EXPAND_FILL
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.add_child(plus)
		else:
			var cover := TextureRect.new()
			cover.texture = _cover(items[index])
			cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.add_child(cover)
		var title := Label.new()
		title.text = tr("ADD_GAME") if adding else str(items[index].name)
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		Style.label(title, T.FONT_SIZE_SECTION, T.FONT_WEIGHT_TITLE)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(title)
		var detail := Label.new()
		detail.name = "Detail"
		detail.text = tr("ADD_GAME_HINT") if adding else _player_count(items[index])
		detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Style.label(detail, T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL, T.MUTED)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(detail)
		card.set_meta("detail", detail)
		if not adding: _add_selection_badge(card)
	select_game(current)
	_adapt()

func _add_selection_badge(card: Button) -> void:
	var badge := Panel.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", Style.pill(T.SKY, BADGE_SIZE / 2))
	card.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -12 - BADGE_SIZE
	badge.offset_top = 12
	badge.offset_right = -12
	badge.offset_bottom = 12 + BADGE_SIZE
	var checkmark := TextureRect.new()
	checkmark.texture = Icons.get_icon("check", T.WHITE, 18)
	checkmark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	checkmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(checkmark)
	checkmark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.set_meta("selection_badge", badge)

func _player_count(info: Dictionary) -> String:
	var players: Dictionary = info.get("players", {})
	var lo := int(players.get("min", 2))
	var hi := int(players.get("max", lo))
	return tr("GAME_PLAYERS") % [lo] if lo == hi else tr("GAME_PLAYER_RANGE") % [lo, hi]

func _cover(info: Dictionary) -> Texture2D:
	var path := str(info.get("cover_path", ""))
	if covers.has(path): return covers[path]
	if not path.is_empty() and FileAccess.file_exists(path + ".import"):
		var texture = load(path)
		if texture is Texture2D:
			return texture
	if not path.is_empty() and FileAccess.file_exists(path):
		var picture := Image.new()
		var error: Error = picture.load_svg_from_string(FileAccess.get_file_as_string(path)) if path.get_extension() == "svg" or path.ends_with(".svg.txt") else picture.load(path)
		if error == OK:
			var texture := ImageTexture.create_from_image(picture)
			covers[path] = texture
			return texture
	return load("res://assets/ui/cover-" + (str(info.id) if info.id in ["gomoku", "hidden_cards"] else "default") + ".svg")

func select_game(index: int) -> void:
	selection = index
	for i in range(cards.size()):
		var active := i == selection and i < entries.size()
		Style.card(cards[i], active)
		if i < entries.size():
			cards[i].set_pressed_no_signal(active)
			var badge: Control = cards[i].get_meta("selection_badge")
			badge.visible = active
			var detail: Label = cards[i].get_meta("detail")
			detail.text = tr("GAME_PICKED_SHORT") if active else _player_count(entries[i])
			detail.add_theme_color_override("font_color", T.SKY if active else T.MUTED)

func _adapt() -> void:
	columns = 2 if size.x < 760 else 4 if size.x >= 1400 else 3
	_link_navigation()
	navigation_changed.emit()

func set_launch_target(target: Button) -> void:
	launch_target = target
	_link_navigation()

func return_focus_card() -> Button:
	return cards[clampi(last_focus, 0, cards.size() - 1)] if not cards.is_empty() else null

func _link_navigation() -> void:
	for i in range(cards.size()):
		var card := cards[i]
		if not is_instance_valid(launch_target):
			for direction in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				card.set_focus_neighbor(direction, NodePath(""))
			card.focus_next = NodePath("")
			card.focus_previous = NodePath("")
			continue
		var left := cards[i - 1] if i % columns > 0 else card
		var right := cards[i + 1] if i % columns < columns - 1 and i + 1 < cards.size() else card
		var above := cards[i - columns] if i >= columns else card
		var below: Control = cards[i + columns] if i + columns < cards.size() else launch_target
		card.focus_neighbor_left = card.get_path_to(left)
		card.focus_neighbor_right = card.get_path_to(right)
		card.focus_neighbor_top = card.get_path_to(above)
		card.focus_neighbor_bottom = card.get_path_to(below)
		card.focus_next = card.get_path_to(cards[i + 1] if i + 1 < cards.size() else launch_target)
		card.focus_previous = card.get_path_to(cards[i - 1] if i > 0 else launch_target)

func focus_selected() -> void:
	if selection >= 0 and selection < cards.size():
		cards[selection].grab_focus()
