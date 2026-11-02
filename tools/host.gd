extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Session = preload("res://sdk/session.gd")
var dropped_once := false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var args := OS.get_cmdline_user_args()
	var game := args[0] if args.size() > 0 else "hidden_cards"
	var port := int(args[1]) if args.size() > 1 else 27840
	var loader = Loader.new()
	var info: Dictionary = loader.inspect("res://mods/" + game)
	if info.is_empty():
		printerr(loader.error)
		quit(1)
		return
	var logic = loader.rules(info)
	var session = Session.new()
	root.add_child(session)
	if args.has("trace"):
		session.updated.connect(func(snapshot): print("HOST_STATE revision=%d finished=%s" % [snapshot.revision, str(snapshot.view.get("finished", false))]))
	if args.has("drop_once"):
		session.updated.connect(func(snapshot):
			if snapshot.revision == 3 and not dropped_once:
				dropped_once = true
				create_timer(0.4).timeout.connect(func():
					for peer in session.bindings.keys():
						session.wire.drop(peer)
					print("HOST_TEST_DROP revision=" + str(session.room.revision))
				)
		)
	if args.has("autoplay"):
		session.updated.connect(func(snapshot):
			if snapshot.players.size() < 2 or snapshot.view.finished:
				return
			if game == "hidden_cards" and snapshot.view.chosen == -1:
				session.call_deferred("submit", {"type": "choose", "card": snapshot.view.hand[0]})
			elif game == "gomoku" and snapshot.view.turn == 0:
				for x in range(15):
					if snapshot.view.board[x] == -1:
						session.call_deferred("submit", {"type": "place", "x": x, "y": 0})
						break
		)
	var error: Error = session.create(info, logic, {"id": "test-host", "nickname": "Host"}, port)
	if error != OK:
		printerr(error_string(error))
		quit(1)
		return
	print("HOST_READY " + JSON.stringify({"fingerprint": info.fingerprint, "port": port}))
