extends RefCounted
# Ordinary LAN SDK endpoint, available in Release. Shares only the active Mod.
const LIMIT = 16 * 1024 * 1024
const CHUNK = 24576
var cached := {}
var source := ""

func offer(info: Dictionary) -> Dictionary:
	if source == info.fingerprint and not cached.is_empty():
		return cached
	var manifest: Dictionary = info.manifest.duplicate(true)
	manifest.build_id = "p_" + str(info.fingerprint).left(32)
	var prefix: String = "mod_versions/" + manifest.id + "/" + manifest.build_id + "/"
	var directory := "user://shared_mods"
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(manifest.build_id + ".zip")
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return {"error": "share_storage_failed"}
	var entries: Dictionary = {"manifest.json": JSON.stringify(manifest, "", true).to_utf8_buffer()}
	var expanded: int = entries["manifest.json"].size()
	for name in manifest.files:
		var file := FileAccess.open(str(info.root).path_join(name), FileAccess.READ)
		if file == null or file.get_length() > LIMIT:
			zip.close()
			return {"error": "share_resource_unavailable"}
		var bytes := file.get_buffer(file.get_length())
		expanded += bytes.size()
		if expanded > 32 * 1024 * 1024:
			zip.close()
			return {"error": "share_too_large"}
		entries[name] = bytes
	var names := entries.keys()
	names.sort()
	for name in names:
		if zip.start_file(prefix + name) != OK or zip.write_file(entries[name]) != OK or zip.close_file() != OK:
			zip.close()
			return {"error": "share_storage_failed"}
	zip.close()
	var package := FileAccess.open(path, FileAccess.READ)
	if package == null or package.get_length() <= 0 or package.get_length() > LIMIT:
		return {"error": "share_too_large"}
	source = info.fingerprint
	cached = {"path": path, "sha256": FileAccess.get_sha256(path), "size": package.get_length()}
	return cached

func handle(peer: int, request: Dictionary, wire, room, info: Dictionary, join_game: bool = true) -> bool:
	if request.get("type") not in ["catalog", "package_get"]:
		return false
	if request.get("session_id", room.game_session_id) != room.game_session_id:
		wire.send(peer, {"type": "share_error", "code": "room_changed"})
		return true
	var package := offer(info)
	if package.has("error"):
		wire.send(peer, {"type": "share_error", "code": package.error})
		return true
	if request.type == "catalog":
		wire.send(peer, {"type": "catalog", "protocol": 1, "kind": "game" if join_game else "mod", "session_id": room.game_session_id, "game_id": info.manifest.id, "name": info.manifest.name, "localized_names": info.manifest.get("localized_names", {}), "version": info.manifest.version, "source_name": room.players[0].nickname, "rules_fingerprint": info.rules_fingerprint, "presentation_fingerprint": info.presentation_fingerprint, "sha256": package.sha256, "size": package.size})
	else:
		var offset = request.get("offset")
		if request.get("sha256") != package.sha256 or not (offset is int or offset is float) or offset != int(offset) or offset < 0 or offset >= package.size:
			wire.send(peer, {"type": "share_error", "code": "invalid_package_request"})
		else:
			var file := FileAccess.open(package.path, FileAccess.READ)
			file.seek(int(offset))
			var bytes := file.get_buffer(mini(CHUNK, int(package.size) - int(offset)))
			wire.send(peer, {"type": "package_chunk", "offset": offset, "data": Marshalls.raw_to_base64(bytes)})
	return true
