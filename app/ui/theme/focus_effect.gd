extends Control
# A thin focus ring with a soft, slightly lowered shadow; no postprocessing needed on TV.
const T = preload("res://app/ui/theme/tokens.gd")
const SHADOW_STEP := 2
const SHADOW_OFFSET := Vector2(0, 1)
const RING_SPREAD := T.FOCUS_GAP + T.FOCUS_RING
const SHADOW_SPREAD := RING_SPREAD + 2 * SHADOW_STEP
const MAX_GROWTH := 10.0 # Per edge, even for full-width buttons on TV.
var button: Button
var feedback
var hovered := false
var tween: Tween
var phase := 0.0
var frame_time := 0.0
var ring: StyleBoxFlat
var shadow: StyleBoxFlat

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
	ring = ring_box(int(button.get_meta("focus_radius", T.RADIUS_BUTTON)))
	shadow = StyleBoxFlat.new()
	shadow.draw_center = false
	shadow.set_border_width_all(SHADOW_STEP)
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

static func ring_box(radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = T.FOCUS
	box.set_border_width_all(T.FOCUS_RING)
	box.set_corner_radius_all(radius + RING_SPREAD)
	box.set_expand_margin_all(RING_SPREAD)
	box.set_content_margin_all(0)
	return box

static func _focus_scale(control: Control) -> float:
	var preferred := T.FOCUS_CARD_SCALE if control.get_meta("focus_card", false) else T.FOCUS_BUTTON_SCALE
	return _bounded_scale(control, preferred)

static func _bounded_scale(control: Control, preferred: float) -> float:
	return minf(preferred, 1.0 + 2.0 * MAX_GROWTH / maxf(1.0, maxf(control.size.x, control.size.y)))

static func visual_rect(control: Control, relative_to: Control) -> Rect2:
	var rect := Rect2(Vector2.ZERO, control.size)
	var transform := relative_to.get_global_transform_with_canvas().affine_inverse() * control.get_global_transform_with_canvas()
	if control.has_node("FocusFeedback"):
		var target_scale := _focus_scale(control)
		# Account for the current tween without waiting for it to settle.
		var ratio := (Vector2.ONE * target_scale).max(control.scale) / control.scale
		var painted := rect.grow(SHADOW_SPREAD + 1.0).merge(Rect2(SHADOW_OFFSET, control.size).grow(SHADOW_SPREAD + 1.0))
		var pivot := control.pivot_offset
		rect = Rect2(pivot + (painted.position - pivot) * ratio, painted.size * ratio)
	elif control.has_theme_stylebox("focus"):
		var ring := control.get_theme_stylebox("focus")
		if ring is StyleBoxFlat:
			rect = rect.grow_individual(maxf(0.0, ring.expand_margin_left) + 1.0, maxf(0.0, ring.expand_margin_top) + 1.0,
				maxf(0.0, ring.expand_margin_right) + 1.0, maxf(0.0, ring.expand_margin_bottom) + 1.0)
	return transform * rect

func _center() -> void:
	button.pivot_offset = button.size * 0.5
	if _active(): _refresh()
	else: queue_redraw()

func _active() -> bool:
	return button.is_visible_in_tree() and not button.disabled and (button.has_focus() or hovered)

func _reduced() -> bool:
	return feedback != null and feedback.reduced_motion()

func _refresh() -> void:
	if not is_instance_valid(button): return
	var active := _active()
	button.z_index = 1 if active else 0
	var amount := _focus_scale(button) if button.has_focus() else _bounded_scale(button, T.FOCUS_HOVER_SCALE)
	_animate(Vector2.ONE * amount if active else Vector2.ONE, T.MOTION_FOCUS)
	set_process(active and button.has_focus() and not _reduced())
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
	if not is_instance_valid(button) or not _active() or not button.has_focus() or ring == null: return
	var pulse := 0.0 if _reduced() else sin(phase * TAU * T.FOCUS_HALO_HZ) * 0.5 + 0.5
	var radius := int(button.get_meta("focus_radius", T.RADIUS_BUTTON))
	for spread in [SHADOW_SPREAD, SHADOW_SPREAD - SHADOW_STEP]:
		shadow.set_corner_radius_all(radius + spread)
		shadow.border_color = Color(T.FOCUS, (0.08 + pulse * 0.035) * (1 if spread == SHADOW_SPREAD else 2))
		draw_style_box(shadow, Rect2(SHADOW_OFFSET, size).grow(spread))
	draw_style_box(ring, Rect2(Vector2.ZERO, size))
