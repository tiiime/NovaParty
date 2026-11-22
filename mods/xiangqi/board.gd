extends Control
signal chosen(index: int)
signal escape_requested

const COLS := 9
const ROWS := 10
const POINTS := COLS * ROWS
const INK := Color("644333")
const BLUE := Color("2859ca")
const RED := Color("a12d24")
const PALE := Color("fff4da")
var cursor := 49
var selected := -1
var seat := 0
var cells := []
var last := []
var can_move := false
var step := 1.0
var origin := Vector2.ZERO
var tray := Rect2()

func _ready() -> void:
	focus_mode = FOCUS_ALL
	custom_minimum_size = Vector2(160, 172)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

func apply_view(state: Dictionary, local_seat: int, movable: bool) -> void:
	seat = local_seat
	cells = state.get("board", [])
	last = state.get("last", [])
	can_move = movable
	accessibility_name = "象棋棋盘" if TranslationServer.get_locale().begins_with("zh") else "Chinese chess board"
	queue_redraw()

func _geometry() -> void:
	step = maxf(1.0, minf((size.x - 12.0) / (COLS + .36), (size.y - 12.0) / (ROWS + .36)))
	var span := Vector2(COLS - 1, ROWS - 1) * step
	origin = (size - span) / 2.0
	tray = Rect2(origin, span).grow(step * .68)

@warning_ignore("integer_division")
func _pos(index: int) -> Vector2:
	var display := POINTS - 1 - index if seat == 1 else index
	return origin + Vector2(display % COLS, display / COLS) * step

func _draw() -> void:
	_geometry()
	var tile := StyleBoxFlat.new()
	tile.bg_color = Color("efcb90")
	tile.border_color = Color("956944")
	tile.set_corner_radius_all(clampi(roundi(step * .33), 6, 18))
	tile.set_border_width_all(2)
	tile.shadow_color = Color(0.32, 0.20, 0.10, .23)
	tile.shadow_size = 4
	tile.shadow_offset = Vector2(0, 3)
	draw_style_box(tile, tray)
	_draw_grid()
	for index in range(cells.size()):
		if int(cells[index]) != 0: _piece(index, int(cells[index]))
	for index in last:
		if int(index) >= 0: draw_circle(_pos(int(index)), step * .47, Color("9c592b"), false, 2.0, true)
	if selected >= 0 and can_move: draw_circle(_pos(selected), step * .48, BLUE, false, 3.0, true)
	if has_focus():
		var p := _pos(cursor)
		var box := Rect2(p - Vector2.ONE * step * .48, Vector2.ONE * step * .96)
		draw_rect(box, PALE, false, 5.0)
		draw_rect(box, BLUE, false, 2.3)

func _screen(x: int, y: int) -> Vector2: return origin + Vector2(x, y) * step

func _draw_grid() -> void:
	for y in range(ROWS): draw_line(_screen(0, y), _screen(COLS - 1, y), INK, 1.4, true)
	for x in range(COLS):
		if x in [0, COLS - 1]: draw_line(_screen(x, 0), _screen(x, ROWS - 1), INK, 1.4, true)
		else:
			draw_line(_screen(x, 0), _screen(x, 4), INK, 1.4, true)
			draw_line(_screen(x, 5), _screen(x, 9), INK, 1.4, true)
	for y in [0, 7]:
		draw_line(_screen(3, y), _screen(5, y + 2), INK, 1.4, true)
		draw_line(_screen(5, y), _screen(3, y + 2), INK, 1.4, true)
	_center("楚 河", origin + Vector2(2, 4.5) * step, .43, INK)
	_center("漢 界", origin + Vector2(6, 4.5) * step, .43, INK)
	for row in [2, 7]:
		for x in [1, 7]: _marks(x, row)
	for row in [3, 6]:
		for x in [0, 2, 4, 6, 8]: _marks(x, row)

func _marks(x: int, y: int) -> void:
	var p := _screen(x, y)
	for dx in [-1, 1]:
		if (dx < 0 and x == 0) or (dx > 0 and x == COLS - 1): continue
		for dy in [-1, 1]:
			var corner := p + Vector2(dx, dy) * step * .13
			draw_line(corner, corner + Vector2(dx, 0) * step * .09, INK, 1.3, true)
			draw_line(corner, corner + Vector2(0, dy) * step * .09, INK, 1.3, true)

func _center(text: String, p: Vector2, ratio: float, tint: Color) -> void:
	var font := get_theme_default_font()
	var px := maxi(10, roundi(step * ratio))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var mid := (font.get_ascent(px) - font.get_descent(px)) * .5
	draw_string(font, p + Vector2(-width / 2, mid), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, tint)

func _piece(index: int, value: int) -> void:
	var p := _pos(index)
	var r := step * .424
	var edge := RED if value > 0 else INK
	draw_circle(p + Vector2(0, step * .068), r, edge.darkened(.2), true, -1, true)
	draw_circle(p, r, Color("fff3d5"), true, -1, true)
	draw_circle(p, r, edge, false, 1.7, true)
	draw_circle(p, r * .80, edge, false, 1.0, true)
	var glyphs := ["", "帥", "仕", "相", "馬", "車", "炮", "兵"] if value > 0 else ["", "將", "士", "象", "馬", "車", "砲", "卒"]
	_center(glyphs[absi(value)], p, .49, edge)

@warning_ignore("integer_division")
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_geometry()
		var cell := Vector2i(((event.position - origin) / step).round())
		if cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS:
			cursor = cell.y * COLS + cell.x
			if seat == 1: cursor = POINTS - 1 - cursor
			grab_focus()
			chosen.emit(cursor)
			queue_redraw()
		accept_event()
		return
	var delta := Vector2i.ZERO
	if event.is_action_pressed("ui_left", true): delta.x = -1
	elif event.is_action_pressed("ui_right", true): delta.x = 1
	elif event.is_action_pressed("ui_up", true): delta.y = -1
	elif event.is_action_pressed("ui_down", true): delta.y = 1
	elif event.is_action_pressed("ui_accept"):
		chosen.emit(cursor)
		accept_event()
		return
	if delta == Vector2i.ZERO: return
	var display := POINTS - 1 - cursor if seat == 1 else cursor
	var next := Vector2i(display % COLS, display / COLS) + delta
	if next.x >= 0 and next.x < COLS and next.y >= 0 and next.y < ROWS:
		display = next.y * COLS + next.x
		cursor = POINTS - 1 - display if seat == 1 else display
		queue_redraw()
	elif delta.x > 0 or delta.y > 0: escape_requested.emit()
	accept_event()
