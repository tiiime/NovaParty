extends SceneTree
const Session = preload("res://sdk/session/session.gd")
const Loader = preload("res://sdk/mods/mod_loader.gd")
const PeerMods = preload("res://sdk/mods/peer_mods.gd")
const Password = preload("res://sdk/session/room_password.gd")
const JoinCode = preload("res://sdk/net/join_code.gd")
const PASSWORD := "星星 moon 24"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ROOM ACCESS: " + message)

func wait_for(test: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 2500
	while not test.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return test.call()

func connect_guest(info: Dictionary, port: int, id: String, role: String, password: String, resume: String = "") -> Node:
	var guest := Session.new()
	root.add_child(guest)
	check(guest.join(info, {"id": id, "nickname": id}, "127.0.0.1", port, resume, {"role": role, "password": password}) == OK, "connect " + id)
	check(await wait_for(func(): return not guest.snapshot.is_empty() or guest.connection_state == "rejected"), "guest handshake finishes: " + id)
	return guest

func run() -> void:
	var loader := Loader.new()
	var info := loader.inspect("res://mods/gomoku")
	var tcp := TCPServer.new()
	if tcp.listen(0, "127.0.0.1") != OK:
		quit(1)
		return
	var port := tcp.get_local_port()
	tcp.stop()
	var host := Session.new()
	root.add_child(host)
	check(host.create(info, loader.rules(info), {"id": "host", "nickname": "Host"}, port, {"role": "spectator", "password": PASSWORD}) == OK, "create locked room as spectator")
	check(host.snapshot.role == "spectator" and not host.snapshot.has("seat") and host.snapshot.players.is_empty(), "host takes no seat")
	check(host.room.spectator_slots() == 4, "host takes no spectator guest quota")
	var catalog := PeerMods.new()
	root.add_child(catalog)
	catalog.inspect_remote("127.0.0.1", port)
	check(await wait_for(func(): return not catalog.metadata.is_empty()), "locked room catalog is readable")
	check(catalog.metadata.password_required and catalog.metadata.player_slots == 2 and catalog.metadata.spectator_slots == 4 and catalog.metadata.source_name == "Host", "catalog advertises only public access metadata")
	check(not JSON.stringify(catalog.metadata).contains(PASSWORD) and not catalog.metadata.has("password_proof"), "catalog does not disclose a password")
	var proof := Password.proof(Password.key(PASSWORD), "original", host.room.game_session_id, "probe", "spectator").hex_encode()
	var hello := {"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "probe", "nickname": "Probe", "role": "spectator", "password_proof": proof}
	check(host.room.hello(hello, -1, "different").code == "wrong_password", "proof cannot be replayed on a fresh connection")
	hello.role = "player"
	check(host.room.hello(hello, -1, "original").code == "wrong_password", "proof is bound to the requested role")
	catalog.cancel()
	catalog.queue_free()
	var no_password := await connect_guest(info, port, "no-password", "spectator", "")
	check(no_password.connection_error == "password_required" and no_password.snapshot.is_empty(), "password required before spectator snapshot")
	var wrong := await connect_guest(info, port, "wrong", "player", "wrong")
	check(wrong.connection_error == "wrong_password" and wrong.snapshot.is_empty() and host.room.players.is_empty(), "wrong password does not allocate a seat")
	var a := await connect_guest(info, port, "first", "player", PASSWORD)
	var b := await connect_guest(info, port, "second", "player", PASSWORD)
	check(a.seat == 0 and b.seat == 1 and host.room.player_slots() == 0, "two other people can play")
	a.submit({"type": "place", "x": 4, "y": 5})
	check(await wait_for(func(): return host.snapshot.revision == 1), "first player, not host, can play")
	var watcher := await connect_guest(info, port, "watch", "spectator", PASSWORD)
	check(watcher.snapshot.role == "spectator" and not watcher.snapshot.has("seat") and watcher.snapshot.view.board[79] == 0 and not watcher.snapshot.view.has("rematch_votes"), "late spectator receives the public board in a full room")
	check(not host.submit_request({"request_id": "fake", "action": {"type": "place"}, "expected_revision": 1}).has("queued"), "observer host cannot issue player command")
	var receipt := []
	watcher.action_result.connect(func(result): receipt.append(result))
	watcher.wire.send(0, {"type": "command", "request_id": "spoof", "expected_revision": 1, "seat": 1, "action": {"type": "place", "x": 7, "y": 7}})
	check(await wait_for(func(): return not receipt.is_empty()), "spectator command gets a room-side receipt")
	check(not receipt.is_empty() and receipt[0].code == "spectator_read_only" and host.snapshot.revision == 1, "forged seat does not grant permission")
	var token: String = watcher.resume_token
	var states := []
	watcher.status_changed.connect(func(state, _code): states.append(state))
	watcher.wire.drop(0)
	check(await wait_for(func(): return states.has("reconnecting") and watcher.connection_state == "connected"), "spectator automatically reconnects")
	check(watcher.resume_token == token and watcher.seat == -1, "automatic recovery restores the same role and credential")
	watcher.close()
	check(await wait_for(func(): return host.room.spectator_slots() == 4), "leaving releases spectator quota")
	check(host.room.players[0].connected and host.room.players[1].connected and host.snapshot.revision == 1, "spectator leaving does not pause or advance the match")
	var switching := await connect_guest(info, port, "watch", "player", PASSWORD)
	check(switching.connection_error == "role_locked", "leave and rejoin cannot change spectator into player")
	var wrong_role := await connect_guest(info, port, "watch", "player", "", token)
	check(wrong_role.connection_error == "role_locked", "resume credential cannot authorize a role switch")
	var resumed := await connect_guest(info, port, "watch", "spectator", "", token)
	check(not resumed.snapshot.is_empty() and resumed.resume_token == token, "password-free credential resume keeps spectator role")
	b.submit({"type": "place", "x": 7, "y": 7})
	check(await wait_for(func(): return resumed.snapshot.get("revision") == 2), "spectator disconnect did not stop play")
	var extra := []
	for index in range(3): extra.append(await connect_guest(info, port, "extra%d" % index, "spectator", PASSWORD))
	var overflow := await connect_guest(info, port, "overflow", "spectator", PASSWORD)
	check(host.room.spectator_slots() == 0 and overflow.connection_error == "spectators_full", "spectator quota is independent and enforced")
	for guest in [host, no_password, wrong, a, b, watcher, switching, wrong_role, resumed, overflow] + extra: guest.queue_free()
	await process_frame
	await check_ui(port)
	print("ROOM_ACCESS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check_ui(port: int) -> void:
	var scene := load("res://app/main.tscn")
	var app = scene.instantiate()
	app.profile_path = "user://room-access-test-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	root.size = Vector2i(540, 960)
	app._open_setup(true)
	app._launch_game()
	check(app.room_access.visible and app.room_access.roles.visible and app.room_access.password_field.secret, "create dialog presents role and masked optional password")
	app.room_access.watch_role.pressed.emit()
	check(app.room_access.role == "spectator" and app.room_access.watch_role.button_pressed, "create dialog has mutually exclusive roles")
	app.room_access.close()
	check(root.gui_get_focus_owner() == app.create_button, "cancel creation returns focus to launch")
	var loader := Loader.new()
	var host := Session.new()
	root.add_child(host)
	var info := loader.inspect("res://mods/gomoku")
	check(host.create(info, loader.rules(info), {"id": "ui-host", "nickname": "Host"}, port, {"password": PASSWORD}) == OK, "UI fixture locked host")
	app._open_setup(false)
	app._show_manual_join()
	app.address.text = "127.0.0.1:%d" % port
	app._submit_manual_join()
	check(await wait_for(func(): return app.room_access.visible), "manual address leads to role/password prompt")
	check(app.room_access.primary.text == "JOIN_GAME" and app.room_access.watch_action.visible and app.room_access.primary.disabled, "join remains primary and locked room requires a password")
	app.room_access.password_field.text = "wrong"
	app.room_access._submit("spectator")
	check(await wait_for(func(): return app.room_access.visible and app.room_access.error_label.visible), "incorrect password reopens room prompt")
	app.room_access.password_field.text = PASSWORD
	app.room_access._submit("spectator")
	check(await wait_for(func(): return is_instance_valid(app.session) and app.session.snapshot.get("role") == "spectator"), "correct password launches read-only spectator view")
	if is_instance_valid(app.game_view):
		check(not app.game_view.has_signal("command") and app.status_key == "SPECTATING" and not app.room_access.visible, "spectator UI is labeled and has no game command signal")
	else:
		check(false, "spectator view is present")
	app._leave()
	var other := await connect_guest(info, port, "ui-other", "player", PASSWORD)
	var invite := JoinCode.encode("127.0.0.1", port, host.room.game_session_id)
	app._join_scanned_code(invite)
	check(await wait_for(func(): return app.room_access.visible and app.room_access.primary.text == "SPECTATE_ONLY"), "QR to full room makes spectate the primary action")
	check(not app.room_access.watch_action.visible and app.room_access.password_field.visible and not invite.contains(PASSWORD), "full room has one spectator action and password stays out of invite")
	app.room_access.close()
	check(not app.room_access.visible and app.room_access.password_field.text.is_empty(), "cancel clears the password and closes the prompt")
	other.queue_free()
	host.queue_free()
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	await process_frame
