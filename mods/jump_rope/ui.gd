extends RefCounted
# Mod-local copy of the platform's juicy flat look (design v0.4). Mods must not import app code.
const INK = Color("133464")
const BLUE = Color("2058e0")
const LIP = 4

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

# Face on a 4-unit lip; pressing removes the lip and sinks the face.
static func slab(fill: Color, lip: Color, outlined: bool, pressed: bool = false) -> StyleBoxFlat:
	var edge := 2 if outlined else 0
	var style := box(fill, 16, lip, edge)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if pressed:
		style.expand_margin_top = -LIP
		style.content_margin_top += LIP
	else:
		style.border_width_bottom = edge + LIP
		style.content_margin_bottom += LIP
	return style

static func button(target: Button, primary: bool = false) -> void:
	target.custom_minimum_size.y = 60
	target.add_theme_font_size_override("font_size", 23)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		target.add_theme_color_override(key, INK if primary else BLUE)
	target.add_theme_color_override("font_disabled_color", Color("8294a3"))
	var fill := Color("ffe34b") if primary else Color.WHITE
	var lip := Color("e0a612") if primary else Color("bcd2f0")
	target.add_theme_stylebox_override("normal", slab(fill, lip, not primary))
	target.add_theme_stylebox_override("hover", slab(Color("ffec8a") if primary else Color("e1efff"), lip, not primary))
	target.add_theme_stylebox_override("pressed", slab(Color("f7d13a") if primary else Color("e1efff"), lip, not primary, true))
	target.add_theme_stylebox_override("disabled", slab(Color("e1eaf0"), Color("e1eaf0"), false))
	var focus := box(Color.TRANSPARENT, 19, Color("ff8a1c"), 6)
	focus.draw_center = false
	focus.set_expand_margin_all(3)
	target.add_theme_stylebox_override("focus", focus)
