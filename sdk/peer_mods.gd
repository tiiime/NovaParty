extends Node
signal catalog_received(metadata: Dictionary)
signal progress(received: int, total: int)
signal completed(path: String, metadata: Dictionary)
signal failed(code: String)
const Wire = preload("wire.gd")
const LIMIT = 16 * 1024 * 1024
var wire
var metadata := {}
var expected_session := ""
var destination := ""
var output: FileAccess
var received := 0
var deadline := 0
var downloading := false
var finished := false
var last_keepalive := 0

func _ready() -> void:
	wire = Wire.new()
	add_child(wire)
	wire.opened.connect(func(peer): wire.send(peer, {"type": "catalog", "session_id": expected_session}) if not expected_session.is_empty() else wire.send(peer, {"type": "catalog"}))
	wire.message.connect(_message)
	wire.lost.connect(func(_peer):
		if not finished:
			_fail("transfer_disconnected")
	)

func inspect_remote(address: String, port: int, session_id: String = "") -> Error:
	expected_session = session_id
	deadline = Time.get_ticks_msec() + 10000
	return wire.connect_to(address, port)

func confirm_download() -> void:
	if metadata.is_empty() or downloading or finished:
		return
	DirAccess.make_dir_recursive_absolute("user://mod_downloads")
	destination = "user://mod_downloads/" + Crypto.new().generate_random_bytes(16).hex_encode() + ".part"
	output = FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		_fail("download_storage_failed")
		return
	downloading = true
	_next()

func _next() -> void:
	deadline = Time.get_ticks_msec() + 10000
	wire.send(0, {"type": "package_get", "session_id": metadata.session_id, "sha256": metadata.sha256, "offset": received})

func _message(_peer: int, value: Dictionary) -> void:
	if finished:
		return
	if value.get("type") == "share_error":
		_fail(str(value.get("code", "transfer_failed")))
	elif value.get("type") == "catalog" and metadata.is_empty():
		if value.get("protocol") != 1:
			_fail("invalid_catalog")
			return
		var length = value.get("size")
		if not (length is int or length is float) or length != int(length) or length <= 0 or length > LIMIT:
			_fail("invalid_catalog")
			return
		for key in ["session_id", "game_id", "name", "version", "source_name", "sha256", "rules_fingerprint", "presentation_fingerprint"]:
			if not value.get(key) is String or str(value[key]).length() > 256:
				_fail("invalid_catalog")
				return
		for key in ["sha256", "rules_fingerprint", "presentation_fingerprint"]:
			if value[key].length() != 64 or not value[key].is_valid_hex_number(false):
				_fail("invalid_catalog")
				return
		if value.session_id.length() != 32 or not value.session_id.is_valid_hex_number(false) or not value.game_id.is_valid_identifier() or (not expected_session.is_empty() and value.session_id != expected_session):
			_fail("room_changed")
			return
		metadata = value
		deadline = 0 # Waiting for an explicit user decision has no download timeout.
		catalog_received.emit(metadata)
	elif value.get("type") == "package_chunk" and downloading:
		if value.get("offset") != received or not value.get("data") is String or value.data.length() > 32768:
			_fail("invalid_chunk")
			return
		var bytes := Marshalls.base64_to_raw(value.data)
		if bytes.is_empty() or Marshalls.raw_to_base64(bytes) != value.data or received + bytes.size() > metadata.size:
			_fail("invalid_chunk")
			return
		output.store_buffer(bytes)
		if output.get_error() != OK:
			_fail("download_storage_failed")
			return
		received += bytes.size()
		progress.emit(received, int(metadata.size))
		if received == metadata.size:
			output.close()
			output = null
			if FileAccess.get_sha256(destination) != metadata.sha256:
				_fail("package_hash_mismatch")
				return
			finished = true
			wire.drop(0)
			completed.emit(destination, metadata)
		else:
			_next()

func cancel() -> void:
	finished = true
	if output != null:
		output.close()
		output = null
	if not destination.is_empty():
		DirAccess.remove_absolute(destination)
	if wire != null:
		wire.drop(0)

func _fail(code: String) -> void:
	cancel()
	failed.emit(code)

func _process(_delta: float) -> void:
	if not finished and not downloading and not metadata.is_empty() and Time.get_ticks_msec() - last_keepalive > 3000:
		last_keepalive = Time.get_ticks_msec()
		wire.send(0, {"type": "catalog", "session_id": metadata.session_id})
	if not finished and deadline > 0 and Time.get_ticks_msec() > deadline:
		_fail("transfer_timeout")

func _exit_tree() -> void:
	cancel()
