extends SceneTree
const Loader = preload("res://sdk/mods/mod_loader.gd")
const Room = preload("res://sdk/session/room.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loader = Loader.new()
	for game in ["gomoku", "hidden_cards"]:
		var info: Dictionary = loader.inspect("res://mods/" + game)
		check(not info.is_empty(), "valid manifest " + game + ": " + loader.error)
		if info.is_empty():
			quit(1)
			return
		var rules = loader.rules(info)
		check(rules != null, "rules load " + game)
		if rules == null:
			quit(1)
			return
		var room = Room.new(info, rules, "host", "Host", 42)
		var hello := {"protocol": 1, "fingerprint": info.fingerprint, "player_id": "guest", "nickname": "Guest"}
		var wrong = hello.duplicate(true)
		wrong.fingerprint = "different"
		check(room.hello(wrong).code == "incompatible", "fingerprint gate")
		var welcome: Dictionary = room.hello(hello)
		check(welcome.seat == 1, "guest seat")
		check(room.hello(hello).code == "invalid_resume_token", "identity is not credential")
		room.players[1].connected = false
		hello.resume_token = welcome.resume_token
		check(room.hello(hello).seat == 1, "credential restores seat")
		check(room.hello(hello).code == "already_connected", "one live connection")
		var view_script = load(info.root.path_join(info.manifest.view))
		var view = view_script.new()
		root.add_child(view)
		view.render(room.snapshot(0))
		check(view.get_child_count() > 0, "view instantiates " + game)
		view.queue_free()
		if game == "gomoku":
			var commands := []
			view.command.connect(func(action): commands.append(action))
			view.board.size = Vector2(300, 300)
			view.board.active = true
			var touch := InputEventScreenTouch.new()
			touch.pressed = true
			touch.position = Vector2(150, 150)
			view.board._gui_input(touch)
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = true
			mouse.position = Vector2(150, 150)
			mouse.device = InputEvent.DEVICE_ID_EMULATION
			view.board._gui_input(mouse)
			check(commands.size() == 1, "touch plus emulated mouse submits once")
			mouse.device = 0
			view.board._gui_input(mouse)
			check(commands.size() == 1 and not view.board.active, "duplicate input is blocked while a move is pending")
			view.on_command_notice("occupied")
			view.board._gui_input(mouse)
			check(commands.size() == 2, "physical mouse retries after rejection")
			view.on_command_notice("occupied")
			var key := InputEventAction.new()
			key.action = "ui_right"
			key.pressed = true
			view.board._gui_input(key)
			key.action = "ui_accept"
			view.board._gui_input(key)
			check(commands.size() == 3 and commands[2].x == 8 and commands[2].y == 7, "directional move and confirm")
			var action := {"type": "place", "x": 0, "y": 0}
			check(not room.command(1, cmd("wrong-turn", 0, action)).accepted, "turn enforced")
			var request := cmd("first", 0, action)
			check(room.command(0, request).accepted, "valid move")
			check(room.command(0, request).accepted and room.revision == 1, "idempotent retry")
			check(room.command(1, cmd("old", 0, {"type": "place", "x": 0, "y": 1})).code == "stale_revision", "stale rejected")
			check(room.command(1, cmd("occupied", 1, action)).code == "occupied", "occupied rejected")
			check(room.command(1, cmd("fraction", 1, {"type": "place", "x": 1.5, "y": 1})).code == "invalid_action", "fraction rejected")
			for x in range(1, 5):
				check(room.command(1, cmd("b" + str(x), room.revision, {"type": "place", "x": x - 1, "y": 1})).accepted, "white move")
				check(room.command(0, cmd("a" + str(x), room.revision, {"type": "place", "x": x, "y": 0})).accepted, "black move")
			check(room.state.finished and room.state.winner == 0, "five wins")
		else:
			check(rules.initial_state(42) == rules.initial_state(42), "seeded reproducibility")
			var a: Dictionary = room.snapshot(0).view
			var b: Dictionary = room.snapshot(1).view
			check(not a.has("deck") and not a.has("hands") and not b.has("deck"), "private data absent")
			check(a.hand != b.hand, "different hands")
			for round_number in range(3):
				var card: int = room.state.hands[0][0]
				check(room.command(0, cmd("a" + str(round_number), room.revision, {"type": "choose", "card": card})).accepted, "first hidden choice")
				var other: Dictionary = room.snapshot(1).view
				check(other.history.size() == round_number and other.chosen == -1 and not other.has("hands"), "unrevealed choice hidden")
				check(room.command(1, cmd("steal" + str(round_number), room.revision, {"type": "choose", "card": card})).code == "card_not_owned", "ownership enforced")
				var next: int = room.state.hands[1][0]
				check(room.command(1, cmd("b" + str(round_number), room.revision, {"type": "choose", "card": next})).accepted, "second choice")
			check(room.state.finished and room.state.history.size() == 3, "three rounds finish")
	check_spectator_manifest(loader)
	check_host_start_manifest(loader)
	print("RULES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check_spectator_manifest(loader: RefCounted) -> void:
	var base: Dictionary = loader.inspect("res://mods/gomoku")
	var manifest: Dictionary = base.manifest.duplicate(true)
	manifest.rules_files = [manifest.rules]
	manifest.files.append("alternate.gd")
	manifest.spectators = {"max_guests": 4, "view": "spectator.gd"}
	var first := inspect_fixture(loader, manifest)
	check(not first.is_empty(), "accept valid spectator declaration")
	manifest.spectators.view = "alternate.gd"
	var alternate := inspect_fixture(loader, manifest)
	check(first.get("rules_fingerprint") == alternate.get("rules_fingerprint") and first.get("presentation_fingerprint") != alternate.get("presentation_fingerprint"), "spectator entrypoint only changes presentation compatibility")
	manifest.spectators.max_guests = 8
	var larger := inspect_fixture(loader, manifest)
	check(alternate.get("rules_fingerprint") != larger.get("rules_fingerprint"), "spectator count affects room compatibility")
	for invalid in [null, true, {}, {"max_guests": 0, "view": "spectator.gd"}, {"max_guests": 9, "view": "spectator.gd"}, {"max_guests": 2.5, "view": "spectator.gd"}, {"max_guests": 4, "view": "unlisted.gd"}]:
		manifest.spectators = invalid
		check(inspect_fixture(loader, manifest).is_empty(), "reject invalid spectator declaration: " + str(invalid))
	var legacy: Dictionary = loader.inspect("res://mods/hidden_cards")
	legacy.manifest.spectators = {"max_guests": 4, "view": "view.gd"}
	check(loader.rules(legacy) == null and loader.error.ends_with("view_for_spectator"), "opt-in requires an explicit public snapshot method")

func check_host_start_manifest(loader: RefCounted) -> void:
	var base: Dictionary = loader.inspect("res://mods/gomoku")
	var manifest: Dictionary = base.manifest.duplicate(true)
	manifest.session_mode = "fixed"
	manifest.players = {"min": 3, "max": 3}
	manifest.host_start = true
	check(inspect_fixture(loader, manifest).is_empty(), "SDK 1 cannot declare the new host action")
	manifest.sdk = 2
	check(not inspect_fixture(loader, manifest).is_empty(), "SDK 2 accepts three required players and host start")
	manifest.host_start = 1
	check(inspect_fixture(loader, manifest).is_empty(), "host_start must be boolean true")
	manifest.host_start = true
	manifest.players.max = 2
	check(inspect_fixture(loader, manifest).is_empty(), "fixed maximum cannot be smaller than the minimum")
	base.manifest.host_start = true
	check(loader.rules(base) == null and loader.error.ends_with("can_start_round"), "host start requires rule hooks")

func inspect_fixture(loader: RefCounted, manifest: Dictionary) -> Dictionary:
	var path := "user://spectator-manifest-test-%d.zip" % Time.get_ticks_usec()
	var packer := ZIPPacker.new()
	if packer.open(path) != OK: return {}
	var prefix := "mods/gomoku/"
	packer.start_file(prefix + "manifest.json")
	packer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	packer.close_file()
	for file in manifest.files:
		packer.start_file(prefix + file)
		var source: PackedByteArray = FileAccess.get_file_as_bytes("res://" + prefix + file) if FileAccess.file_exists("res://" + prefix + file) else "extends Control\n".to_utf8_buffer()
		packer.write_file(source)
		packer.close_file()
	packer.close()
	var archive := ZIPReader.new()
	var result: Dictionary = {}
	if archive.open(path) == OK:
		result = loader.inspect("res://mods/gomoku", archive)
		archive.close()
	DirAccess.remove_absolute(path)
	return result

func cmd(id: String, revision: int, action: Dictionary) -> Dictionary:
	return {"type": "command", "request_id": id, "expected_revision": revision, "action": action}
