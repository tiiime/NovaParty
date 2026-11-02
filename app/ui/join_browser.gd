extends VBoxContainer
signal selected(room: Dictionary)
signal refresh_requested
signal manual_requested
signal scan_requested
const Style = preload("party_theme.gd")
var message: Label
var list: VBoxContainer
var refresh: Button
var manual: Button
var items := []
var search_elapsed := 0.0
func _ready() -> void:
	add_theme_constant_override("separation", 14)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 240
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	refresh = Button.new()
	Style.button(refresh, true)
	refresh.text = "SEARCH_AGAIN"
	add_child(refresh)
	refresh.pressed.connect(func(): refresh_requested.emit())
	var scan := Button.new()
	Style.button(scan)
	scan.text = "SCAN_TO_JOIN"
	add_child(scan)
	scan.pressed.connect(func(): scan_requested.emit())
	manual = Button.new()
	Style.button(manual, true)
	manual.text = "MANUAL_JOIN"
	add_child(manual)
	manual.pressed.connect(func(): manual_requested.emit())
	populate([])
func populate(rooms: Array) -> void:
	items = rooms
	search_elapsed = 0.0
	if not is_instance_valid(list):
		return
	var focus := get_viewport().gui_get_focus_owner()
	var key: String = str(focus.get_meta("room_key", "")) if focus != null else ""
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	message.text = "SEARCHING_GAMES" if rooms.is_empty() else "NEARBY_GAMES"
	for room in rooms:
		var button := Button.new()
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text = str(room.name) + "  ·  " + str(room.version) + "\n" + str(room.source_name)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_meta("room_key", room.key)
		Style.button(button)
		button.custom_minimum_size.y = 92
		list.add_child(button)
		button.pressed.connect(func(): selected.emit(room))
		if room.key == key:
			button.grab_focus()
func focus_default() -> void:
	if list.get_child_count() > 0:
		list.get_child(0).grab_focus()
	else:
		refresh.grab_focus()

func _process(delta: float) -> void:
	if is_visible_in_tree() and items.is_empty() and message.text == "SEARCHING_GAMES":
		search_elapsed += delta
		if search_elapsed >= 5:
			message.text = "NO_NEARBY_GAMES"
