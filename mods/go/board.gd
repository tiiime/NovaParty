extends Control
signal chosen(index: int)
signal escape_requested

const COLS := 9
const POINTS := COLS * COLS
const INK := Color("644333")
const BLUE := Color("2859ca")
var cursor := 40
var cells := []
var last := []
var dead := {}
var step := 1.0
var origin := Vector2.ZERO
var tray := Rect2()

func _ready() -> void:
	focus_mode = FOCUS_ALL
	custom_minimum_size = Vector2(160, 160)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

func apply_view(state: Dictionary) -> void:
	cells = state.get("board", [])
	last = state.get("last", [])
	dead.clear()
	for point in state.get("dead", []): dead[int(point)] = true
	accessibility_name = "围棋棋盘" if TranslationServer.get_locale().begins_with("zh") else "Go board"
	queue_redraw()

func _geometry() -> void:
	step = maxf(1.0, (minf(size.x, size.y) - 12.0) / (COLS + .36))
	var span := Vector2.ONE * (COLS - 1) * step
	origin = (size - span) / 2.0
	tray = Rect2(origin, span).grow(step * .68)

@warning_ignore("integer_division")
func _pos(index: int) -> Vector2:
	return origin + Vector2(index % COLS, index / COLS) * step

func _draw() -> void:
	_geometry()
	var tile := StyleBoxFlat.new()
	tile.bg_color = Color("e5b87d")
	tile.border_color = Color("956944")
	tile.set_corner_radius_all(clampi(roundi(step * .33), 6, 18))
	tile.set_border_width_all(2)
	tile.shadow_color = Color(0.32, 0.20, 0.10, .23)
	tile.shadow_size = 4
	tile.shadow_offset = Vector2(0, 3)
	draw_style_box(tile, tray)
	for axis in range(COLS):
		draw_line(_pos(axis * COLS), _pos(axis * COLS + COLS - 1), INK, 1.4, true)
		draw_line(_pos(axis), _pos(POINTS - COLS + axis), INK, 1.4, true)
	for index in [20, 24, 40, 56, 60]: draw_circle(_pos(index), step * .06, INK, true, -1, true)
	for index in range(cells.size()):
		if int(cells[index]) != 0: _piece(index, int(cells[index]), dead.has(index))
	if last.size() > 1 and int(last[1]) >= 0 and int(cells[int(last[1])]) != 0:
		var p := _pos(int(last[1]))
		var tint := Color("ffdf8a") if int(cells[int(last[1])]) > 0 else INK
		if not dead.has(int(last[1])): draw_circle(p, step * .14, tint, false, 2.0, true)
	if has_focus():
		var p := _pos(cursor)
		var box := Rect2(p - Vector2.ONE * step * .48, Vector2.ONE * step * .96)
		draw_rect(box, Color("fff4da"), false, 5.0)
		draw_rect(box, BLUE, false, 2.3)

func _piece(index: int, value: int, removed: bool) -> void:
	var p := _pos(index)
	var r := step * .424
	var edge := Color("17191d") if value > 0 else Color("756c5e")
	var fill := Color("292c36") if value > 0 else Color("fff9ed")
	if removed:
		fill.a = .48
		edge.a = .62
	else: draw_circle(p + Vector2(0, step * .06), r, edge.darkened(.2), true, -1, true)
	draw_circle(p, r, fill, true, -1, true)
	draw_circle(p, r, edge, false, 1.7, true)
	if removed:
		draw_line(p - Vector2(r, r) * .55, p + Vector2(r, r) * .55, BLUE, 2.5, true)
		draw_line(p + Vector2(-r, r) * .55, p + Vector2(r, -r) * .55, BLUE, 2.5, true)

@warning_ignore("integer_division")
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_geometry()
		var cell := Vector2i(((event.position - origin) / step).round())
		if cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < COLS:
			cursor = cell.y * COLS + cell.x
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
	var next := Vector2i(cursor % COLS, cursor / COLS) + delta
	if next.x >= 0 and next.x < COLS and next.y >= 0 and next.y < COLS:
		cursor = next.y * COLS + next.x
		queue_redraw()
	elif delta.x > 0 or delta.y > 0: escape_requested.emit()
	accept_event()
