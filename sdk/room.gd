extends RefCounted
const PROTOCOL = 2
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

func _init(mod_info: Dictionary, logic, host_id: String, nickname: String, seed_value: int):
	info = mod_info
	rules = logic
	state = rules.initial_state(seed_value)
	players.append({"id": host_id, "nickname": nickname.left(32), "token": _token(), "connected": true})

func hello(data: Dictionary) -> Dictionary:
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
	for seat in range(players.size()):
		if players[seat].id == id:
			if drop_in() and not players[seat].connected and str(data.get("resume_token", "")).is_empty():
				players[seat].token = _token()
				players[seat].nickname = data.nickname.left(32)
				_clear_receipts(seat)
				set_connected(seat, true)
				return welcome(seat, int(protocol))
			if data.get("resume_token", "") != players[seat].token:
				return {"type": "error", "code": "invalid_resume_token"}
			if players[seat].connected:
				return {"type": "error", "code": "already_connected"}
			set_connected(seat, true)
			return welcome(seat, int(protocol))
	var available := -1
	if drop_in():
		for index in range(1, players.size()):
			if not players[index].connected:
				available = index
				break
	if available < 0 and players.size() >= int(info.manifest.players.max):
		return {"type": "error", "code": "room_full"}
	if available >= 0:
		players[available] = {"id": id, "nickname": data.nickname.left(32), "token": _token(), "connected": true}
		_clear_receipts(available)
		_presence(available, true)
		return welcome(available, int(protocol))
	players.append({"id": id, "nickname": data.nickname.left(32), "token": _token(), "connected": true})
	_presence(players.size() - 1, true)
	advance_clock()
	return welcome(players.size() - 1, int(protocol))

func welcome(seat: int, protocol: int = PROTOCOL) -> Dictionary:
	return {"type": "welcome", "seat": seat, "resume_token": players[seat].token, "protocol": protocol, "rules_fingerprint": info.get("rules_fingerprint", ""), "capabilities": ["presentation_versions"] if protocol == 2 else []}

func snapshot(seat: int) -> Dictionary:
	advance_clock()
	var public_players := []
	for p in players:
		public_players.append({"nickname": p.nickname, "code": str(p.id).sha256_text().left(6), "connected": p.connected})
	var result := {"type": "snapshot", "game_session_id": game_session_id, "state_epoch": 0, "revision": revision, "seat": seat, "players": public_players, "view": rules.view_for(state.duplicate(true), seat)}
	if clock_enabled():
		result.clock = {"elapsed_ms": clock_elapsed.duplicate(), "running_seat": clock_turn, "round": clock_round, "synchronized": true}
	return result

func command(seat: int, data: Dictionary) -> Dictionary:
	advance_clock()
	var request = data.get("request_id")
	if not request is String or request.is_empty() or request.length() > 128:
		return {"type": "error", "code": "invalid_request"}
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
	elif not drop_in() and (players.size() < 2 or not players[0].connected or not players[1].connected):
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

func _revision_allowed(value) -> bool:
	if not (value is int or value is float) or value != int(value):
		return false
	return value == revision or (drop_in() and value >= 0 and value <= revision)

func _presence(seat: int, connected: bool) -> void:
	if drop_in() and rules.has_method("presence_changed"):
		state = rules.presence_changed(state.duplicate(true), seat, connected)
		revision += 1

func _clear_receipts(seat: int) -> void:
	for key in receipts.keys():
		if str(key).begins_with(str(seat) + ":"):
			receipts.erase(key)
