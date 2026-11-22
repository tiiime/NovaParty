extends RefCounted
const PROTOCOL = 2
const UserProfile = preload("res://sdk/session/user_profile.gd")
const Password = preload("res://sdk/session/room_password.gd")
const MAX_SPECTATOR_IDENTITIES := 128
var _spectators := {}
var _host_id: String
var _password_key: PackedByteArray
var source_name: String
var host_spectates := false
var info: Dictionary
var rules
var state: Dictionary
var game_session_id := Crypto.new().generate_random_bytes(16).hex_encode()
var revision := 0
var players := []
var receipts := {}
var clock_elapsed := [0, 0]
var clock_anchor := -1
var clock_turn := -1
var clock_round := -1

func _init(mod_info: Dictionary, logic, host_id: String, nickname: String, seed_value: int, user_profile: Dictionary = {}, options: Dictionary = {}):
	info = mod_info
	rules = logic
	state = rules.initial_state(seed_value)
	_host_id = host_id
	_password_key = options.get("password_key", PackedByteArray())
	host_spectates = options.get("role", "player") == "spectator"
	var profile := UserProfile.normalize(user_profile, host_id, nickname)
	source_name = profile.display_name
	if not host_spectates:
		players.append({"id": host_id, "nickname": source_name, "token": _token(), "connected": true, "profile": profile})
		if fixed_seats(): _presence(0, true)

func hello(data: Dictionary, replacing_seat: int = -1, nonce: String = "") -> Dictionary:
	advance_clock()
	if data.get("expected_session_id", "") not in ["", game_session_id]:
		return {"type": "error", "code": "room_changed"}
	var protocol = data.get("protocol")
	var compatible: bool = (protocol == 1 and data.get("fingerprint") == info.fingerprint) or (protocol == PROTOCOL and data.get("rules_fingerprint") == info.get("rules_fingerprint", "missing"))
	if not compatible:
		return {"type": "error", "code": "incompatible"}
	var id = data.get("player_id")
	if not id is String or id.is_empty() or id.length() > 128 or not data.get("nickname") is String:
		return {"type": "error", "code": "invalid_identity"}
	var role = data.get("role", "player")
	if not role is String or role not in ["player", "spectator"]:
		return {"type": "error", "code": "invalid_role"}
	var resume = data.get("resume_token", "")
	if not resume is String or resume.length() > 64:
		return {"type": "error", "code": "invalid_resume_token"}
	var record: Dictionary = _spectators.get(id, {})
	var returning_spectator: bool = not record.is_empty() and resume == record.token
	var returning_seat := -1
	for index in range(players.size()):
		if players[index].id == id:
			returning_seat = index
			break
	var returning_player: bool = returning_seat >= 0 and resume == players[returning_seat].token
	if not returning_player and not returning_spectator:
		var denied := _check_password(data, nonce)
		if not denied.is_empty(): return {"type": "error", "code": denied}
	if id == _host_id and host_spectates:
		return {"type": "error", "code": "role_locked"}
	if role == "spectator":
		if returning_seat >= 0: return {"type": "error", "code": "role_locked"}
		return _hello_spectator(id, returning_spectator, str(resume), int(protocol))
	if not record.is_empty(): return {"type": "error", "code": "role_locked"}
	if returning_seat >= 0:
		if drop_in() and not players[returning_seat].connected and str(resume).is_empty():
			players[returning_seat].token = _token()
			_clear_receipts(returning_seat)
		elif not returning_player:
			return {"type": "error", "code": "invalid_resume_token"}
		if players[returning_seat].connected and (id == _host_id or returning_seat != replacing_seat):
			return {"type": "error", "code": "already_connected", "seat": returning_seat}
		_update_profile(returning_seat, data.get("profile", {}), data.nickname)
		if not players[returning_seat].connected: set_connected(returning_seat, true)
		return welcome(returning_seat, int(protocol))
	if not str(resume).is_empty(): return {"type": "error", "code": "invalid_resume_token"}
	if not player_admission_open():
		return {"type": "error", "code": _closed_player_admission_code()}
	var available := -1
	if drop_in():
		for index in range(0 if host_spectates else 1, players.size()):
			if not players[index].connected:
				available = index
				break
	if available < 0 and players.size() >= int(info.manifest.players.max):
		return {"type": "error", "code": "room_full"}
	if available >= 0:
		players[available] = {"id": id, "nickname": data.nickname.left(32), "token": _token(), "connected": true, "profile": UserProfile.normalize(data.get("profile", {}), str(id), data.nickname)}
		players[available].nickname = players[available].profile.display_name
		_clear_receipts(available)
		_presence(available, true)
		return welcome(available, int(protocol))
	players.append({"id": id, "nickname": data.nickname.left(32), "token": _token(), "connected": true, "profile": UserProfile.normalize(data.get("profile", {}), str(id), data.nickname)})
	players[-1].nickname = players[-1].profile.display_name
	_presence(players.size() - 1, true)
	advance_clock()
	return welcome(players.size() - 1, int(protocol))

