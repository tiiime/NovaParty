extends Control
signal command(action: Dictionary)
signal platform_action(action: String)
const UI = preload("ui.gd")
const Stage = preload("stage.gd")
const Motion = preload("motion.gd")
var stage
var session_services
var invite_panel: PanelContainer
var invite_image: TextureRect
var motion = Motion.new()
var title: Label
var hint: Label
var status: Label
var meter: ProgressBar
var buttons: VBoxContainer
var display_button: Button
var controller_button: Button
var calibrate_button: Button
var role_button: Button
var reconnect_button: Button
var exit_button: Button
var snapshot := {}
var platform := {"connected": true, "can_reconnect": false}
var texts := {}
var local_count := 0
var generation := -1
var role := "none"
var last_send := -10000
var last_sent_count := -1
var pending_role := ""
var sensor_time := 0.0
var suspended := false

func _ready() -> void:
	custom_minimum_size = Vector2(280, 480)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	stage = Stage.new()
	add_child(stage)
	invite_panel = PanelContainer.new()
	invite_panel.add_theme_stylebox_override("panel", UI.box(Color.WHITE, 20))
	invite_panel.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(invite_panel)
	var invite_stack := VBoxContainer.new()
	invite_panel.add_child(invite_stack)
	var invite_title := Label.new()
	invite_title.name = "InviteTitle"
	invite_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	invite_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_stack.add_child(invite_title)
	invite_image = TextureRect.new()
	invite_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	invite_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	invite_image.texture_filter = TEXTURE_FILTER_NEAREST
	invite_image.size_flags_vertical = SIZE_EXPAND_FILL
	invite_stack.add_child(invite_image)
	invite_panel.hide()
	title = _label(30)
	hint = _label(22)
	status = _label(17)
	meter = ProgressBar.new()
	meter.max_value = 8
	meter.show_percentage = false
	meter.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(meter)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	display_button = _button("display", func(): _choose_role("display"), true)
	controller_button = _button("controller", func(): _choose_role("controller"), true)
	calibrate_button = _button("calibrate", func(): motion.reset())
	role_button = _button("change_role", func(): _choose_role("none"))
	reconnect_button = _button("reconnect", func(): platform_action.emit("reconnect"))
	_button("settings", func(): platform_action.emit("settings"))
	exit_button = _button("exit", func(): platform_action.emit("exit"))
	resized.connect(_layout)
	_layout()
	_refresh()

func _label(font_size: int) -> Label:
	var item := Label.new()
	item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", UI.INK)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(item)
	return item

func _button(key: String, callback: Callable, primary: bool = false) -> Button:
	var item := Button.new()
	item.name = key
	item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	UI.button(item, primary)
	buttons.add_child(item)
	item.pressed.connect(callback)
	return item

func _t(key: String) -> String:
	var language := "zh" if TranslationServer.get_locale().begins_with("zh") else "en"
	if texts.get("language", "") != language:
		texts = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("locale-" + language + ".json")))
		texts.language = language
	return str(texts.get(key, key))

func _own() -> Dictionary:
	if snapshot.is_empty():
		return {}
	return snapshot.view.slots[int(snapshot.seat)]

func render(value: Dictionary) -> void:
	snapshot = value
	var own := _own()
	var new_generation := int(own.generation)
	if generation != new_generation:
		generation = new_generation
		local_count = int(own.count)
		last_sent_count = -1
		motion.reset()
	role = own.role
	if role == pending_role:
		pending_role = ""
	local_count = maxi(local_count, int(own.count))
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(title):
		return
	title.text = _t("title")
	var active := _participants()
	stage.set_players(active)
	invite_panel.get_child(0).get_node("InviteTitle").text = _t("scan_join")
	invite_panel.visible = role == "display" and active.is_empty() and is_instance_valid(session_services) and session_services.has_method("get_join_qr")
	if invite_panel.visible:
		invite_image.texture = session_services.get_join_qr()
		invite_panel.visible = invite_image.texture != null
	display_button.visible = role == "none"
	controller_button.visible = role == "none"
	controller_button.disabled = not motion.available or not platform.get("connected", true)
	display_button.disabled = not platform.get("connected", true)
	calibrate_button.visible = role == "controller"
	role_button.visible = role != "none"
	reconnect_button.visible = platform.get("can_reconnect", false)
	meter.visible = role == "controller"
	for child in buttons.get_children():
		child.text = _t(str(child.name))
	if not platform.get("connected", true):
		hint.text = _t("disconnected")
	elif role == "none":
		hint.text = _t("choose")
	elif role == "display":
		hint.text = _t("waiting") if active.is_empty() else _t("playing") % active.size()
	else:
		hint.text = _t("hold_still") if not motion.calibrated else _t("jump_now")
	status.text = _t("detecting") if sensor_time < 2 and not motion.available else _t("sensor_ready") if motion.available else _t("no_sensor")
	if role == "display":
		status.text = _t("join_hint")
	_layout()

