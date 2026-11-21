extends Control
signal start_requested
signal join_requested
signal settings_requested
signal user_requested
const UserProfile = preload("res://sdk/session/user_profile.gd")
const Style = preload("res://app/ui/theme/party_theme.gd")
const Icons = preload("res://app/ui/theme/party_icons.gd")
const T = Style.T
const STAR = preload("res://assets/ui/star.svg")
var start_button: Button
var join_button: Button
var settings_button: Button
var nickname_button: Button
var reduced_motion := false
var motion_time := 0.0
var margin: MarginContainer
var split: BoxContainer
var header: HBoxContainer
var panel: PanelContainer
var artwork: Control
var copy: VBoxContainer
var title: Label
var tagline: Label
var hero: BoxContainer
var profile_name: String
var _frame_elapsed := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 16)
	margin.add_child(shell)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	shell.add_child(header)
	var mark := TextureRect.new()
	mark.texture = STAR
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(mark)
	var brand := _label(header, "APP_NAME", 23, T.FONT_WEIGHT_TITLE, T.INK)
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var badge := _label(header, "HOME_LOCAL", 16, T.FONT_WEIGHT_LABEL, T.SKY_LIP)
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.add_theme_stylebox_override("normal", Style.pill(T.SKY_SOFT, T.RADIUS_BUTTON))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 12
	Style.scroll_container(scroll, 8)
	shell.add_child(scroll)
	var centered := CenterContainer.new()
	centered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centered.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centered)
	split = BoxContainer.new()
	split.add_theme_constant_override("separation", 24)
	centered.add_child(split)
	panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.slab(T.SKY, T.SKY_LIP, 28, false, false, Vector2(28, 24)))
	split.add_child(panel)
	hero = BoxContainer.new()
	hero.vertical = true
	hero.add_theme_constant_override("separation", 8)
	panel.add_child(hero)
	copy = VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 8)
	hero.add_child(copy)
	_label(copy, "HOME_KICKER", 16, T.FONT_WEIGHT_TITLE, T.STAR)
	title = _label(copy, "HOME_HERO", 44, T.FONT_WEIGHT_TITLE, T.WHITE)
	tagline = _label(copy, "HOME_TAGLINE", 22, T.FONT_WEIGHT_BODY, T.WHITE)
	artwork = Control.new()
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.draw.connect(_draw_art)
	hero.add_child(artwork)

	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 12)
	split.add_child(actions)
	_label(actions, "HOME_PLAY_SECTION", 18, T.FONT_WEIGHT_TITLE, T.SKY_LIP)
	start_button = _button(actions, "START_GAME", "play", "primary", func(): start_requested.emit())
	_label(actions, "HOME_START_HINT", 19, T.FONT_WEIGHT_BODY, T.MUTED)
	join_button = _button(actions, "JOIN_GAME", "join", "secondary", func(): join_requested.emit())
	_label(actions, "HOME_JOIN_HINT", 19, T.FONT_WEIGHT_BODY, T.MUTED)

	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 12)
	shell.add_child(dock)
	nickname_button = _button(dock, "USER_INFO", "profile", "secondary", func(): user_requested.emit(), T.BUTTON_HEIGHT)
	settings_button = _button(dock, "SETTINGS", "settings", "secondary", func(): settings_requested.emit(), T.BUTTON_HEIGHT)
	for button in [nickname_button, settings_button]:
		button.add_theme_font_size_override("font_size", 19)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
	var order := [start_button, join_button, nickname_button, settings_button]
	for i in range(order.size()):
		order[i].focus_next = order[i].get_path_to(order[(i + 1) % order.size()])
		order[i].focus_previous = order[i].get_path_to(order[(i + order.size() - 1) % order.size()])
	for button in [start_button, join_button, nickname_button, settings_button]:
		button.focus_neighbor_top = button.get_path_to(start_button if button == join_button else join_button if button != start_button else button)
	start_button.focus_neighbor_bottom = start_button.get_path_to(join_button)
	join_button.focus_neighbor_bottom = join_button.get_path_to(nickname_button)
	nickname_button.focus_neighbor_right = nickname_button.get_path_to(settings_button)
	settings_button.focus_neighbor_left = settings_button.get_path_to(nickname_button)
	resized.connect(_layout)
	scroll.resized.connect(_layout)
	visibility_changed.connect(_update_processing)
	_layout()
	_update_processing()

