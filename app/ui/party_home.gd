extends Control
signal start_requested
signal join_requested
signal settings_requested
const Style = preload("res://app/ui/party_theme.gd")
const STAR = preload("res://assets/ui/star.svg")
var start_button: Button
var join_button: Button
var settings_button: Button
var nickname_button: Button
var title: Label
var subtitle: Label
var hint: Label
var reduced_motion := false
var motion_time := 0.0
var safe_insets := {"left": 24, "right": 24, "top": 24, "bottom": 24}
var star_center := Vector2.ZERO
var star_extent := 260.0
var _frame_accumulator := 0.0
var _clock_accumulator := 0.0
var sky_top := Color("183cd4")
var sky_bottom := Color("286de9")
var sky_texture: GradientTexture2D
var spot_texture: GradientTexture2D
var confetti_styles: Array[StyleBoxFlat] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_texture = GradientTexture2D.new()
	sky_texture.width = 8
	sky_texture.height = 256
	sky_texture.gradient = Gradient.new()
	sky_texture.fill_from = Vector2.ZERO
	sky_texture.fill_to = Vector2(0, 1)
	spot_texture = GradientTexture2D.new()
	spot_texture.width = 256
	spot_texture.height = 256
	spot_texture.fill = GradientTexture2D.FILL_RADIAL
	spot_texture.fill_from = Vector2(0.5, 0.5)
	spot_texture.fill_to = Vector2(0.5, 1.0)
	spot_texture.gradient = Gradient.new()
	spot_texture.gradient.colors = PackedColorArray([Color(0.4, 0.78, 1, 0.28), Color(0.4, 0.78, 1, 0)])
	_update_sky()
	for color in [Color("ff75b9"), Color("68ebff"), Color("ffe34b")]:
		confetti_styles.append(Style.pill(color, 3))
	title = _label("APP_NAME", 48, true)
	title.add_theme_color_override("font_shadow_color", Color("123ca9"))
	title.add_theme_constant_override("shadow_offset_y", 5)
	subtitle = _label("HOME_TAGLINE", 23)
	hint = _label("HOME_HINT", 22)
	start_button = _button("START_GAME", false, func(): start_requested.emit())
	join_button = _button("JOIN_GAME", true, func(): join_requested.emit())
	settings_button = _button("SETTINGS", true, func(): settings_requested.emit())
	nickname_button = _button("", true, func(): settings_requested.emit())
	nickname_button.hide()
	resized.connect(_layout)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()); queue_redraw())
	_layout()
	start_button.grab_focus()