func _participants() -> Array:
	var result := []
	if snapshot.is_empty():
		return result
	for seat in range(snapshot.players.size()):
		var slot: Dictionary = snapshot.view.slots[seat]
		if slot.role == "controller" and snapshot.players[seat].connected:
			var count := int(slot.count)
			if seat == int(snapshot.seat) and platform.get("connected", true):
				count = maxi(count, local_count)
			result.append({"seat": seat, "nickname": snapshot.players[seat].nickname, "generation": slot.generation, "count": count})
	return result

func _choose_role(value: String) -> void:
	if snapshot.is_empty() or (value == "controller" and not motion.available):
		return
	pending_role = value
	command.emit({"type": "role", "role": value, "generation": generation})

func _process(delta: float) -> void:
	if suspended or not visible or not is_visible_in_tree():
		return
	sensor_time += delta
	var before: bool = motion.available
	var calibrated_before: bool = motion.calibrated
	var jumped: bool = motion.sample(Input.get_accelerometer(), delta, Time.get_ticks_msec())
	if before != motion.available or calibrated_before != motion.calibrated or (sensor_time - delta < 2 and sensor_time >= 2):
		_refresh()
	if role != "controller" or not platform.get("connected", true) or platform.get("input_paused", false):
		return
	meter.value = motion.strength
	if jumped:
		local_count += 1
		stage.set_players(_participants())
		Input.vibrate_handheld(18)
	var now := Time.get_ticks_msec()
	if not snapshot.is_empty() and local_count > int(_own().count) and (now - last_send >= 400 or local_count != last_sent_count):
		last_send = now
		last_sent_count = local_count
		command.emit({"type": "jump", "count": mini(local_count, int(_own().count) + 16), "generation": generation})

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		suspended = true
		motion.reset()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		suspended = false
		motion.reset()

func _layout() -> void:
	if not is_instance_valid(buttons):
		return
	var wide := size.x >= 850 and size.x > size.y
	var margin := 18.0
	var width := minf(310, size.x - margin * 2)
	title.position = Vector2(margin, 6)
	title.size = Vector2(size.x - margin * 2, 44)
	hint.position = Vector2(margin, 55)
	hint.size = Vector2(size.x - margin * 2, 66)
	status.position = Vector2(margin, 121)
	status.size = Vector2(size.x - margin * 2, 54)
	var visible_count := 0
	for child in buttons.get_children():
		if child.visible:
			visible_count += 1
	var height := float(visible_count * 68 - 10)
	buttons.position = Vector2(size.x - width - margin, size.y - height - margin)
	buttons.size = Vector2(width, height)
	stage.position = Vector2(margin, 182)
	stage.size = Vector2(size.x - width - margin * 3 if wide else size.x - margin * 2, maxf(80, size.y - 200 if wide else size.y - height - 214))
	if is_instance_valid(invite_panel):
		var side := minf(300, minf(stage.size.x - 32, stage.size.y - 60))
		invite_panel.size = Vector2(side, side + 44)
		invite_panel.position = stage.position + (stage.size - invite_panel.size) / 2
	meter.position = Vector2(margin, 170)
	meter.size = Vector2(stage.size.x, 9)

func wants_fullscreen() -> bool:
	return true

func set_platform_state(value: Dictionary) -> void:
	if value.get("connected", true) != platform.get("connected", true) or value.get("input_paused", false) != platform.get("input_paused", false):
		motion.reset()
	platform = value
	stage.reduced_motion = bool(value.get("reduce_motion", false))
	_refresh()

func focus_default() -> void:
	(display_button if role == "none" else exit_button).grab_focus()

func restore_platform_focus(_action: String = "") -> void:
	focus_default()

func on_command_notice(code: String) -> void:
	if code in ["controllers_full", "stale_generation", "invalid_action"]:
		pending_role = ""
		hint.text = _t(code)

func capture_view_state() -> Dictionary:
	return {"qr_visible": invite_panel.visible, "role": role, "count": local_count, "generation": generation, "sensor_available": motion.available, "sensor_calibrated": motion.calibrated, "sensor_baseline": motion.baseline, "sensor_strength": motion.strength, "participants": _participants().size()}

func restore_view_state(value: Dictionary) -> void:
	# Never restore calibration: a newly loaded detector must sample the real device.
	if int(value.get("generation", -2)) == generation:
		local_count = maxi(local_count, int(value.get("count", 0)))
	_refresh()

func set_session_services(services) -> void:
	session_services = services
	_refresh()

func controls_join_qr() -> bool:
	return is_instance_valid(session_services) and session_services.has_method("get_join_qr")
