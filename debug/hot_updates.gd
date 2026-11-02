extends Node
const Loader = preload("res://sdk/mod_loader.gd")
const Archive = preload("res://debug/archive.gd")
const MAX_SIZE = 16 * 1024 * 1024
const CHUNK = 24576
var app: Object
var directory: String
var uploads := {}
var builds := {}
var active := {}
var previous := {}
var mounts := 0
var loader = Loader.new()
var encoded_pattern := RegEx.new()

func _ready() -> void:
	encoded_pattern.compile("^[A-Za-z0-9+/]+={0,2}\\z")
	DirAccess.make_dir_recursive_absolute(directory.path_join("packages"))
	DirAccess.make_dir_recursive_absolute(directory.path_join("uploads"))
	for name in DirAccess.get_files_at(directory.path_join("uploads")):
		DirAccess.remove_absolute(directory.path_join("uploads").path_join(name))
	_restore()

func _process(_delta: float) -> void:
	for id in uploads.keys():
		if Time.get_ticks_msec() - uploads[id].touched > 120000:
			_abort(id)

func call_method(method: String, params: Dictionary) -> Dictionary:
	match method:
		"mods.upload.begin": return _begin(params)
		"mods.upload.chunk": return _chunk(params)
		"mods.upload.abort":
			if not params.get("upload_id") is String or not uploads.has(params.upload_id):
				return {"error": "unknown_upload"}
			_abort(params.upload_id)
			return {"aborted": true}
		"mods.upload.commit": return _commit(params)
		"mods.activate": return _activate(params)
		"mods.rollback":
			if not params.get("game_id") is String:
				return {"error": "invalid_game_id"}
			var target: String = str(previous.get(params.game_id, ""))
			if target.is_empty():
				return {"error": "no_previous_build"}
			return _activate({"build": target})
		"mods.status": return status()
	return {"error": "method_not_found"}

func status() -> Dictionary:
	var items := []
	for hash in builds:
		items.append(_describe(hash))
	return {"builds": items, "active": active.duplicate(), "previous": previous.duplicate(), "uploads": uploads.size(), "view_state": app.debug_view_state() if app.has_method("debug_view_state") else {}}

func _begin(params: Dictionary) -> Dictionary:
	var size = params.get("size")
	var hash = params.get("sha256")
	if not _integer(size) or size <= 0 or size > _size_limit() or not _hash(hash):
		return {"error": "invalid_upload"}
	if uploads.size() >= 2:
		return {"error": "upload_limit"}
	if builds.has(hash):
		return {"existing": true, "build": hash}
	if DirAccess.get_files_at(directory.path_join("packages")).size() >= 8 or mounts >= 16:
		return {"error": "build_limit_restart_or_clear_storage"}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var path := directory.path_join("uploads").path_join(id + ".part")
	var file := FileAccess.open(path, FileAccess.WRITE_READ)
	if not file:
		return {"error": "storage_unavailable"}
	uploads[id] = {"size": int(size), "sha256": hash, "received": 0, "file": file, "path": path, "touched": Time.get_ticks_msec()}
	return {"upload_id": id, "offset": 0, "chunk_size": CHUNK}

func _chunk(params: Dictionary) -> Dictionary:
	if not params.get("upload_id") is String or not uploads.has(params.upload_id):
		return {"error": "unknown_upload"}
	var upload: Dictionary = uploads[params.upload_id]
	var offset = params.get("offset")
	var encoded = params.get("data")
	if not _integer(offset) or offset < 0 or not encoded is String or encoded.length() > CHUNK * 4 / 3:
		return {"error": "invalid_chunk"}
	if encoded.is_empty() or encoded.length() % 4 != 0:
		return {"error": "invalid_chunk"}
	if encoded_pattern.search(encoded) == null:
		return {"error": "invalid_chunk"}
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.is_empty() or bytes.size() > CHUNK or Marshalls.raw_to_base64(bytes) != encoded or offset + bytes.size() > upload.size:
		return {"error": "invalid_chunk"}
	var file: FileAccess = upload.file
	if offset < upload.received and offset + bytes.size() <= upload.received:
		file.seek(int(offset))
		if file.get_buffer(bytes.size()) == bytes:
			upload.touched = Time.get_ticks_msec()
			return {"offset": upload.received}
	if offset != upload.received:
		return {"error": "offset_mismatch", "offset": upload.received}
	file.seek(upload.received)
	file.store_buffer(bytes)
	if file.get_error() != OK:
		_abort(params.upload_id)
		return {"error": "storage_write_failed"}
	upload.received += bytes.size()
	upload.touched = Time.get_ticks_msec()
	return {"offset": upload.received}

