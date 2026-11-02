extends RefCounted
const INK = Color("133464")
const BLUE = Color("2058e0")
const FocusEffect = preload("res://app/ui/focus_effect.gd")
const FOCUS_ORANGE = Color("ff8a1c")

static func focus_box(radius: int = 36) -> StyleBoxFlat:
	var box := pill(Color.TRANSPARENT, radius, FOCUS_ORANGE, 6)
	box.draw_center = false
	box.expand_margin_left = 3
	box.expand_margin_right = 3
	box.expand_margin_top = 3
	box.expand_margin_bottom = 3
	return box

static func feedback(button: Button, card: bool = false) -> void:
	if button.has_node("FocusFeedback"): return
	button.set_meta("focus_card", card)
	var effect := FocusEffect.new()
	effect.name = "FocusFeedback"
	button.add_child(effect)

static func scroll_container(scroll: ScrollContainer) -> void:
	# Keep card focus rings and the scroll thumb clear of the content edges.
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 14
	padding.content_margin_right = 20
	padding.content_margin_top = 14
	padding.content_margin_bottom = 14
	scroll.add_theme_stylebox_override("panel", padding)
	var bar := scroll.get_v_scroll_bar()
	bar.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("dfeafa")
	track.set_corner_radius_all(6)
	track.content_margin_left = 5
	track.content_margin_right = 5
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", StyleBoxEmpty.new())
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("82b5ef") if state == "grabber" else Color("4c94e5")
		thumb.set_corner_radius_all(6)
		thumb.content_margin_left = 5
		thumb.content_margin_right = 5
		thumb.content_margin_top = 20
		thumb.content_margin_bottom = 20
		bar.add_theme_stylebox_override(state, thumb)

static func pill(fill: Color, radius: int = 24, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

static func button(button: Button, secondary: bool = false) -> void:
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	button.add_theme_font_override("font", font)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxTexture.new()
		box.texture = load("res://assets/ui/button-" + ("pressed" if state == "pressed" else "secondary" if secondary else "primary") + ".svg")
		box.texture_margin_left = 38
		box.texture_margin_right = 38
		box.texture_margin_top = 32
		box.texture_margin_bottom = 38
		box.content_margin_left = 24
		box.content_margin_right = 24
		box.content_margin_top = 12
		box.content_margin_bottom = 18
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", focus_box())
	button.add_theme_stylebox_override("disabled", pill(Color("e1eaf0")))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_font_size_override("font_size", 26)
	button.custom_minimum_size.y = 72
	feedback(button)
