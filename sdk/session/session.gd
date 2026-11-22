extends Node
signal updated(snapshot: Dictionary)
signal notice(message: String)
signal action_result(result: Dictionary)
signal status_changed(state: String, code: String)
const Wire = preload("res://sdk/net/wire.gd")
const Room = preload("res://sdk/session/room.gd")
const UserProfile = preload("res://sdk/session/user_profile.gd")
const Password = preload("res://sdk/session/room_password.gd")
var role := "player"
var _join_key: PackedByteArray
var _challenges := {}
var _answered_challenge := false
var profile_supported := false
const Sharing = preload("res://sdk/mods/mod_sharing.gd")
var sharing = Sharing.new()
const JoinCode = preload("res://sdk/net/join_code.gd")
var join_address := ""
var qr_uri := ""
var qr_texture: Texture2D
var host_port := 0
var advertisement
var advertised := false
var bluetooth_hosting := false
var expected_remote_session := ""
const HEARTBEAT_INTERVAL_MS = 2000
const HEARTBEAT_TIMEOUT_MS = 8000
const HANDSHAKE_TIMEOUT_MS = 10000
# Guest auto-recovery: retry the same host with the same seat credentials, backing off.
const RECONNECT_DELAYS_MS = [500, 1000, 2000, 4000, 8000]
const RECONNECT_WINDOW_MS = 120000
# Host-side codes after which retrying cannot succeed.
const FINAL_CODES = ["invalid_resume_token", "room_changed", "session_replaced", "incompatible", "game_in_progress", "room_full", "invalid_identity"]
var auto_reconnect := true
var reconnect_window_ms := RECONNECT_WINDOW_MS
var reconnect_attempts := 0
var reconnect_at := -1
var reconnect_deadline := -1
var closing := false
# Guest commands sent but not yet acknowledged, by request ID, replayed after a reconnect.
var pending_requests := {}
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

static func supports_room_access() -> bool:
	return true

func create(mod_info: Dictionary, logic, profile: Dictionary, port: int, options: Dictionary = {}) -> Error:
	role = options.get("role", "player")
	var password: String = options.get("password", "")
	if role not in ["player", "spectator"] or password.length() > Password.MAX_LENGTH:
		return ERR_INVALID_PARAMETER
	if role == "spectator" and (not mod_info.manifest.has("spectators") or not logic.has_method("view_for_spectator")):
		return ERR_UNAVAILABLE
	info = mod_info
	identity = profile.duplicate(true)
	var error: Error = wire.listen(port)
	if error != OK:
		return error
	host = true
	profile_supported = true
	host_port = port
	seat = -1 if role == "spectator" else 0
	room = Room.new(info, logic, profile.id, profile.nickname, int(Crypto.new().generate_random_bytes(4).decode_u32(0)), UserProfile.local_public(identity), {"role": role, "password_key": Password.key(password)})
	_set_connection("hosting")
	_publish()
	# Only start automatically when the native radio is already ready; never prompt on open.
	if OS.get_name() != "iOS":
		if wire.bluetooth == null: wire.bluetooth = Wire.Bluetooth.shared(get_tree())
		if wire.bluetooth.host_state() == "on": enable_bluetooth_hosting()
	advertisement = preload("res://sdk/net/discovery.gd").new()
	add_child(advertisement)
	_refresh_advertisement()
	return OK

func accepts_new_players() -> bool:
	return host and room != null and room.player_slots() > 0

func accepts_new_connections() -> bool:
	return host and room != null and (accepts_new_players() or room.spectator_slots() > 0)

func enable_bluetooth_hosting() -> bool:
	if not accepts_new_connections():
		return false
	if not bluetooth_hosting or not wire.bluetooth.hosting or wire.bluetooth.host_status == "failed":
		bluetooth_hosting = wire.listen_bluetooth(room.game_session_id, room.password_required())
	return bluetooth_hosting

func join(mod_info: Dictionary, profile: Dictionary, address: String, port: int, token: String = "", options: Dictionary = {}) -> Error:
	role = options.get("role", "player")
	var password: String = options.get("password", "")
	if role not in ["player", "spectator"] or password.length() > Password.MAX_LENGTH:
		return ERR_INVALID_PARAMETER
	_join_key = Password.key(password)
	info = mod_info
	identity = profile.duplicate(true)
	join_address = address
	host_port = port
	resume_token = token
	_set_connection("connecting")
	var error: Error = wire.connect_to(address, port)
	if error != OK:
		_set_connection("failed", "connect_failed")
	return error