func password_required() -> bool:
	return not _password_key.is_empty()

func _check_password(data: Dictionary, nonce: String) -> String:
	if not password_required(): return ""
	var proof = data.get("password_proof", "")
	if nonce.is_empty() or not proof is String or proof.is_empty(): return "password_required"
	if proof.length() != 64 or not proof.is_valid_hex_number(false): return "wrong_password"
	var expected := Password.proof(_password_key, nonce, game_session_id, data.player_id, data.get("role", "player"))
	return "" if Crypto.new().constant_time_compare(expected, proof.hex_decode()) else "wrong_password"

func spectator_slots() -> int:
	var available := int(info.manifest.get("spectators", {}).get("max_guests", 0))
	for record in _spectators.values():
		if record.connected: available -= 1
	return available

func player_admission_open() -> bool:
	return not fixed_seats() or not rules.has_method("can_join") or rules.can_join(state.duplicate(true))

func player_slots() -> int:
	if not player_admission_open(): return 0
	return _unclaimed_player_slots()

func player_unavailable_code() -> String:
	return "room_full" if player_admission_open() else _closed_player_admission_code()

func _closed_player_admission_code() -> String:
	return "room_full" if info.manifest.get("host_start", false) and state.get("phase") == "lobby" and _unclaimed_player_slots() <= 0 else "game_in_progress"

func _unclaimed_player_slots() -> int:
	var used := players.size()
	if drop_in():
		for player in players:
			if not player.connected: used -= 1
	return int(info.manifest.players.max) - used

func _hello_spectator(id: String, returning: bool, token: String, protocol: int) -> Dictionary:
	if protocol != PROTOCOL or not info.manifest.has("spectators") or not rules.has_method("view_for_spectator"):
		return {"type": "error", "code": "spectators_unsupported"}
	var record: Dictionary = _spectators.get(id, {})
	if not token.is_empty() and not returning:
		return {"type": "error", "code": "invalid_resume_token"}
	if not record.is_empty() and record.connected and not returning:
		return {"type": "error", "code": "already_connected"}
	if (record.is_empty() or not record.connected) and spectator_slots() <= 0:
		return {"type": "error", "code": "spectators_full"}
	if record.is_empty() and _spectators.size() >= MAX_SPECTATOR_IDENTITIES:
		return {"type": "error", "code": "spectators_full"}
	if not returning: record.token = _token()
	record.connected = true
	_spectators[id] = record
	return {"type": "welcome", "role": "spectator", "resume_token": record.token, "protocol": PROTOCOL, "rules_fingerprint": info.rules_fingerprint, "capabilities": ["presentation_versions"]}

func disconnect_spectator(id: String) -> void:
	if _spectators.has(id): _spectators[id].connected = false

func host_profile_changed(profile: Dictionary) -> void:
	source_name = profile.display_name
	if not host_spectates: _update_profile(0, profile)

func _update_profile(seat: int, value, fallback_name: String = "") -> void:
	if seat < 0 or seat >= players.size(): return
	players[seat].profile = UserProfile.normalize(value, str(players[seat].id), fallback_name if not fallback_name.is_empty() else str(players[seat].nickname))
	players[seat].nickname = players[seat].profile.display_name

func welcome(seat: int, protocol: int = PROTOCOL) -> Dictionary:
	return {"type": "welcome", "seat": seat, "resume_token": players[seat].token, "protocol": protocol, "rules_fingerprint": info.get("rules_fingerprint", ""), "capabilities": ["presentation_versions"] if protocol == 2 else []}

func snapshot(seat: int) -> Dictionary:
	var result := _public_snapshot()
	result.seat = seat
	result.view = rules.view_for(state.duplicate(true), seat)
	return result

func spectator_snapshot() -> Dictionary:
	var result := _public_snapshot()
	result.role = "spectator"
	result.view = rules.view_for_spectator(state.duplicate(true))
	return result

