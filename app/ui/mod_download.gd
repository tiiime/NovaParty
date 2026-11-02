extends Control
signal confirmed
signal canceled
const Style = preload("party_theme.gd")
var panel: PanelContainer
var title: Label
var detail: Label
var bar: ProgressBar
var confirm: Button
var cancel: Button
var working := false
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.08, 0.24, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.pill(Color.WHITE, 24))
	add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	title = Label.new()
	title.text = "DOWNLOAD_GAME_TITLE"
	title.add_theme_font_size_override("font_size", 28)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	detail = Label.new()
	detail.size_flags_horizontal = SIZE_EXPAND_FILL
	detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(detail)
	bar = ProgressBar.new()
	stack.add_child(bar)
	confirm = Button.new()
	confirm.text = "DOWNLOAD_AND_JOIN"
	Style.button(confirm)
	stack.add_child(confirm)
	confirm.pressed.connect(func():
		if not working:
			working = true
			confirm.hide()
			bar.show()
			confirmed.emit()
	)
	cancel = Button.new()
	cancel.text = "CANCEL"
	Style.button(cancel, true)
	stack.add_child(cancel)
	cancel.pressed.connect(func(): canceled.emit())
	resized.connect(_layout)
	panel.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	hide()
func ask(text: String) -> void:
	working = false
	detail.text = text
	confirm.show()
	bar.hide()
	bar.value = 0
	show()
	_layout()
	_layout.call_deferred()
	cancel.grab_focus()
func update_progress(received: int, total: int) -> void:
	bar.value = 100.0 * received / total
func _layout() -> void:
	if is_instance_valid(panel):
		panel.size = Vector2(540, 560).min(size - Vector2(48, 80))
		panel.position = (size - panel.size) / 2