func start_round() -> bool:
	if not host or room == null or closing: return false
	if not room.host_start_round().is_empty(): return false
	_publish()
	return true

func can_start_round() -> bool:
	return host and room != null and not closing and room.can_host_start()

func submit(action: Dictionary) -> void:
	request_counter += 1
	submit_request({"request_id": str(Time.get_ticks_usec()) + "-" + str(request_counter), "expected_revision": snapshot.get("revision", -1), "action": action})

# Keep the caller's ID and revision unchanged, including on retries.
func submit_request(request: Dictionary) -> Dictionary:
	var revision = request.get("expected_revision")
	if not request.get("request_id") is String or request.request_id.is_empty() or request.request_id.length() > 128 or not request.get("action") is Dictionary or not (revision is int or revision is float) or revision != int(revision):
		return {"code": "invalid_request"}
	if role == "spectator": return {"code": "spectator_read_only"}
	if seat < 0 or snapshot.is_empty():
		return {"code": "not_ready"}
	var data := request.duplicate(true)
	data.type = "command"
	if host:
		_execute(0, data)
		return {"queued": true, "request_id": data.request_id}
	if not wire.peers.has(0) or connection_state != "connected":
		if reconnect_deadline < 0:
			notice.emit("disconnected")
			return {"code": "disconnected"}
		# Kept and replayed after recovery; the host deduplicates by request ID.
		pending_requests[data.request_id] = data
		return {"queued": true, "request_id": data.request_id, "pending": true}
	pending_requests[data.request_id] = data
	wire.send(0, data)
	return {"queued": true, "request_id": data.request_id}

func _opened(peer: int) -> void:
	if not host:
		_set_connection("handshaking")
		handshake_since = Time.get_ticks_msec()
		_answered_challenge = false
		_send_hello(peer)
	else:
		pending_since[peer] = Time.get_ticks_msec()

func _send_hello(peer: int, proof: String = "") -> void:
	var public := UserProfile.local_public(identity)
	var data := {"type": "hello", "protocol": 2, "capabilities": ["heartbeat_v1", "user_profile_v1", "room_password_v1"], "role": role, "rules_fingerprint": info.rules_fingerprint, "fingerprint": info.fingerprint, "player_id": identity.id, "nickname": public.display_name, "profile": public, "resume_token": resume_token, "expected_session_id": expected_remote_session}
	if not proof.is_empty(): data.password_proof = proof
	wire.send(peer, data)

func _answer_challenge(peer: int, data: Dictionary) -> void:
	var nonce = data.get("nonce")
	var remote = data.get("session_id")
	if connection_state != "handshaking" or _answered_challenge or not nonce is String or nonce.length() != 32 or not nonce.is_valid_hex_number(false) or not remote is String or remote.length() != 32 or not remote.is_valid_hex_number(false):
		_reject("rejected")
	elif not expected_remote_session.is_empty() and expected_remote_session != remote:
		_reject("room_changed")
	elif _join_key.is_empty():
		_reject("password_required")
	else:
		_answered_challenge = true
		_send_hello(peer, Password.proof(_join_key, nonce, remote, identity.id, role).hex_encode())

