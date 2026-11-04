extends "res://app/ui/settings_panel.gd"
signal saved(value: Dictionary)
const UserProfile = preload("res://sdk/user_profile.gd")
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
var focused_before: Control

func _ready() -> void:
	super._ready()
	done.hide()
	Style.scroll_container(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	add_content(body)
	var title := Label.new()
	title.text = "USER_INFO"
	title.add_theme_font_size_override("font_size", 30)
	body.add_child(title)
	var top := HBoxContainer.new()
	body.add_child(top)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(100,100)
	top.add_child(preview)
	preview_name = Label.new()
	preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(preview_name)
	_caption(body, "USER_NAME")
	name_input = LineEdit.new()
	name_input.max_length = 32
	name_input.custom_minimum_size.y = 56
	name_input.placeholder_text = UserProfile.device_name()
	body.add_child(name_input)
	name_input.text_changed.connect(func(value): draft.nickname = value; _refresh())
	_caption(body, "USER_DEVICE_NAME")
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
	body.add_child(palettes)
	for palette in UserProfile.PALETTES:
		palette_buttons.append(_choice(palettes, "PALETTE_" + palette.to_upper(), func(): draft.avatar.palette = palette; _refresh()))
	_caption(body, "USER_THEME")
	var themes := GridContainer.new()
	theme_grid = themes
	themes.columns = 3
	body.add_child(themes)
	for color in UserProfile.THEMES:
		theme_buttons.append(_choice(themes, "THEME_" + color.to_upper(), func(): draft.theme_color = color; _refresh()))
	error_label = Label.new()
	error_label.text = "USER_SAVE_FAILED"
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_color_override("font_color",Color("ad3128"))
	error_label.hide()
	body.add_child(error_label)
	var footer := HBoxContainer.new()
	panel.get_child(0).add_child(footer)
	cancel_button = _choice(footer,"CANCEL",close)
	save_button = _choice(footer,"SAVE",func(): saved.emit(draft.duplicate(true)))
	_connect_focus()
	visibility_changed.connect(func():
		if visible: _connect_focus()
	)

func _caption(parent: Node, key: String) -> void:
	var label := Label.new()
	label.text = key
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",18)
	parent.add_child(label)

func _choice(parent: Node, key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.set_meta("label_key",key)
	Style.button(button,true)
	button.add_theme_font_size_override("font_size",18)
	button.custom_minimum_size = Vector2(0,52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func edit(local: Dictionary) -> void:
	draft = local.duplicate(true)
	var public := UserProfile.local_public(draft)
	draft.avatar = public.avatar.duplicate(true)
	draft.theme_color = public.theme_color
	name_input.text = str(draft.get("nickname",""))
	name_input.placeholder_text = UserProfile.device_name()
	error_label.hide()
	_refresh()
	popup_centered(Vector2i(1080,840) if size.x >= 1200 else Vector2i(600,900))
	character_buttons[UserProfile.CHARACTERS.find(draft.avatar.character)].grab_focus()
	_reset_scroll.call_deferred()

func _refresh() -> void:
	var public := UserProfile.local_public(draft)
	preview.texture = UserProfile.texture(public)
	preview_name.text = public.display_name
	preview_name.add_theme_color_override("font_color", UserProfile.color(public))
	for index in range(character_buttons.size()):
		var appearance := public.duplicate(true)
		appearance.avatar.character = UserProfile.CHARACTERS[index]
		character_buttons[index].icon = UserProfile.texture(appearance)
		_selected(character_buttons[index],UserProfile.CHARACTERS[index] == public.avatar.character)
	for index in range(palette_buttons.size()):
		var button: Button = palette_buttons[index]
		var selected: bool = UserProfile.PALETTES[index] == public.avatar.palette
		_selected(button,selected)
		button.add_theme_stylebox_override("normal",Style.pill(Color(["dea65c","d67ea8","69b9a1","7f9fd5"][index]).lightened(.48),18,Style.BLUE if selected else Color.TRANSPARENT,3 if selected else 0))
	var keys: Array = UserProfile.THEMES.keys()
	for index in range(theme_buttons.size()):
		_selected(theme_buttons[index],keys[index] == public.theme_color)
		theme_buttons[index].add_theme_color_override("font_color",Color(UserProfile.THEMES[keys[index]]))

func _selected(button: Button, selected: bool) -> void:
	button.text = ("✓ " if selected else "") + tr(button.get_meta("label_key"))
	button.add_theme_stylebox_override("normal",Style.pill(Color("fff1ad") if selected else Color("edf4ff"),18,Style.BLUE if selected else Color.TRANSPARENT,3 if selected else 0))

func _connect_focus() -> void:
	var order: Array = [name_input] + character_buttons + palette_buttons + theme_buttons + [cancel_button,save_button]
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index+1)%order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index+order.size()-1)%order.size()])
	name_input.focus_neighbor_top = name_input.get_path_to(save_button)
	save_button.focus_neighbor_bottom = save_button.get_path_to(name_input)

func _reset_scroll() -> void:
	await get_tree().process_frame
	if is_inside_tree(): scroll.scroll_vertical = 0

func _layout() -> void:
	if character_grid == null:
		super._layout()
		return
	var wide := size.x >= 1200
	desired_size = Vector2(1080,840) if wide else Vector2(600,900)
	character_grid.columns = 6 if wide else 3
	palette_grid.columns = 4 if wide else 2
	theme_grid.columns = 6 if wide else 3
	for button in character_buttons:
		button.custom_minimum_size = Vector2(144,112) if wide else Vector2(110,90)
		button.add_theme_constant_override("icon_max_width",72 if wide else 60)
	for button in character_buttons + palette_buttons + theme_buttons + [save_button,cancel_button]:
		button.add_theme_font_size_override("font_size",22 if wide else 18)
	super._layout()
	_fit_panel.call_deferred()

func _fit_panel() -> void:
	if not is_inside_tree(): return
	panel.size = desired_size.min(size - Vector2(48,100))
	panel.position = (size - panel.size) * .5
