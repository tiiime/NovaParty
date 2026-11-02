extends Control
# A lightweight canvas halo and short scale tweens; no bloom/postprocessing needed on TV.
var button: Button
var feedback
var hovered := false
var tween: Tween
var phase := 0.0
var frame_time := 0.0
var glow: StyleBoxFlat
var inset: StyleBoxFlat
var outline: StyleBoxFlat

func _ready() -> void:
	button = get_parent() as Button
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 3
	var ancestor: Node = button
	while ancestor != null:
		if ancestor.has_meta("ui_feedback"):
			feedback = ancestor.get_meta("ui_feedback")
			break
		ancestor = ancestor.get_parent()
	if feedback != null:
		feedback.preferences_changed.connect(_refresh)
	glow = StyleBoxFlat.new()
	glow.bg_color = Color.TRANSPARENT
	glow.draw_center = false
	glow.set_border_width_all(2)
	glow.set_corner_radius_all(24 if button.get_meta("focus_card", false) else 36)
	inset = StyleBoxFlat.new()
	inset.bg_color = Color.TRANSPARENT
	inset.draw_center = false
	inset.border_color = Color("fff5ce")
	inset.set_border_width_all(2)
	inset.set_corner_radius_all(23 if button.get_meta("focus_card", false) else 34)
	outline = StyleBoxFlat.new()
	outline.draw_center = false
	outline.border_color = Color("263461")
	outline.set_border_width_all(2)
	outline.set_corner_radius_all(29 if button.get_meta("focus_card", false) else 41)
	button.focus_entered.connect(func():
		_refresh()
		if feedback != null: feedback.play("move")
	)
	button.focus_exited.connect(_refresh)
	button.mouse_entered.connect(func():
		hovered = true
		_refresh()
		if feedback != null and not button.has_focus(): feedback.play("move")
	)
	button.mouse_exited.connect(func(): hovered = false; _refresh())
	button.button_down.connect(func():
		if feedback != null: feedback.play(str(button.get_meta("sound_cue", "confirm")))
		_animate(Vector2.ONE * 0.985, 0.06)
	)
	button.button_up.connect(_refresh)
	button.resized.connect(_center)
	button.visibility_changed.connect(func():
		if not button.is_visible_in_tree(): hovered = false
		_refresh()
	)
	_center()
	_refresh()

func _center() -> void:
	button.pivot_offset = button.size * 0.5
	queue_redraw()

func _active() -> bool:
	return button.is_visible_in_tree() and not button.disabled and (button.has_focus() or hovered)

func _reduced() -> bool:
	return feedback != null and feedback.reduced_motion()

func _refresh() -> void:
	if not is_instance_valid(button): return
	var active := _active()
	button.z_index = 1 if active else 0
	var amount := (1.035 if button.get_meta("focus_card", false) else 1.045) if button.has_focus() else 1.015
	_animate(Vector2.ONE * amount if active else Vector2.ONE, 0.15)
	set_process(active and not _reduced())
	phase = 0
	queue_redraw()

func _animate(target: Vector2, duration: float) -> void:
	if tween != null: tween.kill()
	if _reduced() or not button.is_visible_in_tree():
		button.scale = target
	else:
		tween = create_tween()
		tween.tween_property(button, "scale", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	phase += delta
	frame_time += delta
	if frame_time >= 1.0 / 30:
		frame_time = 0
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(button) or not _active() or glow == null: return
	var pulse := 0.0 if _reduced() else sin(phase * TAU * 0.65) * 0.5 + 0.5
	for spread in [9, 7, 5]:
		glow.border_color = Color(1.0, 0.49, 0.06, (0.12 + pulse * 0.10) * (12.0 - spread) / 7.0)
		draw_style_box(glow, Rect2(Vector2.ZERO, size).grow(spread))
	if button.has_focus():
		draw_style_box(outline, Rect2(Vector2.ZERO, size).grow(5))
		draw_style_box(inset, Rect2(Vector2.ONE, size - Vector2.ONE * 2))
