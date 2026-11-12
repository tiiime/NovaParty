extends Button
# Settings row: label on the left, a chunky two-state switch drawn on the right.
# It stays a toggle Button so focus, keyboard, `toggled` and `button_pressed` work unchanged.
const Style = preload("res://app/ui/theme/party_theme.gd")
const T = Style.T

func _init() -> void:
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = T.ROW_HEIGHT
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _ready() -> void:
	var pad := Vector2(20, 10)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := Style.slab(T.SKY_SOFT if state.begins_with("hover") else T.PANEL, T.LINE_LIP, T.RADIUS_BUTTON, true, false, pad)
		box.content_margin_right = pad.x + T.SWITCH_WIDTH + 12
		add_theme_stylebox_override(state, box)
	add_theme_stylebox_override("focus", Style.focus_box())
	add_theme_font_override("font", Style.font(T.FONT_WEIGHT_LABEL))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, T.INK)
	set_meta("focus_radius", T.RADIUS_BUTTON)
	set_meta("press_scale", false)
	Style.feedback(self)
	toggled.connect(func(_value): queue_redraw())

func _draw() -> void:
	var track := Rect2(size.x - 20 - T.SWITCH_WIDTH, (size.y - T.LIP - T.SWITCH_HEIGHT) / 2, T.SWITCH_WIDTH, T.SWITCH_HEIGHT)
	var body := Style.pill(T.SKY if button_pressed else T.LINE_LIP, T.SWITCH_HEIGHT / 2)
	draw_style_box(body, track)
	var knob_size := T.SWITCH_HEIGHT - 8.0
	var x := track.end.x - knob_size - 4 if button_pressed else track.position.x + 4
	var knob := Style.pill(T.PANEL, int(knob_size / 2), T.SKY_LIP if button_pressed else T.MUTED.lerp(T.LINE_LIP, 0.6), 0)
	knob.border_width_bottom = 3
	draw_style_box(knob, Rect2(x, track.position.y + 3, knob_size, knob_size + 1))
