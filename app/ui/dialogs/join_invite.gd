extends "res://app/ui/widgets/sheet.gd"
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
	_caption(stack, "INVITE_SCAN", T.FONT_SIZE_META, T.FONT_WEIGHT_BODY, T.MUTED)
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

func present(texture: Texture2D, info: Dictionary) -> void:
	var address := str(info.address)
	address_text = ("[" + address + "]" if address.contains(":") else address) + ":" + str(int(info.port))
	image.texture = texture
	image.visible = texture != null
	endpoint.text = address_text
	copy_button.text = "INVITE_COPY"
	popup_centered(Vector2i(500, 624))
	done.grab_focus()
