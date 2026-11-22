extends "res://app/ui/widgets/sheet.gd"
signal chosen(role: String, password: String)
const PASSWORD_LIMIT := 64
var heading: Label
var details: Label
var error_label: Label
var password_field: LineEdit
var roles: HBoxContainer
var play_role: Button
var watch_role: Button
var primary: Button
var watch_action: Button
var creating := false
var role := "player"

func _ready() -> void:
	super._ready()
	done.text = "CANCEL"
	Style.button(done, "secondary", T.BUTTON_HEIGHT_SMALL)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	add_content(stack)
	heading = _label(stack, T.FONT_SIZE_TITLE)
	details = _label(stack, T.FONT_SIZE_META)
	roles = HBoxContainer.new()
	roles.add_theme_constant_override("separation", 12)
	stack.add_child(roles)
	play_role = _button(roles, "ROOM_PLAY_ROLE", "secondary")
	watch_role = _button(roles, "SPECTATE_ONLY", "secondary")
	var group := ButtonGroup.new()
	for button in [play_role, watch_role]:
		button.toggle_mode = true
		button.button_group = group
	play_role.pressed.connect(func(): _select("player"))
	watch_role.pressed.connect(func(): _select("spectator"))
	password_field = LineEdit.new()
	password_field.secret = true
	password_field.max_length = PASSWORD_LIMIT
	password_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	password_field.custom_minimum_size.y = T.HIT_MIN
	stack.add_child(password_field)
	password_field.text_changed.connect(func(_text): _refresh_buttons())
	password_field.text_submitted.connect(func(_text):
		if not primary.disabled and primary.visible: primary.grab_focus()
	)
	error_label = _label(stack, T.FONT_SIZE_META)
	error_label.add_theme_color_override("font_color", T.DANGER)
	var footer := panel.get_child(0)
	primary = _button(footer, "START_GAME", "primary")
	footer.move_child(primary, done.get_index())
	primary.pressed.connect(func(): _submit(role))
	watch_action = _button(footer, "SPECTATE_ONLY", "secondary")
	footer.move_child(watch_action, done.get_index())
	watch_action.flat = true
	watch_action.pressed.connect(func(): _submit("spectator"))
	visibility_changed.connect(func():
		if not visible: password_field.clear()
	)

func _label(parent: Control, extent: int) -> Label:
	var item := Style.label(Label.new(), extent)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func _button(parent: Control, key: String, kind: String) -> Button:
	var item := Button.new()
	item.text = key
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = SIZE_EXPAND_FILL
	Style.button(item, kind, T.BUTTON_HEIGHT_SMALL)
	parent.add_child(item)
	return item

func create_prompt(can_watch: bool) -> void:
	creating = true
	heading.text = "CREATE_ROOM"
	roles.visible = can_watch
	password_field.show()
	password_field.placeholder_text = tr("ROOM_PASSWORD_OPTIONAL")
	password_field.accessibility_name = tr("ROOM_PASSWORD_OPTIONAL")
	error_label.hide()
	watch_action.hide()
	primary.text = "CREATE_ROOM"
	_select("player")
	popup_centered(Vector2i(590, 560))
	(primary if not can_watch else play_role).grab_focus()

func join_prompt(player_available: bool, spectator_available: bool, locked: bool, game: String, error: String = "") -> void:
	creating = false
	heading.text = game
	var role_help := tr("ROOM_PLAYER_FULL_WATCH") if not player_available else tr("ROOM_CHOOSE_JOIN_ROLE") if spectator_available else ""
	details.text = (tr("ROOM_PASSWORD_REQUIRED") + "\n" if locked else "") + role_help
	details.text = details.text.strip_edges()
	roles.hide()
	password_field.visible = locked
	password_field.placeholder_text = tr("ROOM_PASSWORD")
	password_field.accessibility_name = tr("ROOM_PASSWORD")
	error_label.text = error
	error_label.visible = not error.is_empty()
	role = "player" if player_available else "spectator"
	primary.text = "JOIN_GAME" if role == "player" else "SPECTATE_ONLY"
	watch_action.visible = role == "player" and spectator_available
	_refresh_buttons()
	popup_centered(Vector2i(560, 540))
	(password_field if locked else primary).grab_focus()

func _select(value: String) -> void:
	role = value
	play_role.set_pressed_no_signal(role == "player")
	watch_role.set_pressed_no_signal(role == "spectator")
	details.text = "ROOM_HOST_WATCH_HELP" if role == "spectator" else "ROOM_PUBLIC_HELP"
	_refresh_buttons()

func _refresh_buttons() -> void:
	var missing := not creating and password_field.visible and password_field.text.is_empty()
	primary.disabled = missing
	watch_action.disabled = missing

func _submit(value: String) -> void:
	var password := password_field.text
	if not creating and password_field.visible and password.is_empty(): return
	hide()
	chosen.emit(value, password)
