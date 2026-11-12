extends Control
# A lightweight canvas halo and short scale tweens; no bloom/postprocessing needed on TV.
const T = preload("res://app/ui/theme/tokens.gd")
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
	var radius := int(button.get_meta("focus_radius", T.RADIUS_BUTTON))
	glow.set_corner_radius_all(radius + 3)
	inset = StyleBoxFlat.new()
	inset.bg_color = Color.TRANSPARENT
	inset.draw_center = false
	inset.border_color = T.FOCUS_INNER
	inset.set_border_width_all(2)
	inset.set_corner_radius_all(radius - 1)
	outline = StyleBoxFlat.new()
	outline.draw_center = false
	outline.border_color = T.FOCUS_OUTLINE
	outline.set_border_width_all(2)
	outline.set_corner_radius_all(radius + 6)
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
		if feedback != null:
			feedback.play(str(button.get_meta("sound_cue", "confirm")))
			feedback.haptic(str(button.get_meta("haptic", "tap")))
		# The stylebox already sinks the face by the lip; cards add a small squeeze.
		if button.get_meta("press_scale", true): _animate(Vector2.ONE * 0.985, T.MOTION_PRESS)
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
	var amount: float = (T.FOCUS_CARD_SCALE if button.get_meta("focus_card", false) else T.FOCUS_BUTTON_SCALE) if button.has_focus() else T.FOCUS_HOVER_SCALE
	_animate(Vector2.ONE * amount if active else Vector2.ONE, T.MOTION_FOCUS)
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
	var pulse := 0.0 if _reduced() else sin(phase * TAU * T.FOCUS_HALO_HZ) * 0.5 + 0.5
	for spread in [9, 7, 5]:
		glow.border_color = Color(1.0, 0.49, 0.06, (0.12 + pulse * 0.10) * (12.0 - spread) / 7.0)
		draw_style_box(glow, Rect2(Vector2.ZERO, size).grow(spread))
	if button.has_focus():
		draw_style_box(outline, Rect2(Vector2.ZERO, size).grow(5))
		draw_style_box(inset, Rect2(Vector2.ONE, size - Vector2.ONE * 2))