func _public_snapshot() -> Dictionary:
	advance_clock()
	var public_players := []
	for p in players:
		public_players.append({"nickname": p.nickname, "code": str(p.id).sha256_text().left(6), "connected": p.connected, "profile": p.profile.duplicate(true)})
	var result := {"type": "snapshot", "game_session_id": game_session_id, "state_epoch": 0, "revision": revision, "players": public_players}
	if clock_enabled():
		result.clock = {"elapsed_ms": clock_elapsed.duplicate(), "running_seat": clock_turn, "round": clock_round, "synchronized": true}
	return result

func can_host_start() -> bool:
	return info.manifest.get("host_start", false) and rules.can_start_round(state.duplicate(true))

# Separate local host operation: there is no corresponding wire message or player seat.
func host_start_round() -> String:
	if not can_host_start(): return "round_not_ready"
	var result: Dictionary = rules.start_round(state.duplicate(true))
	if not result.get("state") is Dictionary: return str(result.get("error", "round_not_ready"))
	state = result.state
	revision += 1
	advance_clock()
	return ""

func command(seat: int, data: Dictionary) -> Dictionary:
	advance_clock()
	var request = data.get("request_id")
	if not request is String or request.is_empty() or request.length() > 128:
		return {"type": "error", "code": "invalid_request"}
	if seat < 0 or seat >= players.size(): return _receipt(request, "spectator_read_only")
	var key: String = str(seat) + ":" + request
	if receipts.has(key):
		if receipts[key].payload != JSON.stringify(data, "", true):
			return _receipt(request, "request_id_reused")
		return receipts[key].result.duplicate(true)
	# Limit retained requests. Never evict accepted IDs within a room.
	if drop_in() and receipts.size() >= 512:
		receipts.erase(receipts.keys()[0])
	elif receipts.size() >= 10000:
		return _receipt(request, "request_limit")
	var code := ""
	if data.has("game_session_id") and data.game_session_id != game_session_id:
		code = "stale_session"
	elif data.has("state_epoch") and data.state_epoch != 0:
		code = "stale_epoch"
	elif not drop_in() and not fixed_seats() and (players.size() < 2 or not players[0].connected or not players[1].connected):
		code = "waiting_for_players"
	elif not _revision_allowed(data.get("expected_revision")):
		code = "stale_revision"
	elif not data.get("action") is Dictionary:
		code = "invalid_action"
	else:
		var result: Dictionary = rules.apply(state.duplicate(true), seat, data.action)
		code = result.get("error", "")
		if code.is_empty():
			state = result.state
			revision += 1
	advance_clock()
	var receipt := _receipt(request, code)
	receipts[key] = {"payload": JSON.stringify(data, "", true), "result": receipt.duplicate(true)}
	return receipt

func _receipt(request: String, code: String) -> Dictionary:
	return {"type": "receipt", "request_id": request, "accepted": code.is_empty(), "code": code, "revision": revision}

func _token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

func clock_enabled() -> bool:
	return rules.has_method("clock_context")

# Optional explicit monotonic time allows deterministic clock tests without sleeping.
func advance_clock(now: int = -1) -> void:
	if not clock_enabled():
		return
	if now < 0:
		now = Time.get_ticks_msec()
	if clock_anchor >= 0 and clock_turn in [0, 1]:
		clock_elapsed[clock_turn] += maxi(0, now - clock_anchor)
	var context = rules.clock_context(state.duplicate(true))
	if not context is Dictionary:
		clock_turn = -1
		clock_anchor = now
		return
	var round_value: int = int(context.get("round", 0))
	if round_value != clock_round:
		clock_round = round_value
		clock_elapsed = [0, 0]
	var ready: bool = players.size() == 2 and players[0].connected and players[1].connected
	clock_turn = int(context.get("seat", -1)) if ready else -1
	if clock_turn not in [0, 1]:
		clock_turn = -1
	clock_anchor = now

func set_connected(seat: int, connected: bool) -> void:
	advance_clock()
	players[seat].connected = connected
	_presence(seat, connected)
	advance_clock()

# Drop-in games opt in explicitly; board games retain strict two-player semantics.
func drop_in() -> bool:
	return info.manifest.get("session_mode", "") == "drop_in"

func fixed_seats() -> bool:
	return info.manifest.get("session_mode", "") == "fixed"

func _revision_allowed(value) -> bool:
	if not (value is int or value is float) or value != int(value):
		return false
	return value == revision or (drop_in() and value >= 0 and value <= revision)

func _presence(seat: int, connected: bool) -> void:
	if (drop_in() or fixed_seats()) and rules.has_method("presence_changed"):
		state = rules.presence_changed(state.duplicate(true), seat, connected)
		revision += 1

func _clear_receipts(seat: int) -> void:
	for key in receipts.keys():
		if str(key).begins_with(str(seat) + ":"):
			receipts.erase(key)
