extends Node
signal updated(snapshot: Dictionary)
signal notice(message: String)
signal action_result(result: Dictionary)
signal status_changed(state: String, code: String)
const Wire = preload("res://sdk/wire.gd")
const Room = preload("res://sdk/room.gd")
const Sharing = preload("mod_sharing.gd")
var sharing = Sharing.new()
const JoinCode = preload("join_code.gd")
var join_address := ""
var qr_uri := ""
var qr_texture: Texture2D
var host_port := 0
var advertisement
var expected_remote_session := ""
const HEARTBEAT_INTERVAL_MS = 2000
const HEARTBEAT_TIMEOUT_MS = 8000
const HANDSHAKE_TIMEOUT_MS = 10000
var wire
var local_session_id := Crypto.new().generate_random_bytes(16).hex_encode()
var room
var info: Dictionary
var host := false
var seat := -1
var snapshot := {}
var bindings := {}
var pending_since := {}
var identity := {}
var resume_token := ""
var request_counter := 0
var connection_state := "idle"
var connection_error := ""
var heartbeats := {}
var disconnect_reasons := {}
var handshake_since := -1
var last_clock_publish := 0

func _ready() -> void:
	wire = Wire.new()
	add_child(wire)
	wire.message.connect(_message)
	wire.lost.connect(_lost)
	wire.opened.connect(_opened)

func create(mod_info: Dictionary, logic, profile: Dictionary, port: int) -> Error:
	info = mod_info
	identity = profile
	var error: Error = wire.listen(port)
	if error != OK:
		return error
	host = true
	host_port = port
	seat = 0
	room = Room.new(info, logic, profile.id, profile.nickname, int(Crypto.new().generate_random_bytes(4).decode_u32(0)))
	_set_connection("hosting")
	_publish()
	advertisement = preload("discovery.gd").new()
	add_child(advertisement)
	advertisement.advertise(port, room.game_session_id, info, profile.nickname)
	return OK

func join(mod_info: Dictionary, profile: Dictionary, address: String, port: int, token: String = "") -> Error:
	info = mod_info
	identity = profile
	join_address = address
	host_port = port
	resume_token = token
	_set_connection("connecting")
	var error: Error = wire.connect_to(address, port)
	if error != OK:
		_set_connection("failed", "connect_failed")
	return error

func submit(action: Dictionary) -> void:
	request_counter += 1
	submit_request({"request_id": str(Time.get_ticks_usec()) + "-" + str(request_counter), "expected_revision": snapshot.get("revision", -1), "action": action})

# Keep the caller's ID and revision unchanged, including on retries.
func submit_request(request: Dictionary) -> Dictionary:
	var revision = request.get("expected_revision")
	if not request.get("request_id") is String or request.request_id.is_empty() or request.request_id.length() > 128 or not request.get("action") is Dictionary or not (revision is int or revision is float) or revision != int(revision):
		return {"code": "invalid_request"}
	if seat < 0 or snapshot.is_empty():
		return {"code": "not_ready"}
	if not host and not wire.peers.has(0):
		notice.emit("disconnected")
		return {"code": "disconnected"}
	var data := request.duplicate(true)
	data.type = "command"
	if host:
		_execute(0, data)
	else:
		wire.send(0, data)
	return {"queued": true, "request_id": data.request_id}

func _opened(peer: int) -> void:
	if not host:
		_set_connection("handshaking")
		handshake_since = Time.get_ticks_msec()
		wire.send(peer, {"type": "hello", "protocol": 2, "capabilities": ["heartbeat_v1"], "rules_fingerprint": info.rules_fingerprint, "fingerprint": info.fingerprint, "player_id": identity.id, "nickname": identity.nickname, "resume_token": resume_token, "expected_session_id": expected_remote_session})
	else:
		pending_since[peer] = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if host and room != null and room.clock_enabled() and room.clock_turn in [0, 1] and now - last_clock_publish >= 1000:
		_publish()
	for peer in pending_since.keys():
		if now - int(pending_since[peer]) >= HANDSHAKE_TIMEOUT_MS:
			wire.drop(peer)
	if not host and seat < 0 and handshake_since >= 0 and now - handshake_since >= HANDSHAKE_TIMEOUT_MS:
		handshake_since = -1
		disconnect_reasons[0] = "handshake_timeout"
		wire.drop(0)
	for peer in heartbeats.keys():
		var health: Dictionary = heartbeats[peer]
		if now - int(health.confirmed) >= HEARTBEAT_TIMEOUT_MS:
			disconnect_reasons[peer] = "heartbeat_timeout"
			wire.drop(peer)
		elif now - int(health.sent) >= HEARTBEAT_INTERVAL_MS:
			# One outstanding challenge: replacing it would invalidate slow but valid replies.
			if health.nonce.is_empty():
				health.nonce = Crypto.new().generate_random_bytes(8).hex_encode()
				health.sent = now
				wire.send(peer, {"type": "ping", "nonce": health.nonce})

func _enable_heartbeat(peer: int) -> void:
	var now := Time.get_ticks_msec()
	heartbeats[peer] = {"confirmed": now, "sent": now, "nonce": ""}

