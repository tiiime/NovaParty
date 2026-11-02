extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Room = preload("res://sdk/room.gd")
const Motion = preload("res://mods/jump_rope/motion.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL JUMP: " + message)
func _initialize() -> void:
	call_deferred("run")
func action(room, seat: int, value: Dictionary, expected: int = -1) -> Dictionary:
	value.generation = room.state.slots[seat].generation
	return room.command(seat, {"request_id": str(Time.get_ticks_usec()), "expected_revision": room.revision if expected < 0 else expected, "action": value})
func hello(room, id: String) -> Dictionary:
	return room.hello({"protocol": 2, "rules_fingerprint": room.info.rules_fingerprint, "player_id": id, "nickname": id})
func run() -> void:
	var loader := Loader.new()
	var info := loader.inspect("res://mods/jump_rope")
	check(not info.is_empty(), "drop-in package loads")
	var room := Room.new(info, loader.rules(info), "screen", "大屏", 1)
	check(action(room, 0, {"type": "role", "role": "display"}).accepted, "display starts without controllers")
	var screen_session: String = room.game_session_id
	for i in range(1, 5):
		check(hello(room, "phone" + str(i)).seat == i, "controller joins at any time")
		check(action(room, i, {"type": "role", "role": "controller"}).accepted, "controller role")
	check(hello(room, "overflow").code == "room_full", "bounded capacity")
	check(action(room, 0, {"type": "role", "role": "controller"}).code == "controllers_full", "four-controller limit")
	var shared_revision: int = room.revision
	for seat in [1, 2, 3, 4]:
		check(action(room, seat, {"type": "jump", "count": 1}, shared_revision).accepted, "simultaneous independent counters")
	check(action(room, 1, {"type": "jump", "count": 1}).accepted and room.state.slots[1].count == 1, "absolute counter retry never double counts")
	check(not action(room, 1, {"type": "jump", "count": 0}).accepted, "counter cannot move backwards")
	check(not action(room, 1, {"type": "jump", "count": 1.5}).accepted, "integer counts")
	check(not action(room, 1, {"type": "jump", "count": 99}).accepted, "bounded delta")
	var old_generation: int = room.state.slots[1].generation
	room.set_connected(1, false)
	check(room.state.slots[1].role == "none", "disconnect immediately removes animal")
	check(action(room, 2, {"type": "jump", "count": 2}).accepted, "others keep jumping after disconnect")
	var joined := hello(room, "replacement")
	check(joined.seat == 1 and room.game_session_id == screen_session, "vacant seat reused without restarting display")
	var result := room.command(1, {"request_id": "old-packet", "expected_revision": 0, "action": {"type": "jump", "count": 3, "generation": old_generation}})
	check(result.code == "stale_generation", "old occupant cannot affect replacement")
	check(action(room, 1, {"type": "role", "role": "controller"}).accepted, "replacement can start")
	check(action(room, 1, {"type": "role", "role": "none"}).accepted and room.state.slots[1].count == 0, "change role releases animal")
	var gomoku := loader.inspect("res://mods/gomoku")
	var board_room := Room.new(gomoku, loader.rules(gomoku), "a", "a", 1)
	check(board_room.command(0, {"request_id": "blocked", "expected_revision": 0, "action": {"type": "place", "x": 0, "y": 0}}).code == "waiting_for_players", "board game semantics unchanged")
	var detector := Motion.new()
	var phantom_jump := false
	for i in range(100):
		phantom_jump = detector.sample(Vector3.ZERO, 0.02, i * 20) or phantom_jump
	check(not phantom_jump, "missing sensor produces no jumps")
	check(not detector.available and not detector.calibrated, "missing sensor stays unavailable")
	for i in range(70):
		detector.sample(Vector3(0, 9.81, 0), 0.02, i * 20)
	check(detector.calibrated, "stationary calibration")
	check(detector.sample(Vector3(0, 14, 0), 0.02, 1500), "first motion peak")
	check(not detector.sample(Vector3(0, 15, 0), 0.02, 1600), "sustained peak no duplicate")
	detector.sample(Vector3(0, 9.81, 0), 0.02, 1700)
	check(not detector.sample(Vector3(0, 14, 0), 0.02, 1750), "cooldown suppresses bounce")
	detector.sample(Vector3(0, 9.81, 0), 0.02, 1850)
	check(detector.sample(Vector3(0, 0, 14), 0.02, 1950), "orientation-independent next motion")
	var view = load(info.root.path_join(info.manifest.view)).new()
	root.size = Vector2i(1920, 1080)
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.render(room.snapshot(0))
	await process_frame
	check(view.stage.participants.size() == 3, "only active animals displayed")
	check(view.stage.lanes().size() == 3, "three-player grid")
	room.set_connected(3, false)
	room.set_connected(4, false)
	view.render(room.snapshot(0))
	check(view.stage.lanes().size() == 1 and view.stage.lanes()[0].size == view.stage.size, "solo fills stage")
	root.size = Vector2i(540, 960)
	await process_frame
	view.render(room.snapshot(0))
	await process_frame
	check(view.buttons.position.y >= 180 and view.buttons.position.y + view.buttons.size.y <= view.size.y, "phone actions within bounds")
	check(view.controller_button.disabled, "desktop sensor unavailable blocks controller")
	view.set_platform_state({"connected": true, "reduce_motion": true, "input_paused": true})
	check(view.stage.reduced_motion, "reduced motion honored")
	view.queue_free()
	await process_frame
	print("JUMP_ROPE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
