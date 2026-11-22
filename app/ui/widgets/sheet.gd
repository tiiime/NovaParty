extends Control
signal confirmed
const Style = preload("res://app/ui/theme/party_theme.gd")
const T = Style.T
var tween: Tween
var panel: PanelContainer
var scroll: ScrollContainer
var content: MarginContainer
var done: Button
var desired_size := Vector2(492, 620)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(T.SCRIM, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.sheet())
	add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	stack.add_child(scroll)
	content = MarginContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	done = Button.new()
	done.text = "CLOSE"
	done.set_meta("sound_cue", "back")
	Style.button(done, "primary")
	stack.add_child(done)
	done.pressed.connect(close)
	resized.connect(_layout)
	hide()

func add_content(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(control)

# Reserve space inside the clipping viewport for focus rings and scaled controls.
func set_content_gutter(gutter: int) -> void:
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, gutter)
	# Godot's follow_focus only reveals the unscaled control, not its focus outline.
	scroll.follow_focus = false

func reveal(control: Control) -> void:
	if not is_inside_tree(): return
	# Wait for the panel and scrolling containers to finish sorting after opening.
	await get_tree().process_frame
	if not is_inside_tree() or not visible or not is_instance_valid(control) or not control.has_focus(): return
	# Use the largest steady focus scale, even if the motion tween hasn't settled.
	var box := control.get_global_rect().grow_individual(0, 2, 0, 2)
	var clip := scroll.get_global_rect().grow(-10)
	if box.position.y < clip.position.y: scroll.scroll_vertical -= ceili(clip.position.y - box.position.y)
	elif box.end.y > clip.end.y: scroll.scroll_vertical += ceili(box.end.y - clip.end.y)

func get_ok_button() -> Button:
	return done

func popup_centered(target: Vector2i) -> void:
	desired_size = target
	show()
	_layout()
	# Sheets rise a few units and settle; skipped with reduced motion.
	var feedback = _feedback()
	if tween != null: tween.kill()
	if feedback != null and not feedback.reduced_motion() and is_inside_tree():
		var rest := panel.position
		panel.position = rest + Vector2(0, 24)
		panel.modulate.a = 0.0
		tween = create_tween().set_parallel()
		tween.tween_property(panel, "position", rest, T.MOTION_SHEET).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "modulate:a", 1.0, T.MOTION_SHEET * 0.6)
	else:
		panel.modulate.a = 1.0

func _feedback():
	var node: Node = self
	while node != null:
		if node.has_meta("ui_feedback"): return node.get_meta("ui_feedback")
		node = node.get_parent()
	return null

func _layout() -> void:
	if not panel:
		return
	var inset := Vector2(24, 24)
	var host := get_parent().get_parent()
	if host is Control:
		var margins = host.get("content_margin")
		if margins is MarginContainer:
			inset.x = maxf(margins.get_theme_constant("margin_left"), margins.get_theme_constant("margin_right"))
			inset.y = maxf(margins.get_theme_constant("margin_top"), margins.get_theme_constant("margin_bottom"))
	var available := (size - inset * 2).max(Vector2(260, 220))
	if tween != null and tween.is_running():
		tween.kill()
		panel.modulate.a = 1.0
	panel.size = desired_size.min(available)
	panel.position = (size - panel.size) / 2

func close() -> void:
	hide()
	confirmed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		var host := get_parent().get_parent()
		if host.has_method("_top_modal") and host._top_modal() != self: return
		close()
		get_viewport().set_input_as_handled()
