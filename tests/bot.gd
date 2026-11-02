extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Session = preload("res://sdk/session.gd")
var session
var game: String
var last_revision := -1

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var args := OS.get_cmdline_user_args()
	game = args[0]
	var loader = Loader.new()
	var mod_root: String = loader.mount_zip(args[4]) if args.size() > 4 else "res://mods/" + game
	var info: Dictionary = loader.inspect(mod_root)
	session = Session.new()
	root.add_child(session)
	session.updated.connect(receive)
	session.notice.connect(func(message): printerr(message))
	var result: Error = session.join(info, {"id": "bot-guest", "nickname": "测试玩家"}, args[2] if args.size() > 2 else "127.0.0.1", int(args[1]))
	if result != OK:
		quit(1)
	create_timer(float(args[3]) if args.size() > 3 else 10.0).timeout.connect(func(): printerr("BOT_TIMEOUT"); quit(1))

func receive(snapshot: Dictionary) -> void:
	if snapshot.view.finished:
		print("BOT_FINISHED " + game + " revision=" + str(snapshot.revision) + " winner=" + str(snapshot.view.get("winner", -1)))
		quit(0)
		return
	print("BOT_STATE revision=%d" % [snapshot.revision])
	if int(snapshot.revision) <= last_revision:
		return
	last_revision = int(snapshot.revision)
	if snapshot.view.has("hand") and snapshot.view.chosen == -1:
		session.call_deferred("submit", {"type": "choose", "card": snapshot.view.hand[0]})
	elif snapshot.view.has("board") and snapshot.view.turn == 1:
		for x in range(15):
			if snapshot.view.board[15 + x] == -1:
				session.call_deferred("submit", {"type": "place", "x": x, "y": 1})
				break
