extends Control
var participants := []
var known := {}
var impulses := {}
var time := 0.0
var reduced_motion := false
const COLORS = [Color("fff6ea"), Color("ffc8ad"), Color("d5c6ff"), Color("b8ebdd")]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_players(value: Array) -> void:
	participants = value
	var live := {}
	for player in value:
		var key: String = str(player.seat) + ":" + str(player.generation)
		live[key] = true
		if known.has(key) and player.count > known[key]:
			impulses[key] = time
		known[key] = player.count
	for key in known.keys():
		if not live.has(key):
			known.erase(key)
			impulses.erase(key)
	queue_redraw()

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func lanes() -> Array:
	var result := []
	var count := participants.size()
	var columns := 1 if count <= 1 else 2
	var rows := 2 if count > 2 else 1
	for i in range(count):
		result.append(Rect2(Vector2((i % columns) * size.x / columns, (i / columns) * size.y / rows), size / Vector2(columns, rows)))
	return result

func _draw() -> void:
	draw_style_box(_box(Color("dcf3ff")), Rect2(Vector2.ZERO, size))
	draw_circle(Vector2(size.x * 0.88, size.y * 0.14), minf(size.x, size.y) * 0.06, Color("ffe883"))
	var ground := Rect2(0, size.y * 0.83, size.x, size.y * 0.17)
	draw_style_box(_box(Color("bce9d2")), ground)
	var regions := lanes()
	for i in range(participants.size()):
		var region: Rect2 = regions[i]
		if i % 2 == 1:
			draw_line(region.position + Vector2(0, 24), region.position + Vector2(0, region.size.y - 24), Color("b7dce9"), 2)
		var player: Dictionary = participants[i]
		var key: String = str(player.seat) + ":" + str(player.generation)
		var age: float = time - float(impulses.get(key, -10.0))
		var hop := sin(clampf(age / 0.55, 0, 1) * PI) if age < 0.55 else 0.0
		var scale_value := minf(region.size.x / 300, region.size.y / 480)
		var base := region.position + region.size * Vector2(0.5, 0.70)
		draw_set_transform(base, 0, Vector2.ONE * scale_value)
		_ellipse(Vector2(0, 20), Vector2(66 - 12 * hop, 9), Color("93c9b5"))
		draw_set_transform(base + Vector2(0, -48 * hop * scale_value if not reduced_motion else 0.0), 0, Vector2.ONE * scale_value)
		_animal(int(player.seat), hop, age)
		draw_set_transform(Vector2.ZERO)
		_centered(str(player.count), region.position + Vector2(region.size.x / 2, region.size.y * 0.19), int(clampf(region.size.y * 0.13, 32, 72)))
		_centered(str(player.nickname), region.position + Vector2(region.size.x / 2, region.size.y * 0.92), 21, region.size.x - 24)

func _animal(seat: int, hop: float, age: float) -> void:
	var fill: Color = COLORS[posmod(seat - 1, COLORS.size())]
	var rope := PackedVector2Array()
	var phase := clampf(age / 0.55, 0, 1) * TAU
	for i in range(33):
		var t := PI * i / 32
		rope.append(Vector2(-104 * cos(t), -54 + 114 * sin(t) * cos(phase)))
	draw_polyline(rope, Color("e59a68"), 5, true)
	if seat % 2 == 1:
		_ellipse(Vector2(-24, -157), Vector2(17, 48), fill)
		_ellipse(Vector2(24, -157), Vector2(17, 48), fill)
		_ellipse(Vector2(-24, -159), Vector2(7, 31), Color("ffc4c4"))
		_ellipse(Vector2(24, -159), Vector2(7, 31), Color("ffc4c4"))
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-56, -118), Vector2(-53, -170), Vector2(-15, -132)]), fill)
		draw_colored_polygon(PackedVector2Array([Vector2(56, -118), Vector2(53, -170), Vector2(15, -132)]), fill)
	_ellipse(Vector2(0, -46), Vector2(55, 60 - hop * 3), fill)
	_ellipse(Vector2(0, -104), Vector2(63, 51), fill)
	_ellipse(Vector2(-36, 5), Vector2(25, 13), fill)
	_ellipse(Vector2(36, 5), Vector2(25, 13), fill)
	draw_line(Vector2(-42, -61), Vector2(-98, -54), fill, 19, true)
	draw_line(Vector2(42, -61), Vector2(98, -54), fill, 19, true)
	draw_circle(Vector2(-22, -112), 4.5, Color("18395e"))
	draw_circle(Vector2(22, -112), 4.5, Color("18395e"))
	draw_circle(Vector2(-39, -95), 9, Color("ffb6b6"))
	draw_circle(Vector2(39, -95), 9, Color("ffb6b6"))
	draw_arc(Vector2(0, -103), 12, 0.25, PI - 0.25, 16, Color("18395e"), 3, true)

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(48):
		var angle := TAU * i / 48
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)

func _centered(value: String, point: Vector2, font_size: int, width: float = -1) -> void:
	var font := get_theme_default_font()
	var text_value := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if width > 0 and text_value.x > width:
		while value.length() > 1 and font.get_string_size(value + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			value = value.left(value.length() - 1)
		value += "…"
		text_value = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, point - Vector2(text_value.x / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("18395e"))

func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(26)
	return box
