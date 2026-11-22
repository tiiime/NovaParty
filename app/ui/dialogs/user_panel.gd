extends "res://app/ui/widgets/sheet.gd"
signal saved(value: Dictionary)
const UserProfile = preload("res://sdk/session/user_profile.gd")
var draft := {}
var name_input: LineEdit
var preview: TextureRect
var preview_name: Label
var character_grid: GridContainer
var palette_grid: GridContainer
var theme_grid: GridContainer
var character_buttons := []
var palette_buttons := []
var theme_buttons := []
var cancel_button: Button
var save_button: Button
var error_label: Label
var swatches := {}

func _ready() -> void:
	super._ready()
	done.hide()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	add_content(body)
	var title := Label.new()
	_caption(body, "PROFILE_LOCAL")
	title.text = "USER_INFO"
	Style.label(title, T.FONT_SIZE_TITLE, T.FONT_WEIGHT_TITLE)
	body.add_child(title)
	_caption(body, "PROFILE_HELP", true)
	var top_panel := PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", Style.pill(T.SKY_SOFT, T.RADIUS_CARD))
	body.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top_panel.add_child(top)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(100,100)
	top.add_child(preview)
	preview_name = Label.new()
	preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Style.label(preview_name, T.FONT_SIZE_SECTION, T.FONT_WEIGHT_TITLE)
	top.add_child(preview_name)
	_caption(body, "USER_NAME")
	name_input = LineEdit.new()
	name_input.max_length = 32
	name_input.custom_minimum_size.y = T.HIT_MIN
	name_input.accessibility_name = tr("USER_NAME")
	name_input.placeholder_text = UserProfile.device_name()
	body.add_child(name_input)
	name_input.text_changed.connect(func(value): draft.nickname = value; _refresh())
	_caption(body, "USER_DEVICE_NAME", true)
	_caption(body, "USER_CHARACTER")
	character_grid = GridContainer.new()
	character_grid.columns = 3
	character_grid.add_theme_constant_override("h_separation", 10)
	character_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(character_grid)
	for character in UserProfile.CHARACTERS:
		var button := _choice(character_grid, "CHAR_" + character.to_upper(), func(): draft.avatar.character = character; _refresh())
		button.custom_minimum_size = Vector2(110,90)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 52)
		character_buttons.append(button)
	_caption(body, "USER_PALETTE")
	var palettes := GridContainer.new()
	palette_grid = palettes
	palettes.columns = 2
	palettes.add_theme_constant_override("h_separation", 10)
	palettes.add_theme_constant_override("v_separation", 8)
	body.add_child(palettes)
	for palette in UserProfile.PALETTES:
		palette_buttons.append(_choice(palettes, "PALETTE_" + palette.to_upper(), func(): draft.avatar.palette = palette; _refresh()))
	_caption(body, "USER_THEME")
	var themes := GridContainer.new()
	theme_grid = themes
	themes.columns = 3
	themes.add_theme_constant_override("h_separation", 10)
	themes.add_theme_constant_override("v_separation", 8)
	body.add_child(themes)
	for color in UserProfile.THEMES:
		theme_buttons.append(_choice(themes, "THEME_" + color.to_upper(), func(): draft.theme_color = color; _refresh()))
	error_label = Label.new()
	error_label.text = "USER_SAVE_FAILED"
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.label(error_label, T.FONT_SIZE_BODY, T.FONT_WEIGHT_LABEL, T.DANGER)
	error_label.add_theme_stylebox_override("normal", Style.banner("danger"))
	error_label.hide()
	body.add_child(error_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	panel.get_child(0).add_child(footer)
	cancel_button = _action(footer, "CANCEL", "secondary", close)
	cancel_button.set_meta("sound_cue", "back")
	save_button = _action(footer, "SAVE", "primary", func(): saved.emit(draft.duplicate(true)))
	save_button.set_meta("haptic", "confirm")
	_connect_focus()
	visibility_changed.connect(func():
		if visible: _connect_focus()
	)

func _caption(parent: Node, key: String, hint: bool = false) -> void:
	var label := Label.new()
	label.text = key
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.label(label, T.FONT_SIZE_META, T.FONT_WEIGHT_BODY if hint else T.FONT_WEIGHT_TITLE, T.MUTED)
	parent.add_child(label)

func _action(parent: Node, key: String, kind: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = key
	Style.button(button, kind)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _choice(parent: Node, key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.set_meta("label_key",key)
	button.toggle_mode = true
	button.set_meta("haptic", "select")
	Style.card(button, false, T.RADIUS_BUTTON)
	button.add_theme_font_override("font", Style.font(T.FONT_WEIGHT_LABEL))
	button.add_theme_font_size_override("font_size",18)
	button.custom_minimum_size = Vector2(0,T.BUTTON_HEIGHT_SMALL + T.LIP)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func edit(local: Dictionary) -> void:
	draft = local.duplicate(true)
	var public := UserProfile.local_public(draft)
	draft.avatar = public.avatar.duplicate(true)
	draft.theme_color = public.theme_color
	name_input.accessibility_name = tr("USER_NAME")
	name_input.text = str(draft.get("nickname",""))
	name_input.placeholder_text = UserProfile.device_name()
	error_label.hide()
	_refresh()
	popup_centered(Vector2i(1080,840) if size.x >= 1200 else Vector2i(600,900))
	character_buttons[UserProfile.CHARACTERS.find(draft.avatar.character)].grab_focus()

func _refresh() -> void:
	var public := UserProfile.local_public(draft)
	preview.texture = UserProfile.texture(public)
	preview_name.text = public.display_name
	preview_name.add_theme_color_override("font_color", T.INK)
	preview.get_parent().get_parent().add_theme_stylebox_override("panel", Style.pill(T.SKY_SOFT, T.RADIUS_CARD, UserProfile.color(public), T.STROKE))
	for index in range(character_buttons.size()):
		var appearance := public.duplicate(true)
		appearance.avatar.character = UserProfile.CHARACTERS[index]
		character_buttons[index].icon = UserProfile.texture(appearance)
		_selected(character_buttons[index],UserProfile.CHARACTERS[index] == public.avatar.character)
	for index in range(palette_buttons.size()):
		var button: Button = palette_buttons[index]
		var selected: bool = UserProfile.PALETTES[index] == public.avatar.palette
		_selected(button,selected)
		button.icon = _swatch(Color(["dea65c","d67ea8","69b9a1","7f9fd5"][index]))
	var keys: Array = UserProfile.THEMES.keys()
	for index in range(theme_buttons.size()):
		_selected(theme_buttons[index],keys[index] == public.theme_color)
		theme_buttons[index].icon = _swatch(Color(UserProfile.THEMES[keys[index]]))

func _selected(button: Button, selected: bool) -> void:
	button.text = tr(button.get_meta("label_key"))
	button.set_meta("selected", selected)
	button.set_pressed_no_signal(selected)
	Style.card(button, selected, T.RADIUS_BUTTON)

# Round colour chip used as a button icon; colour is never the only cue (label + selected lip).
func _swatch(color: Color) -> Texture2D:
	if not swatches.has(color):
		var image := Image.create(40, 40, false, Image.FORMAT_RGBA8)
		for y in range(40):
			for x in range(40):
				var distance := Vector2(x - 19.5, y - 19.5).length()
				image.set_pixel(x, y, Color(color, clampf(19.0 - distance, 0, 1)))
		swatches[color] = ImageTexture.create_from_image(image)
	return swatches[color]

func _connect_focus() -> void:
	var order: Array = [name_input] + character_buttons + palette_buttons + theme_buttons + [cancel_button,save_button]
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index+1)%order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index+order.size()-1)%order.size()])
	name_input.focus_neighbor_top = name_input.get_path_to(save_button)
	save_button.focus_neighbor_bottom = save_button.get_path_to(name_input)

func _layout() -> void:
	if character_grid == null:
		super._layout()
		return
	var wide := size.x >= 1200
	desired_size = Vector2(1080,840) if wide else Vector2(600,900)
	super._layout()
	var panel_width := minf(desired_size.x, size.x - 2 * _safe_inset().x)
	var gutters := panel.get_theme_stylebox("panel").get_minimum_size().x + 2 * content.get_theme_constant("margin_left")
	var inner_width := panel_width - gutters
	var full_grid := wide and inner_width >= 920
	character_grid.columns = 6 if full_grid else 3 if inner_width >= 350 else 2
	palette_grid.columns = 4 if full_grid else 2
	theme_grid.columns = character_grid.columns
	for button in character_buttons:
		button.custom_minimum_size = Vector2(144,112) if character_grid.columns == 6 else Vector2(0,90)
		button.add_theme_constant_override("icon_max_width",72 if wide else 60)
	for button in character_buttons + palette_buttons + theme_buttons + [save_button,cancel_button]:
		button.add_theme_font_size_override("font_size",22 if wide else 18)
