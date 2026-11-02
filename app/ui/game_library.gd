extends GridContainer
signal selected(index: int)
signal add_requested
signal navigation_changed
const Style = preload("res://app/ui/party_theme.gd")
var cards: Array[Button] = []
var entries: Array = []
var selection := 0
var last_focus := 0
var launch_target: Button

func _ready() -> void:
	add_theme_constant_override("h_separation", 18)
	add_theme_constant_override("v_separation", 18)
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
		card.custom_minimum_size = Vector2(0, 248)
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
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 14)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(margin)
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 8)
		margin.add_child(body)
		if adding:
			var plus := Label.new()
			plus.text = "+"
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.size_flags_vertical = Control.SIZE_EXPAND_FILL
			plus.add_theme_font_size_override("font_size", 70)
			plus.add_theme_color_override("font_color", Style.BLUE)
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
		title.add_theme_font_size_override("font_size", 23)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(title)
		var detail := Label.new()
		detail.name = "Detail"
		detail.text = "ADD_GAME_HINT" if adding else "GAME_TWO_PLAYERS"
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.add_theme_font_size_override("font_size", 17)
		detail.add_theme_color_override("font_color", Color("506786"))
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(detail)
		card.set_meta("detail", detail)
		Style.feedback(card, true)
	select_game(current)
	_adapt()

func _cover(info: Dictionary) -> Texture2D:
	var path: String = info.get("cover_path", "")
	if not path.is_empty() and FileAccess.file_exists(path + ".import"):
		var texture = load(path)
		if texture is Texture2D:
			return texture
	if not path.is_empty() and FileAccess.file_exists(path):
		var picture := Image.new()
		var error: Error = picture.load_svg_from_string(FileAccess.get_file_as_string(path)) if path.get_extension() == "svg" or path.ends_with(".svg.txt") else picture.load(path)
		if error == OK:
			return ImageTexture.create_from_image(picture)
	return load("res://assets/ui/cover-" + (str(info.id) if info.id in ["gomoku", "hidden_cards"] else "default") + ".svg")

func select_game(index: int) -> void:
	selection = index
	for i in range(cards.size()):
		var active := i == selection and i < entries.size()
		var normal := Style.pill(Color("e1efff") if active else Color.WHITE, 24, Style.BLUE if active else Color("cfddf3"), 3 if active else 1)
		cards[i].add_theme_stylebox_override("normal", normal)
		cards[i].add_theme_stylebox_override("hover", Style.pill(Color("e1efff"), 24, Style.BLUE, 2))
		cards[i].add_theme_stylebox_override("pressed", Style.pill(Color("c9e3ff"), 24, Style.BLUE, 3))
		cards[i].add_theme_stylebox_override("focus", Style.focus_box(24))
		if i < entries.size():
			cards[i].get_meta("detail").text = "GAME_SELECTED" if active else "GAME_TWO_PLAYERS"

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
