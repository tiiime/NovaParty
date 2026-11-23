extends RefCounted
# Juicy flat kit (design v0.4): solid fills, 2-unit strokes and a 4-unit lower lip.
# Pressing removes the lip and sinks the face by the same amount, so layout never jumps.
const T = preload("res://app/ui/theme/tokens.gd")
const FocusEffect = preload("res://app/ui/theme/focus_effect.gd")
const INK = T.INK
const BLUE = T.SKY
static var _fonts := {}

static func token(name: String) -> Color:
	return T.COLORS.get(name, Color.TRANSPARENT)

static func font(weight: int = T.FONT_WEIGHT_BODY) -> FontVariation:
	if not _fonts.has(weight):
		var variation := FontVariation.new()
		variation.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): float(weight)}
		_fonts[weight] = variation
	return _fonts[weight]

static func pill(fill: Color, radius: int = T.RADIUS_CARD, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.anti_aliasing_size = 0.6
	return box

# A face resting on a lip. `stroke` outlines white/soft faces with the lip colour.
static func slab(fill: Color, lip: Color, radius: int, stroke: bool, pressed: bool = false, pad: Vector2 = Vector2(20, 10)) -> StyleBoxFlat:
	var edge := T.STROKE if stroke else 0
	var box := pill(fill, radius, lip, edge)
	box.content_margin_left = pad.x
	box.content_margin_right = pad.x
	if pressed:
		box.expand_margin_top = -T.LIP
		box.content_margin_top = pad.y + T.LIP
		box.content_margin_bottom = pad.y
	else:
		box.border_width_bottom = edge + T.LIP
		box.content_margin_top = pad.y
		box.content_margin_bottom = pad.y + T.LIP
	return box

static func feedback(button: Button, card: bool = false) -> void:
	if button.has_node("FocusFeedback"): return
	# Only the overlay paints focus so engine states cannot stack a second outline on it.
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.set_meta("focus_card", card)
	var effect := FocusEffect.new()
	effect.name = "FocusFeedback"
	button.add_child(effect)

# kind: "primary" | "accent" | "secondary" | "danger". Booleans keep the old API (true = secondary).
static func button(target: Button, kind = "primary", height: int = T.BUTTON_HEIGHT) -> void:
	if kind is bool: kind = "secondary" if kind else "primary"
	var spec: Dictionary = T.BUTTON[kind]
	var fill := token(spec.fill)
	var lip := token(spec.lip)
	var outlined: bool = not str(spec.border).is_empty()
	target.set_meta("kit_kind", kind)
	target.add_theme_font_override("font", font(T.FONT_WEIGHT_TITLE))
	target.add_theme_font_size_override("font_size", T.FONT_SIZE_BUTTON)
	target.add_theme_stylebox_override("normal", slab(fill, lip, T.RADIUS_BUTTON, outlined))
	target.add_theme_stylebox_override("hover", slab(fill.lerp(T.SKY_SOFT if outlined else Color.WHITE, 0.6 if outlined else 0.18), lip, T.RADIUS_BUTTON, outlined))
	var pressed := slab(fill.lerp(lip, 0.25), lip, T.RADIUS_BUTTON, outlined, true)
	target.add_theme_stylebox_override("pressed", pressed)
	target.add_theme_stylebox_override("hover_pressed", pressed)
	target.add_theme_stylebox_override("disabled", slab(T.DISABLED, T.DISABLED, T.RADIUS_BUTTON, false))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(state, token(spec.text))
	target.add_theme_color_override("font_disabled_color", T.DISABLED_TEXT)
	target.custom_minimum_size.y = maxi(height, T.HIT_MIN)
	target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target.set_meta("focus_radius", T.RADIUS_BUTTON)
	feedback(target)

# Selectable tile: a latched selection keeps its raised lip after the click.
static func card(target: Button, selected: bool = false, radius: int = T.RADIUS_CARD) -> void:
	var fill := T.SKY_SOFT if selected else T.PANEL
	var lip := T.SELECTION_LIP if selected else T.LINE_LIP
	var pad := Vector2(14, 12)
	target.add_theme_stylebox_override("normal", slab(fill, lip, radius, true, false, pad))
	target.add_theme_stylebox_override("hover", slab(T.SKY_SOFT, lip, radius, true, false, pad))
	var pressed := slab(T.SKY_SOFT, lip, radius, true, not (target.toggle_mode and selected), pad)
	target.add_theme_stylebox_override("pressed", pressed)
	target.add_theme_stylebox_override("hover_pressed", pressed)
	target.add_theme_stylebox_override("disabled", slab(T.DISABLED, T.DISABLED, radius, false, false, pad))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(state, T.SKY if selected else T.INK)
	target.set_meta("focus_radius", radius)
	target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	feedback(target, true)

static func sheet(radius: int = T.RADIUS_SHEET) -> StyleBoxFlat:
	var box := slab(T.PANEL, T.LINE_LIP, radius, true, false, Vector2(24, 24))
	box.content_margin_top = 24
	box.content_margin_bottom = 24 + T.LIP
	return box

static func banner(kind: String = "info") -> StyleBoxFlat:
	var colors: Array = {"info": [T.SKY_SOFT, T.LINE_LIP], "success": [T.SUCCESS_SOFT, T.SUCCESS_LINE], "danger": [T.DANGER_SOFT, T.DANGER_LINE], "wait": [T.STAR_SOFT, T.STAR_LIP]}[kind]
	return pill(colors[0], T.RADIUS_INPUT, colors[1], T.STROKE)

static func label(target: Label, size: int = T.FONT_SIZE_BODY, weight: int = T.FONT_WEIGHT_BODY, color: Color = T.INK) -> Label:
	target.add_theme_font_override("font", font(weight))
	target.add_theme_font_size_override("font_size", size)
	target.add_theme_color_override("font_color", color)
	return target

static func progress(bar: ProgressBar) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size.y = T.PROGRESS_HEIGHT
	var track := pill(T.LINE, T.PROGRESS_HEIGHT / 2)
	track.set_content_margin_all(0)
	var fill := pill(T.STAR, T.PROGRESS_HEIGHT / 2, T.STAR_LIP, 0)
	fill.set_content_margin_all(0)
	fill.border_width_bottom = T.LIP
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)

