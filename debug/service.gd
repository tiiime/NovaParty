extends Node
# Excluded from Release exports. No shell/eval; only trusted Mod packages.
const Wire = preload("res://sdk/wire.gd")
const Loader = preload("res://sdk/mod_loader.gd")
const METHODS = ["qr.image", "qr.decode_image", "qr.status", "qr.scan", "qr.stop", "qr.join", "lan.search", "lan.status", "lan.inspect", "lan.confirm_download", "lan.cancel", "ui.status", "ui.updates", "ui.upload.begin", "ui.upload.chunk", "ui.upload.abort", "ui.upload.commit", "ui.activate", "ui.rollback", "device.info", "debug.capabilities", "room.status", "room.create", "room.join", "room.leave", "room.reconnect", "game.snapshot", "game.describe_actions", "game.submit", "game.result", "events.subscribe", "events.unsubscribe", "mods.upload.begin", "mods.upload.chunk", "mods.upload.abort", "mods.upload.commit", "mods.status", "mods.activate", "mods.rollback"]
var app: Object
var wire
var hot_updates
var ui_updates
var room_control
var session_generation := 0
var endpoint := "disabled"
var token := ""
var app_instance_id := Crypto.new().generate_random_bytes(16).hex_encode()
var clients := {}
var current_session
var sequence := 0
var events := []
var results := {}
var result_order := []
var connection_path := "user://debug/connection.json"
var apk_server
var apk_http := {}

func _exit_tree() -> void:
	if apk_server != null:
		apk_server.close()

func _ready() -> void:
	if not OS.is_debug_build() or not OS.has_feature("novaparty_debug"):
		set_process(false)
		return
	var bind_address := "127.0.0.1"
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			bind_address = ip
			break
	var advertised_address := bind_address
	var listen_path := "user://debug/listen.json"
	if FileAccess.file_exists(listen_path):
		var settings = JSON.parse_string(FileAccess.get_file_as_string(listen_path))
		if settings is Dictionary and settings.get("bind") is String and settings.bind.is_valid_ip_address():
			bind_address = settings.bind
	var listen_port := 27841
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--debug-bind="):
			bind_address = argument.trim_prefix("--debug-bind=")
		if argument.begins_with("--debug-port="):
			listen_port = int(argument.trim_prefix("--debug-port="))
		if argument.begins_with("--debug-connection="):
			connection_path = argument.trim_prefix("--debug-connection=")
	wire = Wire.new()
	add_child(wire)
	wire.opened.connect(func(peer): clients[peer] = {"authenticated": false, "subscribed": false, "since": Time.get_ticks_msec(), "window": Time.get_ticks_msec(), "requests": 0})
	wire.lost.connect(func(peer): clients.erase(peer))
	wire.message.connect(_message)
	var error: Error = wire.listen(listen_port, bind_address)
	if error != OK:
		endpoint = "unavailable (" + str(error) + ")"
		return
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	endpoint = bind_address + ":" + str(listen_port)
	if OS.has_feature("android"):
		var klass = Engine.get_singleton("JavaClassWrapper").wrap("org.novaparty.debug.ApkUpdateServer")
		if klass != null:
			apk_server = klass.ApkUpdateServer(Engine.get_singleton("AndroidRuntime").getActivity())
			var http_error := str(apk_server.start(bind_address, listen_port + 1, token))
			if http_error.is_empty():
				apk_http = {"port": listen_port + 1, "upload_path": "/debug/apk", "status_path": "/debug/apk/status", "max_bytes": 201326592}
	DirAccess.make_dir_recursive_absolute(connection_path.get_base_dir())
	var file := FileAccess.open(connection_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"host": advertised_address if bind_address == "0.0.0.0" else bind_address, "port": listen_port, "token": token, "app_instance_id": app_instance_id, "apk_http": apk_http}))
		file.close()
		# Unix developer machines: private credentials. Android uses private app storage.
		if OS.get_name() in ["macOS", "Linux"]:
			OS.execute("chmod", ["600", ProjectSettings.globalize_path(connection_path)])
	room_control = load("res://debug/room_control.gd").new()
	room_control.app = app
	hot_updates = load("res://debug/hot_updates.gd").new()
	hot_updates.app = app
	hot_updates.directory = connection_path.get_base_dir().path_join("hot")
	add_child(hot_updates)
	if app.has_method("debug_replace_client_ui"):
		ui_updates = load("res://debug/ui_updates.gd").new()
		ui_updates.app = app
		ui_updates.directory = connection_path.get_base_dir().path_join("ui-hot")
		add_child(ui_updates)

func _process(_delta: float) -> void:
	if apk_server != null:
		apk_server.poll()
	if not wire:
		return
	_sync_session()
	for peer in clients.keys():
		if not clients[peer].authenticated and Time.get_ticks_msec() - clients[peer].since > 5000:
			wire.drop(peer)

