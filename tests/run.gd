extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Room = preload("res://sdk/room.gd")
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
			check(commands.size() == 2, "physical mouse still works")
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
	print("RULES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func cmd(id: String, revision: int, action: Dictionary) -> Dictionary:
	return {"type": "command", "request_id": id, "expected_revision": revision, "action": action}
