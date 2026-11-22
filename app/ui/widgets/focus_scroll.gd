extends ScrollContainer
## The gutter belongs to the scrollable content, not the viewport's panel.
## Follow the painted focus bounds rather than Godot's unscaled layout rect.
const FocusEffect = preload("res://app/ui/theme/focus_effect.gd")
const GUTTER := 22 # Focus growth + halo + a small reveal margin.
var _reveal_queued := false

func _ready() -> void:
	follow_focus = false
	scroll_deadzone = 12
	vertical_scroll_mode = SCROLL_MODE_SHOW_NEVER
	get_viewport().gui_focus_changed.connect(_focus_changed)
	resized.connect(queue_reveal)
	get_v_scroll_bar().changed.connect(queue_reveal)
	get_h_scroll_bar().changed.connect(queue_reveal)
	queue_reveal()

static func padding() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, GUTTER)
	return margin

func _focus_changed(control: Control) -> void:
	if control != null and is_ancestor_of(control): queue_reveal()

func queue_reveal() -> void:
	if _reveal_queued or not is_inside_tree(): return
	var target := get_viewport().gui_get_focus_owner()
	if target == null or not is_ancestor_of(target): return
	_reveal_queued = true
	# Opening a sheet, changing page, or refocusing after a render can all queue a container sort.
	get_tree().process_frame.connect(_reveal_focus, CONNECT_ONE_SHOT)

func _reveal_focus() -> void:
	_reveal_queued = false
	if not is_inside_tree() or not is_visible_in_tree(): return
	var target := get_viewport().gui_get_focus_owner()
	if target == null or not target.is_visible_in_tree() or not is_ancestor_of(target): return
	var bounds := FocusEffect.visual_rect(target, self)
	if horizontal_scroll_mode != SCROLL_MODE_DISABLED:
		var dx := _reveal_delta(bounds.position.x, bounds.end.x, size.x)
		if dx != 0: scroll_horizontal += dx
	if vertical_scroll_mode != SCROLL_MODE_DISABLED:
		var dy := _reveal_delta(bounds.position.y, bounds.end.y, size.y)
		if dy != 0: scroll_vertical += dy

static func _reveal_delta(start: float, end: float, extent: float) -> int:
	if start < 1.0: return floori(start - 1.0)
	if end > extent - 1.0: return ceili(end - extent + 1.0)
	return 0