func _label(parent: Node, key: String, extent: int, weight: int, color: Color) -> Label:
	var label := Style.label(Label.new(), extent, weight, color)
	label.text = key
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, key: String, icon: String, kind: String, callback: Callable, height: int = T.BUTTON_HEIGHT_LARGE) -> Button:
	var button := Button.new()
	button.text = key
	button.icon = Icons.get_icon(icon, T.INK if kind == "primary" else T.SKY)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("h_separation", 12)
	Style.button(button, kind, height)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func set_user_profile(value: Dictionary) -> void:
	profile_name = str(value.display_name)
	nickname_button.tooltip_text = profile_name
	nickname_button.icon = UserProfile.texture(value)

func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	_update_processing()

func _update_processing() -> void:
	set_process(is_visible_in_tree() and not reduced_motion)

func set_safe_insets(value: Dictionary) -> void:
	for edge in value:
		margin.add_theme_constant_override("margin_" + edge, int(value[edge]))
	_layout()

func _layout() -> void:
	if not is_instance_valid(split): return
	var width := size.x - margin.get_theme_constant("margin_left") - margin.get_theme_constant("margin_right")
	var wide := width >= 840
	split.vertical = not wide
	split.custom_minimum_size.x = clampf(width - 40, 240, 1080 if wide else 600)
	panel.custom_minimum_size = Vector2(560, 410) if wide else Vector2(0, 0)
	artwork.custom_minimum_size = Vector2(0, 204 if wide else 164)
	title.add_theme_font_size_override("font_size", 48 if wide else 39)
	artwork.queue_redraw()

func _process(delta: float) -> void:
	if reduced_motion: return
	motion_time += delta
	_frame_elapsed += delta
	if _frame_elapsed >= 1.0 / 30.0:
		_frame_elapsed = 0.0
		artwork.queue_redraw()

func orbit_positions(at_time: float) -> Array:
	var center := artwork.size * Vector2(0.54, 0.52)
	var extent := minf(artwork.size.y, artwork.size.x * 0.52)
	return [center + Vector2(cos(at_time * 0.65) * extent * 0.76, sin(at_time * 0.65) * extent * 0.20), center + Vector2(-extent * 0.78, cos(at_time * 0.78) * 10), center + Vector2(extent * 0.52, -extent * 0.31)]

func _draw_art() -> void:
	var center := artwork.size * Vector2(0.54, 0.52)
	var extent := minf(artwork.size.y, artwork.size.x * 0.52)
	if extent <= 0: return
	artwork.draw_set_transform(center + Vector2(0, extent * 0.34), 0.0, Vector2(1, 0.24))
	artwork.draw_circle(Vector2.ZERO, extent * 0.68, T.SKY_LIP, true, -1.0, true)
	artwork.draw_set_transform(Vector2.ZERO)
	var sparks := orbit_positions(motion_time)
	for i in range(sparks.size()):
		var at: Vector2 = sparks[i]
		var radius := 8.0 + i * 2.0
		var color: Color = [T.MINT, T.PINK, T.STAR_SOFT][i]
		artwork.draw_line(at - Vector2(radius, 0), at + Vector2(radius, 0), color, 4, true)
		artwork.draw_line(at - Vector2(0, radius), at + Vector2(0, radius), color, 4, true)
	center.y += sin(motion_time * 1.5) * 5.0
	var side := extent * 1.06
	artwork.draw_set_transform(center, -0.14)
	artwork.draw_texture_rect(STAR, Rect2(Vector2.ONE * -side * 0.5, Vector2.ONE * side), false)
	artwork.draw_set_transform(Vector2.ZERO)
