extends Control
signal confirmed
const Style = preload("res://app/ui/party_theme.gd")
var panel: PanelContainer
var scroll: ScrollContainer
var done: Button
var desired_size := Vector2(492, 620)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.08, 0.24, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.pill(Color.WHITE, 28))
	add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	stack.add_child(scroll)
	done = Button.new()
	done.text = "CLOSE"
	Style.button(done)
	stack.add_child(done)
	done.pressed.connect(close)
	resized.connect(_layout)
	hide()

func add_content(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(control)

func get_ok_button() -> Button:
	return done

func popup_centered(target: Vector2i) -> void:
	desired_size = target
	show()
	_layout()

func _layout() -> void:
	if not panel:
		return
	var available := size - Vector2(48, 100)
	panel.size = desired_size.min(available)
	panel.position = (size - panel.size) / 2

func close() -> void:
	hide()
	confirmed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