func _commit(params: Dictionary) -> Dictionary:
	if not params.get("upload_id") is String or not uploads.has(params.upload_id):
		return {"error": "unknown_upload"}
	var upload: Dictionary = uploads[params.upload_id]
	if upload.received != upload.size:
		return {"error": "upload_incomplete", "offset": upload.received}
	upload.file.close()
	var path: String = upload.path
	var hash: String = upload.sha256
	if FileAccess.get_sha256(path) != hash:
		_abort(params.upload_id)
		return {"error": "hash_mismatch"}
	if builds.has(hash):
		_abort(params.upload_id)
		return _describe(hash)
	var destination := _package_path(hash)
	if DirAccess.copy_absolute(path, destination) != OK:
		_abort(params.upload_id)
		return {"error": "storage_write_failed"}
	# ZIP pack mounts retain the filename, so mount the immutable final location.
	var info := _mount(destination)
	if info.has("error"):
		DirAccess.remove_absolute(destination)
		_abort(params.upload_id)
		return info
	DirAccess.remove_absolute(path)
	uploads.erase(params.upload_id)
	builds[hash] = info
	if not _save():
		builds.erase(hash)
		return {"error": "catalog_write_failed"}
	return _describe(hash)

func _mount(path: String) -> Dictionary:
	var archive := Archive.inspect(path)
	if archive.has("error"):
		return archive
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"error": "invalid_zip"}
	var manifests := []
	for name in archive.files:
		if name.ends_with("/manifest.json"):
			manifests.append(name)
	if manifests.size() != 1:
		zip.close()
		return {"error": "invalid_manifest"}
	var manifest = JSON.parse_string(zip.read_file(manifests[0]).get_string_from_utf8())
	if not manifest is Dictionary or not manifest.get("id") is String or not manifest.id.is_valid_identifier() or not manifest.get("build_id") is String or not manifest.build_id.is_valid_identifier() or not manifest.get("files") is Array or not manifest.get("rules_files") is Array:
		zip.close()
		return {"error": "invalid_manifest"}
	var prefix: String = "mod_versions/" + manifest.id + "/" + manifest.build_id + "/"
	var allowed := [prefix + "manifest.json"]
	for file in manifest.files:
		if not file is String or not Archive.safe_path(file) or allowed.has(prefix + file):
			zip.close()
			return {"error": "unsafe_manifest_path"}
		allowed.append(prefix + file)
	if allowed.size() != archive.files.size() or manifests[0] != prefix + "manifest.json":
		zip.close()
		return {"error": "namespace_mismatch"}
	for name in archive.files:
		if not allowed.has(name) or zip.read_file(name).size() != archive.files[name]:
			zip.close()
			return {"error": "invalid_archive_files"}
	zip.close()
	var root := "res://" + prefix.trim_suffix("/")
	if FileAccess.file_exists(root.path_join("manifest.json")):
		return {"error": "build_namespace_reused"}
	if mounts >= 16:
		return {"error": "mount_limit"}
	mounts += 1
	if not ProjectSettings.load_resource_pack(path, false):
		return {"error": "mount_failed"}
	var info: Dictionary = loader.inspect(root)
	if info.is_empty():
		return {"error": "invalid_mod: " + loader.error}
	var script = load(root.path_join(info.manifest.view))
	if loader.rules(info) == null or not script is GDScript or not script.can_instantiate() or not ClassDB.is_parent_class(script.get_instance_base_type(), "Control"):
		return {"error": "invalid_scripts"}
	var probe = script.new()
	var valid: bool = probe is Control and probe.has_signal("command") and probe.has_method("render")
	probe.free()
	if not valid:
		return {"error": "invalid_view_contract"}
	return info

