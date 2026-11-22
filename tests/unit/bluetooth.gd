extends SceneTree
# Bluetooth transport contract, exercised with two in-process radios (no hardware needed).
const Bluetooth = preload("res://sdk/net/bluetooth.gd")
const FakeRadio = preload("res://tests/support/fake_radio.gd")
const Loader = preload("res://sdk/mods/mod_loader.gd")
const Session = preload("res://sdk/session/session.gd")
const Discovery = preload("res://sdk/net/discovery.gd")
const PeerMods = preload("res://sdk/mods/peer_mods.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL BLUETOOTH: " + message)

func _initialize() -> void:
	call_deferred("run")

func wait_until(condition: Callable, frames: int = 600) -> bool:
	for i in range(frames):
		if condition.call(): return true
		await process_frame
	return condition.call()

func radio(air: Dictionary, id: String) -> Node:
	var node: Node = Bluetooth.new()
	root.add_child(node)
	node.use_backend(FakeRadio.new(air, id), "fake")
	return node

func run() -> void:
	var air := {}
	var host_radio := radio(air, "AA:00")
	var guest_radio := radio(air, "BB:11")
	check(host_radio.available() and host_radio.state == "on", "bridge reports a powered radio")
	host_radio._event({"type": "ble_host_state", "state": "on"})
	host_radio._event({"type": "ble_state", "state": "unauthorized"})
	check(host_radio.host_state() == "on" and host_radio.state == "unauthorized", "Android can host without scan permission")
	host_radio._event({"type": "ble_state", "state": "on"})
	var loader = Loader.new()
	var info: Dictionary = loader.inspect("res://mods/gomoku")
	var host = Session.new()
	root.add_child(host)
	host.wire.bluetooth = host_radio
	const PASSWORD := "room over BLE"
	var created: bool = host.create(info, loader.rules(info), {"id": "host-player", "nickname": "Host"}, 0, {"password": PASSWORD}) == OK
	check(created, "host starts TCP and Bluetooth together")
	if not created:
		quit(1)
		return
	check(host.bluetooth_hosting and host_radio.advertising, "joinable host advertises over Bluetooth")
	check(host_radio.host_status == "starting", "hosting is not reported ready before native confirmation")
	host_radio._event({"type": "ble_advertising"})
	check(host_radio.host_status == "ready", "native advertising confirmation marks the invite ready")
	var sid: String = host.room.game_session_id

	var discovery = Discovery.new()
	root.add_child(discovery)
	discovery.bluetooth = guest_radio
	discovery.browse()
	check(not guest_radio.scanning, "ordinary LAN discovery does not start Bluetooth")
	discovery.browse(true)
	check(await wait_until(func(): return discovery.list_rooms().any(func(room): return room.get("transport") == "ble")), "explicit Bluetooth scan lists the host")
	var rows: Array = discovery.list_rooms().filter(func(room): return room.get("transport") == "ble")
	if rows.is_empty():
		quit(1)
		return
	check(rows.size() == 1 and rows[0].address == "ble:AA:00" and rows[0].code == sid.left(6) and rows[0].password_required, "row carries ble: address, session code and lock bit")
	guest_radio._event({"type": "ble_found", "key": "apple-without-name", "name": "NP", "rssi": -60})
	check(discovery.list_rooms().any(func(entry): return entry.address == "ble:apple-without-name" and entry.code.is_empty()), "UUID-only CoreBluetooth advert is discoverable")
	guest_radio.devices.erase("apple-without-name")

	# Catalog + package download through the ordinary Mod sharing endpoint, in 20-byte chunks.
	var transfer = PeerMods.new()
	root.add_child(transfer)
	transfer.wire.bluetooth = guest_radio
	var catalog := [{}]
	var done := [""]
	transfer.catalog_received.connect(func(metadata): catalog[0] = metadata)
	transfer.completed.connect(func(path, _metadata): done[0] = path)
	check(transfer.inspect_remote(rows[0].address, 0) == OK, "inspect over Bluetooth starts")
	check(await wait_until(func(): return not catalog[0].is_empty()), "catalog arrives over Bluetooth")
	check(catalog[0].get("session_id") == sid and catalog[0].get("game_id") == "gomoku" and catalog[0].get("password_required") == true, "Bluetooth catalog identifies locked live game")
	transfer.confirm_download()
	check(await wait_until(func(): return not done[0].is_empty(), 4000), "package download completes over Bluetooth")
	check(not done[0].is_empty() and FileAccess.get_sha256(done[0]) == catalog[0].get("sha256"), "downloaded package hash matches")
	var peak := 0
	for stream in guest_radio.streams.values(): peak = maxi(peak, stream.outstanding)
	check(peak <= Bluetooth.WINDOW, "send window bounds unacknowledged bytes")
	transfer.cancel()
	transfer.queue_free()
	check(await wait_until(func(): return host_radio.streams.is_empty()), "host sees the transfer link close")

	var guest = Session.new()
	root.add_child(guest)
	guest.wire.bluetooth = guest_radio
	guest.expected_remote_session = sid
	check(guest.join(info, {"id": "guest-player", "nickname": "Guest"}, rows[0].address, 0, "", {"password": PASSWORD}) == OK, "guest joins locked room by ble: address")
	check(await wait_until(func(): return guest.seat == 1 and not guest.snapshot.is_empty()), "handshake and first snapshot cross the link")
	check(guest.connection_state == "connected" and host.snapshot.players.size() == 2, "both sides agree on two players")
	host.submit({"type": "place", "x": 7, "y": 7})
	check(await wait_until(func(): return int(guest.snapshot.get("revision", 0)) == int(host.snapshot.revision) and int(host.snapshot.revision) > 0), "host move reaches the guest")
	guest.submit({"type": "place", "x": 8, "y": 7})
	check(await wait_until(func(): return int(host.snapshot.revision) >= 2 and int(guest.snapshot.revision) == int(host.snapshot.revision)), "guest move is executed by the host")
	# A host that stops being joinable keeps its links but disappears from scans.
	host_radio.set_advertising(false)
	await create_timer(Bluetooth.DEVICE_TTL_MS / 1000.0 + 0.5).timeout
	check(guest_radio.list_devices().is_empty(), "stale Bluetooth device expires from the scan list")
	check(host_radio.streams.size() == 1 and guest.connection_state == "connected", "stopping advertising keeps the live link")

	# Link loss recovers by itself over the same Bluetooth address and seat.
	var token: String = guest.resume_token
	var states: Array = []
	guest.status_changed.connect(func(state, _code): states.append(state))
	guest_radio.backend.drop_all()
	check(await wait_until(func(): return states.has("reconnecting")), "guest starts recovering after the radio link drops")
	check(await wait_until(func(): return guest.connection_state == "connected" and host.snapshot.players[1].connected, 900), "automatic Bluetooth reconnect")
	check(guest.seat == 1 and int(guest.snapshot.revision) == int(host.snapshot.revision), "same seat and state after recovery")
	# A radio can't open two streams to the same peripheral; the old stream stays usable.
	check(guest_radio.connect_peer("AA:00") == null and guest.connection_state == "connected", "duplicate dial does not replace a live BLE stream")
	# A different radio (or TCP link) with the same credentials can take over the seat.
	var new_radio := radio(air, "BB:22")
	var resumed = Session.new()
	root.add_child(resumed)
	resumed.wire.bluetooth = new_radio
	check(resumed.join(info, {"id": "guest-player", "nickname": "Guest"}, rows[0].address, 0, token) == OK, "another radio can resume with the same credentials")
	check(await wait_until(func(): return resumed.seat == 1 and int(resumed.snapshot.get("revision", -1)) == int(host.snapshot.revision)), "takeover restores seat and state")
	check(await wait_until(func(): return guest.connection_state == "rejected" and guest.connection_error == "session_replaced"), "replaced connection is told and does not retry")
	check(resumed.connection_state == "connected" and host.snapshot.players[1].connected, "retiring the old link keeps the seat online")
	guest.queue_free()
	var observer := Session.new()
	root.add_child(observer)
	observer.wire.bluetooth = guest_radio
	check(observer.join(info, {"id": "observer", "nickname": "Observer"}, rows[0].address, 0, "", {"role": "spectator", "password": PASSWORD}) == OK, "observer can dial a full room over Bluetooth")
	check(await wait_until(func(): return observer.snapshot.get("role") == "spectator") and not observer.snapshot.has("seat"), "Bluetooth observer gets the public snapshot")

	var unknown = new_radio.connect_peer("ZZ:99")
	check(unknown != null, "unknown device starts as a pending link")
	check(await wait_until(func(): return unknown.get_status() == StreamPeerTCP.STATUS_ERROR), "failed Bluetooth connect is reported as lost")
	var off_air := {}
	var refused := radio(off_air, "CC:22")
	refused.backend.powered = false
	refused.host("abcdef")
	refused.scan()
	check(not refused.hosting and not refused.advertising and not refused.scanning and refused.last_error == "bluetooth_off", "a refusing radio does not report hosting, advertising or scanning")
	refused.backend.powered = true
	refused.stop_scan()
	refused.scan()
	check(refused.scanning, "scanning restarts once the radio is available")
	refused.queue_free()
	var silent: Node = Bluetooth.new()
	root.add_child(silent)
	check(not silent.available() and silent.connect_peer("AA:00") == null and not silent.host("abcdef"), "no bridge means Bluetooth is cleanly unavailable")
	for node in [observer, resumed, host, discovery, silent, host_radio, guest_radio, new_radio]:
		node.queue_free()
	await process_frame
	print("BLUETOOTH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
