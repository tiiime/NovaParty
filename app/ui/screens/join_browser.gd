extends VBoxContainer
signal selected(room: Dictionary)
signal refresh_requested
signal manual_requested
signal scan_requested
signal bluetooth_requested
const Style = preload("res://app/ui/theme/party_theme.gd")
const Icons = preload("res://app/ui/theme/party_icons.gd")
const T = Style.T
var bluetooth: Button
var message: Label
var list: VBoxContainer
var refresh: Button
var manual: Button
var scan: Button
var actions: GridContainer
var items := []
var room_buttons := {}
var search_timeout: Timer
var busy := false

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	actions = GridContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 12)
	add_child(actions)
	scan = _button(actions, "SCAN_TO_JOIN", "scan", func(): scan_requested.emit(), "accent")
	manual = _button(actions, "MANUAL_JOIN", "link", func(): manual_requested.emit())
	bluetooth = _button(actions, "BLUETOOTH_SEARCH", "bluetooth", func(): bluetooth_requested.emit())
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	add_child(heading)
	var title := Style.label(Label.new(), T.FONT_SIZE_SECTION, T.FONT_WEIGHT_TITLE)
	title.text = "NEARBY_TITLE"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	refresh = _button(heading, "SEARCH_AGAIN", "refresh", func(): refresh_requested.emit())
	refresh.size_flags_horizontal = SIZE_SHRINK_END
	refresh.add_theme_font_size_override("font_size", T.FONT_SIZE_META)
	message = Style.label(Label.new(), T.FONT_SIZE_BODY, T.FONT_WEIGHT_LABEL, T.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_stylebox_override("normal", Style.banner("info"))
	add_child(message)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	add_child(list)
	search_timeout = Timer.new()
	search_timeout.one_shot = true
	search_timeout.timeout.connect(func():
		if items.is_empty(): message.text = "NO_NEARBY_GAMES"
	)
	add_child(search_timeout)
	resized.connect(_adapt_actions)
	_adapt_actions()

func _button(parent: Node, key: String, glyph: String, callback: Callable, kind: String = "secondary") -> Button:
	var button := Button.new()
	button.text = key
	button.icon = Icons.get_icon(glyph, T.WHITE if kind == "accent" else T.SKY)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.add_theme_constant_override("h_separation", 8)
	Style.button(button, kind, T.BUTTON_HEIGHT_SMALL)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _adapt_actions() -> void:
	actions.columns = 3 if size.x >= 820 and bluetooth.visible else 2 if size.x >= 540 else 1

func set_bluetooth_available(value: bool) -> void:
	bluetooth.visible = value
	_adapt_actions()

func begin_search() -> void:
	message.text = "SEARCHING_GAMES"
	search_timeout.start(5.0)

func unavailable() -> void:
	search_timeout.stop()
	if items.is_empty(): message.text = "DISCOVERY_UNAVAILABLE"

func stop_search() -> void:
	search_timeout.stop()

func set_busy(value: bool) -> void:
	busy = value
	for button in [scan, manual, refresh, bluetooth] + room_buttons.values():
		button.disabled = value

func populate(rooms: Array) -> void:
	items = rooms
	message.visible = rooms.is_empty()
	if rooms.is_empty() and message.text.is_empty(): begin_search()
	var retained := {}
	var focused := get_viewport().gui_get_focus_owner()
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		var key := str(room.key)
		var button: Button = room_buttons.get(key)
		if button == null:
			button = Button.new()
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.icon = Icons.get_icon("bluetooth" if room.get("transport") == "ble" else "radio", T.SKY)
			button.set_meta("room_key", key)
			button.set_meta("haptic", "select")
			Style.card(button, false, T.RADIUS_BUTTON)
			button.add_theme_font_override("font", Style.font(T.FONT_WEIGHT_LABEL))
			button.custom_minimum_size.y = 88
			button.disabled = busy
			button.pressed.connect(func(): selected.emit(button.get_meta("room")))
			list.add_child(button)
		button.set_meta("room", room)
		if room.get("transport") == "ble":
			button.text = tr("BLUETOOTH_GAME") + "\n" + tr("BLUETOOTH_ROW") % str(room.get("code", "")).to_upper()
		else:
			button.text = str(room.name) + "\n" + tr("LAN_ROOM_ROW") % [str(room.source_name), str(room.version)]
		retained[key] = button
		list.move_child(button, index)
	var lost_focus := false
	for key in room_buttons:
		if not retained.has(key):
			var button: Button = room_buttons[key]
			lost_focus = lost_focus or focused == button
			list.remove_child(button)
			button.queue_free()
	room_buttons = retained
	if rooms.is_empty() and search_timeout.is_stopped() and message.text == "SEARCHING_GAMES":
		message.text = "NO_NEARBY_GAMES"
	if lost_focus and is_visible_in_tree() and not busy: focus_default()

func focus_default() -> void:
	if busy: return
	if list.get_child_count() > 0: list.get_child(0).grab_focus()
	else: scan.grab_focus()
