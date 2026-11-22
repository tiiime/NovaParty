extends "res://app/ui/widgets/sheet.gd"
signal bluetooth_requested
const Icons = preload("res://app/ui/theme/party_icons.gd")
var scan_caption: Label
var password_caption: Label
var bluetooth_button: Button
var bluetooth_status: Label
var bluetooth_room_code: Label
var image: TextureRect
var endpoint: Label
var copy_button: Button
var address_text := ""

func _ready() -> void:
	super._ready()
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	add_content(stack)
	_caption(stack, "OPEN_INVITE", T.FONT_SIZE_TITLE, T.FONT_WEIGHT_TITLE, T.INK)
	password_caption = _caption(stack, "INVITE_PASSWORD_REQUIRED", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL, T.MUTED)
	password_caption.hide()
	bluetooth_button = Button.new()
	bluetooth_button.text = "BLUETOOTH_HOST"
	bluetooth_button.icon = Icons.get_icon("bluetooth", T.SKY)
	Style.button(bluetooth_button, "secondary", T.BUTTON_HEIGHT_SMALL)
	bluetooth_button.pressed.connect(func(): bluetooth_requested.emit())
	# Keep the Bluetooth identity above the QR so it is visible on short screens.
	stack.add_child(bluetooth_button)
	bluetooth_button.hide()
	bluetooth_room_code = _caption(stack, "", T.FONT_SIZE_BODY, T.FONT_WEIGHT_LABEL, T.INK)
	bluetooth_room_code.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	bluetooth_room_code.add_theme_stylebox_override("normal", Style.banner("info"))
	bluetooth_room_code.hide()
	bluetooth_status = _caption(stack, "", T.FONT_SIZE_META, T.FONT_WEIGHT_BODY, T.MUTED)
	bluetooth_status.hide()
	scan_caption = _caption(stack, "INVITE_SCAN", T.FONT_SIZE_META, T.FONT_WEIGHT_BODY, T.MUTED)
	image = TextureRect.new()
	image.custom_minimum_size = Vector2(0, 248)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.accessibility_name = tr("INVITE_QR_LABEL")
	stack.add_child(image)
	endpoint = _caption(stack, "", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL, T.INK)
	endpoint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	endpoint.add_theme_stylebox_override("normal", Style.banner("info"))
	copy_button = Button.new()
	Style.button(copy_button, "secondary", T.BUTTON_HEIGHT_SMALL)
	copy_button.pressed.connect(func():
		DisplayServer.clipboard_set(address_text)
		copy_button.text = "INVITE_COPIED"
	)
	stack.add_child(copy_button)
	done.text = "HIDE_JOIN_QR"
	Style.button(done, "primary", T.BUTTON_HEIGHT_SMALL)

func _caption(parent: Node, key: String, extent: int, weight: int, color: Color) -> Label:
	var caption := Style.label(Label.new(), extent, weight, color)
	caption.text = key
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(caption)
	return caption

func present(texture: Texture2D, info: Dictionary, locked: bool = false) -> void:
	password_caption.visible = locked
	var address := str(info.get("address", ""))
	address_text = ("[" + address + "]" if address.contains(":") else address) + ":" + str(int(info.get("port", 0))) if not address.is_empty() else ""
	image.texture = texture
	image.visible = texture != null
	scan_caption.visible = image.visible
	endpoint.text = address_text
	endpoint.visible = not address_text.is_empty()
	copy_button.text = "INVITE_COPY"
	copy_button.visible = endpoint.visible
	popup_centered(Vector2i(500, 680 if image.visible and bluetooth_button.visible else 624 if image.visible else 300))
	scroll.scroll_vertical = 0
	done.grab_focus()

func set_bluetooth(value: bool, key: String = "", enabled: bool = true, room_code: String = "") -> void:
	bluetooth_button.visible = value
	bluetooth_button.disabled = not enabled
	bluetooth_status.text = key
	bluetooth_status.visible = value and not key.is_empty()
	bluetooth_room_code.visible = value and not room_code.is_empty()
	bluetooth_room_code.text = tr("BLUETOOTH_HOST_CODE") % room_code.to_upper() if bluetooth_room_code.visible else ""
