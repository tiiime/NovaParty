extends RefCounted
const INK = Color("18395e")
const BLUE = Color("2464db")

static func box(fill: Color, radius: int = 20, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

static func button(target: Button, primary: bool = false) -> void:
	target.custom_minimum_size.y = 58
	target.add_theme_font_size_override("font_size", 23)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		target.add_theme_color_override(key, INK)
	target.add_theme_color_override("font_disabled_color", Color("73849b"))
	target.add_theme_stylebox_override("normal", box(Color("ffe261") if primary else Color.WHITE, 18, Color("e6bb39") if primary else Color("d6e2f4"), 1))
	target.add_theme_stylebox_override("hover", box(Color("ffec96") if primary else Color("e6f1ff"), 18, BLUE, 2))
	target.add_theme_stylebox_override("pressed", box(Color("f4ce39") if primary else Color("cddfff"), 18))
	target.add_theme_stylebox_override("disabled", box(Color("e6ebf2"), 18))
	target.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, 18, Color("13bedb"), 4))