func _reject(code: String) -> void:
	_join_key.clear()
	pending_requests.clear()
	reconnect_at = -1
	_set_connection("rejected", code)
	notice.emit(code)
	wire.drop(0)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not host and connection_state == "reconnecting" and reconnect_at >= 0 and now >= reconnect_at and not wire.peers.has(0):
		_attempt_reconnect()
	if host and room != null and room.clock_enabled() and room.clock_turn in [0, 1] and now - last_clock_publish >= 1000:
		_publish()
	for peer in pending_since.keys():
		if now - int(pending_since[peer]) >= HANDSHAKE_TIMEOUT_MS:
			wire.drop(peer)
	# Applies to first joins and to reconnect handshakes alike.
	if not host and handshake_since >= 0 and now - handshake_since >= HANDSHAKE_TIMEOUT_MS:
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
			var nonce: String = _challenges.get(peer, "")
			_challenges.erase(peer)
			var response: Dictionary = room.hello(data, -1, nonce)
			var offered_caps = data.get("capabilities", [])
			if response.get("code") == "password_required" and nonce.is_empty() and offered_caps is Array and offered_caps.has("room_password_v1"):
				var fresh := Crypto.new().generate_random_bytes(16).hex_encode()
				_challenges[peer] = fresh
				wire.send(peer, {"type": "password_challenge", "nonce": fresh, "session_id": room.game_session_id})
				return
			if response.get("code") == "already_connected" and response.has("seat"):
				# Rotate the binding without a false presence event or a rules revision change.
				var replacement_seat := int(response.seat)
				for old in bindings.keys():
					if not bindings[old] is int or int(bindings[old]) != replacement_seat:
						continue
					response = room.hello(data, replacement_seat, nonce)
					if response.type == "welcome":
						bindings.erase(old)
						heartbeats.erase(old)
						wire.retire(old, {"type": "error", "code": "session_replaced"})
					break
			if response.type == "welcome":
				if response.get("role") == "spectator":
					for old in bindings.keys():
						if bindings[old] is String and str(bindings[old]) == data.player_id:
							bindings.erase(old)
							heartbeats.erase(old)
							wire.retire(old, {"type": "error", "code": "session_replaced"})
					bindings[peer] = data.player_id
				else:
					bindings[peer] = response.seat
				pending_since.erase(peer)
				var capabilities = data.get("capabilities", [])
				if data.get("protocol") == 2 and capabilities is Array and capabilities.has("heartbeat_v1"):
					response.capabilities.append("heartbeat_v1")
					_enable_heartbeat(peer)
				if bindings[peer] is int and offered_caps is Array and offered_caps.has("user_profile_v1"):
					response.capabilities.append("user_profile_v1")
				wire.send(peer, response)
				_publish()
			else:
				wire.retire(peer, response)
			return
		if bindings[peer] is String:
			if data.get("type") == "command":
				wire.send(peer, room.command(-1, data))
			return
		if data.get("type") == "profile_update":
			room._update_profile(int(bindings[peer]), data.get("profile", {}))
			_publish()
		if data.get("type") == "command":
			_execute(bindings[peer], data, peer)
	else:
		match data.get("type"):
			"password_challenge":
				_answer_challenge(peer, data)
			"welcome":
				if connection_state != "handshaking" or data.get("role", "player") != role or (role == "player" and not data.has("seat")) or (not _join_key.is_empty() and not _answered_challenge and resume_token.is_empty()):
					_reject("incompatible")
					return
				seat = int(data.get("seat", -1))
				_join_key.clear()
				resume_token = data.resume_token
				handshake_since = -1
				var capabilities = data.get("capabilities", [])
				profile_supported = capabilities is Array and capabilities.has("user_profile_v1")
				if data.get("protocol") == 2 and capabilities is Array and capabilities.has("heartbeat_v1"):
					_enable_heartbeat(peer)
				reconnect_attempts = 0
				reconnect_at = -1
				reconnect_deadline = -1
				_set_connection("connected")
				for request in pending_requests.values():
					wire.send(peer, request)
			"snapshot":
				if connection_state != "connected" or data.get("role", "player") != role: return
				snapshot = data
				updated.emit(data)
			"error":
				_reject(str(data.get("code", "rejected")))
			"receipt":
				pending_requests.erase(str(data.get("request_id", "")))
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
	_refresh_advertisement()
	last_clock_publish = Time.get_ticks_msec()
	snapshot = room.spectator_snapshot() if role == "spectator" else room.snapshot(0)
	updated.emit(snapshot)
	var public := snapshot if role == "spectator" else {}
	for peer in bindings:
		if bindings[peer] is String:
			if public.is_empty(): public = room.spectator_snapshot()
			wire.send(peer, public)
		else:
			wire.send(peer, room.snapshot(bindings[peer]))

func _refresh_advertisement() -> void:
	if advertisement == null or room == null:
		return
	var joinable := accepts_new_connections()
	if joinable and not advertised:
		advertisement.advertise(host_port, room.game_session_id, info, identity.nickname, room.password_required())
		advertised = true
		if bluetooth_hosting: wire.bluetooth.set_advertising(true)
	elif not joinable and advertised:
		if bluetooth_hosting: wire.bluetooth.set_advertising(false)
		advertisement.stop_advertise()
		advertised = false