func _heartbeat(peer: int, data: Dictionary) -> bool:
	if not heartbeats.has(peer) or data.get("type") not in ["ping", "pong"]:
		return false
	var nonce = data.get("nonce")
	if not nonce is String or nonce.length() != 16 or not nonce.is_valid_hex_number(false):
		return true
	if data.type == "ping":
		wire.send(peer, {"type": "pong", "nonce": nonce})
	elif not heartbeats[peer].nonce.is_empty() and nonce == heartbeats[peer].nonce:
		heartbeats[peer].confirmed = Time.get_ticks_msec()
		heartbeats[peer].nonce = ""
	return true

func _message(peer: int, data: Dictionary) -> void:
	if _heartbeat(peer, data):
		return
	if host:
		if not bindings.has(peer):
			if sharing.handle(peer, data, wire, room, info):
				pending_since[peer] = Time.get_ticks_msec()
				return
			if data.get("type") != "hello":
				wire.drop(peer)
				return
			var response: Dictionary = room.hello(data)
			if response.type == "welcome":
				bindings[peer] = response.seat
				pending_since.erase(peer)
				var capabilities = data.get("capabilities", [])
				if data.get("protocol") == 2 and capabilities is Array and capabilities.has("heartbeat_v1"):
					response.capabilities.append("heartbeat_v1")
					_enable_heartbeat(peer)
			wire.send(peer, response)
			if response.type == "welcome":
				_publish()
			return
		if data.get("type") == "command":
			_execute(bindings[peer], data, peer)
	else:
		match data.get("type"):
			"welcome":
				seat = int(data.seat)
				resume_token = data.resume_token
				handshake_since = -1
				var capabilities = data.get("capabilities", [])
				if data.get("protocol") == 2 and capabilities is Array and capabilities.has("heartbeat_v1"):
					_enable_heartbeat(peer)
				_set_connection("connected")
			"snapshot":
				snapshot = data
				updated.emit(data)
			"error":
				_set_connection("rejected", str(data.get("code", "rejected")))
				notice.emit(str(data.get("code")))
				wire.drop(0)
			"receipt":
				action_result.emit(data)
				if not data.accepted:
					notice.emit(str(data.code))

func _execute(player_seat: int, data: Dictionary, peer: int = -1) -> void:
	var result: Dictionary = room.command(player_seat, data)
	if peer >= 0:
		wire.send(peer, result)
	else:
		action_result.emit(result)
		if not result.get("accepted", false):
			notice.emit(str(result.get("code")))
	_publish()

func _publish() -> void:
	last_clock_publish = Time.get_ticks_msec()
	snapshot = room.snapshot(0)
	updated.emit(snapshot)
	for peer in bindings:
		wire.send(peer, room.snapshot(bindings[peer]))

func _lost(peer: int) -> void:
	pending_since.erase(peer)
	heartbeats.erase(peer)
	var reason: String = disconnect_reasons.get(peer, "transport_lost")
	disconnect_reasons.erase(peer)
	if host and bindings.has(peer):
		room.set_connected(bindings[peer], false)
		bindings.erase(peer)
		_publish()
	elif not host:
		handshake_since = -1
		if connection_state != "rejected":
			_set_connection("disconnected", reason)
		notice.emit("connection_lost")

func _set_connection(state: String, code: String = "") -> void:
	if connection_state != state or connection_error != code:
		connection_state = state
		connection_error = code
		status_changed.emit(state, code)

func update_presentation(presentation: Dictionary) -> void:
	if presentation.get("rules_fingerprint") != info.get("rules_fingerprint"):
		return
	info = presentation
	if host:
		room.info = presentation
		advertisement.advertise(host_port, room.game_session_id, info, identity.nickname)

# Optional presentation services. These methods return local data/resources, never network state.
func get_join_info(address_override: String = "") -> Dictionary:
	if snapshot.is_empty():
		return {}
	var address := address_override if not address_override.is_empty() else join_address
	if host and address.is_empty():
		# Prefer Wi-Fi/Ethernet over cellular/VPN interfaces for local invitations.
		for interface in IP.get_local_interfaces():
			var name: String = str(interface.get("name", "")).to_lower()
			if not (name.begins_with("wlan") or name.begins_with("en") or name.begins_with("eth")):
				continue
			for candidate in interface.get("addresses", []):
				if str(candidate).contains(".") and not str(candidate).contains(":") and not str(candidate).begins_with("127.") and not str(candidate).begins_with("169.254."):
					address = candidate
					break
			if not address.is_empty():
				break
	if host and address.is_empty():
		for candidate in IP.get_local_addresses():
			if candidate.contains(".") and not candidate.contains(":") and not candidate.begins_with("127.") and not candidate.begins_with("169.254."):
				address = candidate
				break
	var uri := JoinCode.encode(address, host_port, str(snapshot.get("game_session_id", "")))
	if uri.is_empty():
		return {}
	return {"uri": uri, "address": address, "port": host_port, "session_id": snapshot.game_session_id}

func get_join_qr(address_override: String = "") -> Texture2D:
	var invite := get_join_info(address_override)
	if invite.is_empty():
		return null
	if qr_uri != invite.uri:
		qr_uri = invite.uri
		qr_texture = JoinCode.texture(qr_uri)
	return qr_texture