func _sync_session() -> void:
	var candidate = app.get("session")
	if not is_instance_valid(candidate):
		candidate = null
	if candidate == current_session:
		return
	if is_instance_valid(current_session):
		current_session.updated.disconnect(_updated)
		current_session.action_result.disconnect(_receipt)
		current_session.notice.disconnect(_notice)
		current_session.status_changed.disconnect(_connection_status)
	current_session = candidate
	session_generation += 1
	results.clear()
	result_order.clear()
	if current_session:
		current_session.updated.connect(_updated)
		current_session.action_result.connect(_receipt)
		current_session.notice.connect(_notice)
		current_session.status_changed.connect(_connection_status)
	_event("state", _snapshot())

func _connection_status(_state: String, _code: String) -> void:
	_event("connection", _snapshot())

func _notice(message: String) -> void:
	_event("notice", {"message": message})

func _updated(_snapshot_value: Dictionary) -> void:
	_event("state", _snapshot())

func _snapshot() -> Dictionary:
	var generation = app.get("room_generation")
	var metadata := {"app_instance_id": app_instance_id, "room_generation": generation if generation is int else session_generation, "local_session_id": "", "in_room": false, "session_state": "lobby"}
	if not is_instance_valid(current_session):
		return metadata
	metadata.local_session_id = current_session.local_session_id
	metadata.game_id = current_session.info.manifest.id
	metadata.host = current_session.host
	metadata.connected = current_session.host or current_session.wire.peers.has(0)
	metadata.session_state = current_session.connection_state
	metadata.connection_error = current_session.connection_error
	if current_session.snapshot.is_empty():
		return metadata
	var value: Dictionary = current_session.snapshot.duplicate(true)
	value.merge(metadata, true)
	value.in_room = true
	value.fingerprint = current_session.info.fingerprint
	value.game_id = current_session.info.manifest.id
	value.rules_fingerprint = current_session.info.rules_fingerprint
	var presentation: Dictionary = app.get("mod_info") if app.get("mod_info") is Dictionary else current_session.info
	if presentation.is_empty():
		presentation = current_session.info
	value.presentation_fingerprint = presentation.presentation_fingerprint
	value.build_id = presentation.manifest.get("build_id", "builtin")
	value.host = current_session.host
	value.connected = current_session.host or current_session.wire.peers.has(0)
	return value

func _receipt(value: Dictionary) -> void:
	var receipt := value.duplicate(true)
	receipt.game_session_id = current_session.snapshot.get("game_session_id", "")
	receipt.state_epoch = current_session.snapshot.get("state_epoch", 0)
	var request: String = str(receipt.get("request_id", ""))
	if not results.has(request):
		result_order.append(request)
	results[request] = receipt
	while result_order.size() > 256:
		results.erase(result_order.pop_front())
	_event("action_result", receipt)

func _event(kind: String, payload: Dictionary) -> void:
	sequence += 1
	var event := {"seq": sequence, "app_instance_id": app_instance_id, "kind": kind, "data": payload}
	events.append(event)
	if events.size() > 128:
		events.pop_front()
	for peer in clients.keys():
		if clients[peer].authenticated and clients[peer].subscribed:
			wire.send(peer, {"jsonrpc": "2.0", "method": "event", "params": event})

func _error(peer: int, id, code: int, message: String) -> void:
	wire.send(peer, {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})

