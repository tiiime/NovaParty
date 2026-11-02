extends PanelContainer
signal dismissed
const Style = preload("party_theme.gd")
var image: TextureRect
var caption: Label
var done: Button
func _ready() -> void:
	add_theme_stylebox_override("panel", Style.pill(Color.WHITE, 24))
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 12)
	add_child(stack)
	caption = Label.new()
	caption.text = "INVITE_SCAN"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(caption)
	image = TextureRect.new()
	image.custom_minimum_size = Vector2(220, 220)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stack.add_child(image)
	done = Button.new()
	done.text = "HIDE_JOIN_QR"
	Style.button(done, true)
	stack.add_child(done)
	done.pressed.connect(func(): hide(); dismissed.emit())
