extends Control
signal place(x: int, y: int)
signal focus_actions
const UI = preload("ui.gd")
var cells := []
var active := false
var cursor := Vector2i(7, 7)
var board_color := Color("d8b477")
var last_move := -1
var winning_line: Array = []

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func grid_rect() -> Rect2:
	var extent := minf(size.x, size.y)
	var margin := maxf(18, extent * 0.065)
	return Rect2(Vector2((size.x - extent) / 2 + margin, (size.y - extent) / 2 + margin), Vector2.ONE * (extent - margin * 2))

func cell_center(index: int) -> Vector2:
	var grid := grid_rect()
	return grid.position + Vector2(index % 15, int(index / 15)) * grid.size.x / 14

func _draw() -> void:
	var extent := minf(size.x, size.y)
	if extent < 20:
		return
	var origin := Vector2((size.x - extent) / 2, (size.y - extent) / 2)
	var surface := UI.box(board_color, 22, board_color.darkened(.22), 2)
	surface.shadow_color = Color(0.12, 0.19, 0.29, 0.12)
	surface.shadow_size = 6
	surface.shadow_offset = Vector2(0, 4)
	draw_style_box(surface, Rect2(origin, Vector2.ONE * extent))
	var grid := grid_rect()
	var step := grid.size.x / 14
	var ink := board_color.darkened(.43)
	for i in range(15):
		var line := i * step
		draw_line(grid.position + Vector2(0, line), grid.position + Vector2(grid.size.x, line), ink, 1, true)
		draw_line(grid.position + Vector2(line, 0), grid.position + Vector2(line, grid.size.y), ink, 1, true)
	for point in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(7, 7), Vector2i(3, 11), Vector2i(11, 11)]:
		draw_circle(cell_center(point.y * 15 + point.x), maxf(2, step * .075), ink, true, -1, true)
	for index in range(cells.size()):
		if cells[index] == -1:
			continue
		var point := cell_center(index)
		var radius := step * .43
		draw_circle(point + Vector2(0, step * .065), radius, Color(0.1, 0.17, 0.25, .23), true, -1, true)
		draw_circle(point, radius, Color("1e2c40") if cells[index] == 0 else Color("fffdf5"), true, -1, true)
		draw_circle(point + Vector2(-radius * .23, -radius * .28), radius * .30, Color("4e5b6b") if cells[index] == 0 else Color.WHITE, true, -1, true)
		if index == last_move:
			draw_circle(point, radius * .22, Color("63d5f0") if cells[index] == 0 else UI.BLUE, true, -1, true)
	if winning_line.size() >= 5:
		# All winning stones receive a ring, including an overline.
		for index in winning_line:
			draw_arc(cell_center(int(index)), step * .46, 0, TAU, 32, Color("18a989"), 3, true)
	if has_focus() and winning_line.is_empty():
		var point := cell_center(cursor.y * 15 + cursor.x)
		draw_style_box(UI.box(Color(0.2, .7, 1, .10), 6, Color("087eac"), 3), Rect2(point - Vector2.ONE * step * .48, Vector2.ONE * step * .96))

func _gui_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var point := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
	elif event is InputEventScreenTouch and event.pressed:
		point = event.position
	if point.x >= 0:
		var grid := grid_rect()
		var step := grid.size.x / 14
		var hit := grid.grow(step * .48)
		if hit.has_point(point):
			cursor = Vector2i(clampi(roundi((point.x - grid.position.x) / step), 0, 14), clampi(roundi((point.y - grid.position.y) / step), 0, 14))
			grab_focus()
			if active and (cells.is_empty() or cells[cursor.y * 15 + cursor.x] == -1):
				place.emit(cursor.x, cursor.y)
			queue_redraw()
			accept_event()
		return
	var handled := true
	if event.is_action_pressed("ui_left"):
		cursor.x = maxi(0, cursor.x - 1)
	elif event.is_action_pressed("ui_right"):
		if cursor.x == 14:
			focus_actions.emit()
		else:
			cursor.x += 1
	elif event.is_action_pressed("ui_up"):
		cursor.y = maxi(0, cursor.y - 1)
	elif event.is_action_pressed("ui_down"):
		cursor.y = mini(14, cursor.y + 1)
	elif event.is_action_pressed("ui_accept"):
		if active and (cells.is_empty() or cells[cursor.y * 15 + cursor.x] == -1):
			place.emit(cursor.x, cursor.y)
	else:
		handled = false
	if handled:
		queue_redraw()
		accept_event()
