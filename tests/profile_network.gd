extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Session = preload("res://sdk/session.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("PROFILE_NET FAIL: " + message)
func _initialize() -> void: run.call_deferred()
func until(predicate: Callable) -> bool:
	for i in range(300):
		if predicate.call(): return true
		await create_timer(.01).timeout
	return false
func run() -> void:
	var loader := Loader.new()
	var info := loader.inspect("res://mods/gomoku")
	var server := TCPServer.new()
	server.listen(0,"127.0.0.1")
	var port := server.get_local_port()
	server.stop()
	var host := Session.new()
	var guest := Session.new()
	root.add_child(host)
	root.add_child(guest)
	check(host.create(info,loader.rules(info),{"id":"host","nickname":"Host","avatar":{"character":"panda","palette":"berry"}},port) == OK, "host starts")
	check(guest.join(info,{"id":"guest","nickname":"Guest","avatar":{"character":"cat","palette":"mint"},"theme_color":"rose"},"127.0.0.1",port) == OK, "guest joins")
	check(await until(func(): return guest.snapshot.get("players",[]).size() == 2), "hello exchanges profiles")
	check(guest.profile_supported and guest.get_player_profile(0).avatar == {"character":"panda","palette":"berry"}, "profile capability and host avatar received")
	check(host.get_player_profile(1).avatar == {"character":"cat","palette":"mint"}, "guest avatar received")
	var before: Dictionary = host.snapshot.duplicate(true)
	check(guest.update_user_profile({"nickname":"New name","avatar":{"character":"fox","palette":"ocean"},"theme_color":"gold","id":"malicious"}), "guest publishes appearance")
	check(await until(func(): return host.snapshot.players[1].nickname == "New name" and guest.snapshot.players[1].nickname == "New name"), "live appearance synchronized")
	check(host.snapshot.players[0].nickname == "Host" and host.room.players[1].id == "guest", "message cannot change another seat or identity")
	check(host.snapshot.revision == before.revision and host.snapshot.view == before.view, "metadata update preserves game revision and state")
	check(guest.get_avatar_texture(guest.get_local_profile()) != null and guest.get_profile_color(guest.get_local_profile()) == Color("a87d12"), "Mod services expose texture and accent")
	var profile: Dictionary = guest.get_player_profile(1)
	profile.avatar.character = "dog"
	check(guest.get_player_profile(1).avatar.character == "fox", "getter detached from snapshot")
	# A decoded JSON message may contain an invented seat; binding remains authoritative.
	guest.wire.send(0,{"type":"profile_update","seat":0,"profile":{"display_name":"Bound guest","avatar":{"character":"dog","palette":"honey"}}})
	check(await until(func(): return host.snapshot.players[1].nickname == "Bound guest"), "raw update accepted for authenticated binding")
	check(host.snapshot.players[0].nickname == "Host", "forged seat ignored")
	guest.queue_free()
	host.queue_free()
	await process_frame
	print("PROFILE_NETWORK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