func _lost(peer: int) -> void:
	_challenges.erase(peer)
	pending_since.erase(peer)
	heartbeats.erase(peer)
	var reason: String = disconnect_reasons.get(peer, "transport_lost")
	disconnect_reasons.erase(peer)
	if host and bindings.has(peer):
		if bindings[peer] is String: room.disconnect_spectator(bindings[peer])
		else: room.set_connected(bindings[peer], false)
		bindings.erase(peer)
		_publish()
	elif not host:
		handshake_since = -1
		if connection_state == "rejected" or closing:
			return
		var recoverable: bool = auto_reconnect and not resume_token.is_empty()
		if recoverable and (reconnect_deadline < 0 or Time.get_ticks_msec() < reconnect_deadline):
			_schedule_reconnect(reason)
			return
		_set_connection("disconnected" if reconnect_deadline < 0 else "failed", reason if reconnect_deadline < 0 else "reconnect_timeout")
		notice.emit("connection_lost")

func _set_connection(state: String, code: String = "") -> void:
	if connection_state != state or connection_error != code:
		connection_state = state
		connection_error = code
		status_changed.emit(state, code)

func _schedule_reconnect(reason: String) -> void:
	var now := Time.get_ticks_msec()
	if reconnect_deadline < 0:
		reconnect_deadline = now + reconnect_window_ms
	var delay: int = RECONNECT_DELAYS_MS[mini(reconnect_attempts, RECONNECT_DELAYS_MS.size() - 1)]
	reconnect_at = now + delay
	_set_connection("reconnecting", reason)

func _attempt_reconnect() -> void:
	reconnect_attempts += 1
	reconnect_at = -1
	# Only the same match may answer: a new room on the same address is refused.
	expected_remote_session = str(snapshot.get("game_session_id", expected_remote_session))
	if wire.connect_to(join_address, host_port) != OK:
		_lost(0)

# Platform hook: skip the backoff (app returned to the foreground, user tapped reconnect).
func reconnect_now() -> bool:
	if host or resume_token.is_empty() or connection_state in ["connected", "handshaking", "connecting", "rejected"] or closing:
		return false
	if wire.peers.has(0):
		return false
	reconnect_attempts = 0
	reconnect_deadline = Time.get_ticks_msec() + reconnect_window_ms
	reconnect_at = Time.get_ticks_msec()
	_set_connection("reconnecting", "requested")
	return true

# Intentional leave: never auto-reconnect.
func close() -> void:
	closing = true
	_join_key.clear()
	reconnect_at = -1
	pending_requests.clear()
	if wire != null and wire.peers.has(0):
		wire.drop(0)

func update_presentation(presentation: Dictionary) -> void:
	if presentation.get("rules_fingerprint") != info.get("rules_fingerprint"):
		return
	info = presentation
	if host:
		room.info = presentation
		if advertised:
			advertisement.advertise(host_port, room.game_session_id, info, identity.nickname, room.password_required())

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

# Public presentation services. Returned dictionaries are detached from identity/state.
func get_local_profile() -> Dictionary:
	return UserProfile.local_public(identity).duplicate(true)

func get_player_profile(player_seat: int) -> Dictionary:
	var players: Array = snapshot.get("players", [])
	if player_seat < 0 or player_seat >= players.size(): return UserProfile.normalize({})
	var player: Dictionary = players[player_seat]
	return UserProfile.normalize(player.get("profile", {}), str(player.get("code", "")), str(player.get("nickname", "Player")))

func get_avatar_texture(profile: Dictionary) -> Texture2D:
	return UserProfile.texture(profile)

func get_profile_color(profile: Dictionary) -> Color:
	return UserProfile.color(profile)

func update_user_profile(local: Dictionary) -> bool:
	# Mod-facing getters are public; mutation is reserved for the platform UI.
	var public := UserProfile.local_public(local)
	identity.nickname = public.display_name
	identity.avatar = public.avatar.duplicate(true)
	identity.theme_color = public.theme_color
	if host and room != null:
		room.host_profile_changed(public)
		if advertised and advertisement != null:
			advertisement.stop_advertise()
			advertised = false
		_publish()
		return true
	if profile_supported and wire != null and wire.peers.has(0):
		wire.send(0, {"type":"profile_update", "profile":public})
		return true
	return false