func _label(key: String, font_size: int, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bold:
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
		label.add_theme_font_override("font", font)
	add_child(label)
	return label

func _button(key: String, secondary: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.focus_mode = Control.FOCUS_ALL
	Style.button(button, secondary)
	button.pressed.connect(callback)
	add_child(button)
	return button

func set_nickname(value: String) -> void:
	if nickname_button:
		nickname_button.text = tr("HOME_NICKNAME") % value

func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	# Freeze the current pose immediately; re-enabling continues without a jump.
	queue_redraw()

func set_safe_insets(value: Dictionary) -> void:
	safe_insets = value
	if is_node_ready():
		_layout()

func _layout() -> void:
	if not is_instance_valid(title):
		return
	var left := float(safe_insets.left) + 12
	var right := size.x - float(safe_insets.right) - 12
	var top := float(safe_insets.top) + 10
	var bottom := size.y - float(safe_insets.bottom) - 8
	var width := maxf(220, right - left)
	var portrait := size.x < size.y
	title.position = Vector2(left, top)
	title.size = Vector2(width, 94)
	title.add_theme_font_size_override("font_size", 42 if portrait else 54)
	subtitle.position = Vector2(left, top + (98 if portrait else 82))
	subtitle.size = Vector2(width, 64)
	var buttons_y: float
	if portrait:
		buttons_y = bottom - 282
		start_button.position = Vector2(left + 8, buttons_y)
		start_button.size = Vector2(width - 16, 88)
		join_button.position = Vector2(left + 8, buttons_y + 110)
		join_button.size = Vector2(width - 16, 82)
		var stage_top := top + 172
		var stage_bottom := buttons_y - 42
		star_extent = clampf((stage_bottom - stage_top) * 0.8, 96, minf(270, width * 0.66))
		star_center = Vector2(size.x * 0.5, (stage_top + stage_bottom) * 0.5)
	else:
		buttons_y = top + (bottom - top) * 0.36
		start_button.position = Vector2(left + width * 0.52, buttons_y)
		start_button.size = Vector2(width * 0.46, 116)
		join_button.position = Vector2(start_button.position.x, buttons_y + 150)
		join_button.size = Vector2(start_button.size.x, 104)
		star_extent = minf(320, (bottom - top) * 0.49)
		star_center = Vector2(left + width * 0.24, top + (bottom - top) * 0.55)
	settings_button.position = Vector2(right - 160, bottom - 64)
	settings_button.size = Vector2(160, 64)
	settings_button.add_theme_font_size_override("font_size", 21)
	nickname_button.position = Vector2(left, bottom - 64)
	nickname_button.size = Vector2(minf(230, width - 184), 64)
	nickname_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nickname_button.add_theme_font_size_override("font_size", 20)
	hint.visible = not portrait
	hint.position = Vector2(start_button.position.x, bottom - 117)
	hint.size = Vector2(start_button.size.x, 70)
	# Explicit navigation avoids geometry-based surprises when the canvas rotates.
	var buttons := [start_button, join_button, settings_button]
	for i in range(buttons.size()):
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i + buttons.size() - 1) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
	queue_redraw()

func _process(delta: float) -> void:
	_clock_accumulator += delta
	if _clock_accumulator >= 60:
		_clock_accumulator = 0
		_update_sky()
	if reduced_motion:
		return
	motion_time += delta
	_frame_accumulator += delta
	# UI is native and runs normally; redraw only the decorative layer at 30 fps.
	if _frame_accumulator >= 1.0 / 30.0:
		_frame_accumulator = 0
		queue_redraw()

func _update_sky() -> void:
	var clock := Time.get_datetime_dict_from_system()
	var hour := float(clock.hour) + float(clock.minute) / 60.0
	var index := int(hour / 6.0) % 4
	var blend := fmod(hour, 6.0) / 6.0
	var tops := [Color("2639bd"), Color("234be0"), Color("183cd4"), Color("393fd2")]
	var bottoms := [Color("4960d9"), Color("3a78ed"), Color("286de9"), Color("5369e6")]
	sky_top = tops[index].lerp(tops[(index + 1) % 4], blend)
	sky_bottom = bottoms[index].lerp(bottoms[(index + 1) % 4], blend)
	if sky_texture:
		sky_texture.gradient.colors = PackedColorArray([sky_top, sky_bottom])
	queue_redraw()

# Shared by draw and tests; no GUI state is inferred from animation phase.
func orbit_positions(at_time: float) -> Array:
	var points := []
	for i in range(3):
		var angle := at_time * (0.24 + i * 0.035) + i * TAU / 3.0
		points.append(star_center + Vector2(cos(angle) * star_extent * 0.67, sin(angle) * star_extent * 0.39))
	return points

func _draw_star(center: Vector2, extent: float, angle: float = 0.0) -> void:
	draw_set_transform(center, angle)
	draw_texture_rect(STAR, Rect2(Vector2.ONE * -extent / 2, Vector2.ONE * extent), false)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if not sky_texture:
		return
	draw_texture_rect(sky_texture, Rect2(Vector2.ZERO, size), false)
	draw_texture_rect(spot_texture, Rect2(star_center - Vector2.ONE * star_extent, Vector2.ONE * star_extent * 2), false)
	var floor_points := PackedVector2Array([Vector2(0, size.y)])
	for i in range(33):
		var x := size.x * i / 32.0
		floor_points.append(Vector2(x, size.y - 86 + sin(float(i) / 32 * TAU) * 16))
	floor_points.append(size)
	draw_colored_polygon(floor_points, Color("e9f3ff"))
	# Elliptical floating stage; draw transformed circles, not a raster background.
	var stage := star_center + Vector2(0, star_extent * 0.58)
	draw_set_transform(stage + Vector2(0, 6), 0, Vector2(1, 0.19))
	draw_circle(Vector2.ZERO, star_extent * 0.6, Color("95d9ff"))
	draw_set_transform(stage, 0, Vector2(1, 0.17))
	draw_circle(Vector2.ZERO, star_extent * 0.6, Color.WHITE)
	draw_set_transform(Vector2.ZERO)
	var ring := PackedVector2Array()
	for i in range(97):
		var a := i * TAU / 96.0
		ring.append(star_center + Vector2(cos(a) * star_extent * 0.67, sin(a) * star_extent * 0.39))
	draw_polyline(ring, Color(0.57, 0.9, 1.0, 0.45), 1.5, true)
	var float_offset := Vector2(0, sin(motion_time * 1.1) * 5)
	_draw_star(star_center + float_offset, star_extent, -0.12 + sin(motion_time * 0.7) * 0.025)
	var points := orbit_positions(motion_time)
	for i in range(points.size()):
		var extent := star_extent * (0.13 + i * 0.012) * (1.0 + sin(motion_time * 1.4 + i) * 0.12)
		_draw_star(points[i], extent, 0.15 * sin(motion_time + i))
	# Sparse party confetti lives in the periphery and never intercepts input.
	for i in range(8):
		var point := Vector2(size.x * (0.03 if i % 2 == 0 else 0.96), size.y * (0.20 + float(i) * 0.075))
		draw_set_transform(point, float(i) * 0.4)
		draw_style_box(confetti_styles[i % 3], Rect2(-3, -7, 6, 14))
	draw_set_transform(Vector2.ZERO)