func _message(peer: int, request: Dictionary) -> void:
	if not clients.has(peer):
		return
	var id = request.get("id")
	if request.get("jsonrpc") != "2.0" or not (id is String or id is int or id is float) or not request.get("method") is String or not request.get("params", {}) is Dictionary:
		_error(peer, id, -32600, "invalid_request")
		return
	var client: Dictionary = clients[peer]
	if Time.get_ticks_msec() - client.window >= 1000:
		client.window = Time.get_ticks_msec()
		client.requests = 0
	client.requests += 1
	if client.requests > 60:
		wire.drop(peer)
		return
	var method: String = request.method
	var params: Dictionary = request.get("params", {})
	if not client.authenticated:
		if method != "auth" or params.get("token") != token or token.is_empty():
			wire.drop(peer)
			return
		client.authenticated = true
		_reply(peer, id, {"authenticated": true, "app_instance_id": app_instance_id})
		return
	_sync_session()
	var state := _snapshot()
	if method in ["room.create", "room.join", "room.leave", "room.reconnect"]:
		var result: Dictionary = room_control.handle(method, params, state)
		_sync_session()
		if result.has("error"):
			_error(peer, id, -32011, result.error)
		else:
			_reply(peer, id, result)
		return
	if (method.begins_with("lan.") or method.begins_with("qr.")) and app.has_method("debug_lan_command"):
		var result: Dictionary = app.debug_lan_command(method, params)
		if result.has("error"):
			_error(peer, id, -32011, result.error)
		else:
			_reply(peer, id, result)
		return
	if method.begins_with("ui.") and method != "ui.status" and METHODS.has(method):
		if ui_updates == null:
			_error(peer, id, -32010, "ui_host_upgrade_required")
			return
		var result: Dictionary = ui_updates.call_method("ui.status" if method == "ui.updates" else method, params)
		if result.has("error"):
			_error(peer, id, -32010, result.error)
		else:
			_reply(peer, id, result)
			if method in ["ui.activate", "ui.rollback"]:
				_event("client_ui_changed", result)
		return
	if method.begins_with("mods.") and METHODS.has(method):
		var result: Dictionary = hot_updates.call_method(method, params)
		if result.has("error"):
			_error(peer, id, -32010, result.error)
		else:
			_reply(peer, id, result)
			if method in ["mods.activate", "mods.rollback"]:
				_event("presentation_changed", result)
		return
	match method:
		"ui.status":
			if app.has_method("debug_ui_status"):
				_reply(peer, id, app.debug_ui_status())
			else:
				_error(peer, id, -32001, "unsupported_app")
		"device.info":
			_reply(peer, id, {"app_instance_id": app_instance_id, "os": OS.get_name(), "model": OS.get_model_name(), "version": ProjectSettings.get_setting("application/config/version"), "mode": "play"})
		"debug.capabilities":
			_reply(peer, id, {"protocol": 1, "methods": METHODS, "mode": "play", "session_modes": ["two_player", "drop_in", "fixed"], "apk_http": apk_http, "hot_update": {"upload": true, "presentation": true, "live_rules": false, "client_ui": ui_updates != null, "ui_api": 1, "max_ui_package_bytes": 67108864, "max_package_bytes": 16777216, "chunk_bytes": 24576}, "event_capacity": 128, "result_capacity": 256})
		"room.status":
			var status := state.duplicate(true)
			status.erase("view")
			_reply(peer, id, status)
		"game.snapshot":
			_reply(peer, id, state)
		"game.describe_actions":
			if not state.in_room:
				_error(peer, id, -32001, "not_ready")
				return
			var logic = Loader.new().rules(current_session.info)
			var description: Dictionary = logic.describe_actions(state.view.duplicate(true), int(state.seat)) if logic != null and logic.has_method("describe_actions") else {"supported": false}
			if not state.connected or (current_session.info.manifest.get("session_mode", "") == "" and (state.players.size() < 2 or not state.players[0].connected or not state.players[1].connected)):
				description.legal_actions = []
				description.blocked_by = "waiting_for_players" if state.players.size() < 2 else "disconnected"
			description.context = {"game_session_id": state.get("game_session_id", ""), "state_epoch": state.get("state_epoch", 0), "expected_revision": state.revision}
			_reply(peer, id, description)
		"game.submit":
			if not _valid_command(params):
				_error(peer, id, -32602, "invalid_command")
				return
			if not state.in_room or params.game_session_id != state.get("game_session_id", "") or params.state_epoch != state.get("state_epoch", 0):
				_error(peer, id, -32002, "stale_context")
				return
			var command := {"request_id": params.request_id, "game_session_id": params.game_session_id, "state_epoch": params.state_epoch, "expected_revision": params.expected_revision, "action": params.action}
			# queued is not an acceptance receipt. Observe action_result or game.result.
			_reply(peer, id, current_session.submit_request(command))
		"game.result":
			if not params.get("request_id") is String or params.get("game_session_id") != state.get("game_session_id", ""):
				_error(peer, id, -32602, "invalid_context")
				return
			_reply(peer, id, results.get(params.request_id, {"status": "unknown"}))
		"events.subscribe":
			var after = params.get("after_seq", sequence)
			if not _integer(after) or after < 0:
				_error(peer, id, -32602, "invalid_cursor")
				return
			var resync: bool = params.get("app_instance_id", app_instance_id) != app_instance_id or after > sequence or (not events.is_empty() and after < events[0].seq - 1)
			client.subscribed = true
			_reply(peer, id, {"seq": sequence, "app_instance_id": app_instance_id, "resync_required": resync, "snapshot": state})
			if not resync:
				for event in events:
					if event.seq > after:
						wire.send(peer, {"jsonrpc": "2.0", "method": "event", "params": event})
		"events.unsubscribe":
			client.subscribed = false
			_reply(peer, id, {"subscribed": false})
		_:
			_error(peer, id, -32601, "method_not_found")

func _integer(value) -> bool:
	return (value is int or value is float) and value == int(value)

func _valid_command(params: Dictionary) -> bool:
	return params.get("request_id") is String and not params.request_id.is_empty() and params.request_id.length() <= 128 and params.get("game_session_id") is String and not params.game_session_id.is_empty() and _integer(params.get("state_epoch")) and _integer(params.get("expected_revision")) and params.get("action") is Dictionary

func _reply(peer: int, id, result: Dictionary) -> void:
	wire.send(peer, {"jsonrpc": "2.0", "id": id, "result": result})