func _activate(params: Dictionary) -> Dictionary:
	var hash = params.get("build")
	if not hash is String or not builds.has(hash):
		return {"error": "unknown_build"}
	if not app.has_method("debug_select_build"):
		return {"error": "unsupported_app"}
	var info: Dictionary = builds[hash]
	var game: String = info.manifest.id
	var session = app.get("session")
	var old_info: Dictionary = {}
	if is_instance_valid(session):
		old_info = app.get("mod_info")
		var swapped: Dictionary = app.debug_replace_view(info)
		if swapped.has("error"):
			return swapped
	_builtin(game)
	var old: String = str(active.get(game, "builtin:" + game))
	var old_previous = previous.get(game)
	active[game] = hash
	if old != hash:
		if builds.has(old):
			previous[game] = old
		else:
			previous.erase(game)
	if not _save():
		active[game] = old
		if old_previous == null:
			previous.erase(game)
		else:
			previous[game] = old_previous
		if not old_info.is_empty():
			app.debug_replace_view(old_info)
		return {"error": "catalog_write_failed"}
	app.debug_select_build(info)
	return {"activated": true, "build": hash, "game_id": game, "presentation_only": is_instance_valid(session), "view_state": app.debug_view_state()}

func _describe(hash: String) -> Dictionary:
	var info: Dictionary = builds[hash]
	return {"build": hash, "game_id": info.manifest.id, "build_id": info.manifest.get("build_id", "builtin"), "rules_fingerprint": info.rules_fingerprint, "presentation_fingerprint": info.presentation_fingerprint}

func _abort(id: String) -> void:
	if uploads.has(id):
		var upload: Dictionary = uploads[id]
		upload.file.close()
		DirAccess.remove_absolute(upload.path)
		uploads.erase(id)

func _package_path(hash: String) -> String:
	return directory.path_join("packages").path_join(hash + ".zip")

func _save() -> bool:
	var packages := []
	for hash in builds:
		if not hash.begins_with("builtin:"):
			packages.append(hash)
	var file := FileAccess.open(directory.path_join("catalog.tmp"), FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify({"packages": packages, "active": active, "previous": previous}))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(directory.path_join("catalog.tmp"))
		return false
	return DirAccess.rename_absolute(directory.path_join("catalog.tmp"), directory.path_join("catalog.json")) == OK

func _restore() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json"))) if FileAccess.file_exists(directory.path_join("catalog.json")) else null
	if not catalog is Dictionary or not catalog.get("packages") is Array or catalog.packages.size() > 8:
		return
	for hash in catalog.packages:
		if not _hash(hash) or not FileAccess.file_exists(_package_path(hash)) or FileAccess.get_sha256(_package_path(hash)) != hash:
			continue
		var info := _mount(_package_path(hash))
		if not info.has("error"):
			builds[hash] = info
	for field in ["active", "previous"]:
		var values = catalog.get(field, {})
		if values is Dictionary:
			for game in values:
				if game is String and values[game] is String:
					if values[game] == "builtin:" + game:
						_builtin(game)
					if builds.has(values[game]) and builds[values[game]].manifest.id == game:
						(active if field == "active" else previous)[game] = values[game]
	for game in previous:
		if not active.has(game):
			active[game] = previous[game]
	if app.has_method("debug_select_build"):
		for game in active:
			app.debug_select_build(builds[active[game]])

func _builtin(game: String) -> void:
	if not game.is_valid_identifier():
		return
	var info: Dictionary = loader.inspect("res://mods/" + game) if FileAccess.file_exists("res://mods/" + game + "/manifest.json") else {}
	if not info.is_empty():
		builds["builtin:" + game] = info

func _hash(value) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false) and value == value.to_lower()

func _integer(value) -> bool:
	return (value is int or value is float) and value == int(value)

func _size_limit() -> int:
	return MAX_SIZE