# Application-wide defaults for plain controls; kit functions add per-control overrides.
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font(T.FONT_WEIGHT_BODY)
	theme.default_font_size = T.FONT_SIZE_BODY
	theme.set_color("font_color", "Label", T.INK)
	theme.set_stylebox("panel", "PopupMenu", pill(T.PANEL, T.RADIUS_INPUT, T.LINE_LIP, T.STROKE))
	theme.set_stylebox("hover", "PopupMenu", pill(T.SKY_SOFT, 10))
	for key in ["font_color", "font_hover_color"]:
		theme.set_color(key, "PopupMenu", T.INK)
	theme.set_color("font_color", "LineEdit", T.INK)
	theme.set_color("font_placeholder_color", "LineEdit", T.MUTED)
	theme.set_color("caret_color", "LineEdit", T.SKY)
	theme.set_stylebox("normal", "LineEdit", pill(T.PAGE, T.RADIUS_INPUT, T.LINE_LIP, T.STROKE))
	theme.set_stylebox("focus", "LineEdit", pill(T.PANEL, T.RADIUS_INPUT, T.SKY, T.STROKE + 1))
	for key in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(key, "OptionButton", T.INK)
	theme.set_font("font", "OptionButton", font(T.FONT_WEIGHT_LABEL))
	theme.set_stylebox("normal", "OptionButton", slab(T.PANEL, T.LINE_LIP, T.RADIUS_INPUT, true))
	theme.set_stylebox("hover", "OptionButton", slab(T.SKY_SOFT, T.LINE_LIP, T.RADIUS_INPUT, true))
	theme.set_stylebox("pressed", "OptionButton", slab(T.SKY_SOFT, T.LINE_LIP, T.RADIUS_INPUT, true, true))
	theme.set_stylebox("focus", "OptionButton", FocusEffect.ring_box(T.RADIUS_INPUT))
	return theme
