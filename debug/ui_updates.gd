extends "res://debug/hot_updates.gd"
# UI packages share the authenticated upload transport, never the Mod namespace.
const UI_LIMIT = 64 * 1024 * 1024
const BUILTIN = "builtin:client"
const UI_ENTRY = "app/main.gd"

func _size_limit() -> int:
	return UI_LIMIT

func call_method(method: String, params: Dictionary) -> Dictionary:
	match method:
		"ui.activate": return _activate(params)
		"ui.rollback":
			var target: String = str(previous.get("client", BUILTIN))
			return _activate({"build": target})
		"ui.status": return status()
	# Reuse bounded chunking, SHA-256 and immutable files, with a separate catalog.
	return super.call_method(method.replace("ui.upload.", "mods.upload."), params)

func status() -> Dictionary:
	var value := super.status()
	value["runtime"] = app.debug_ui_status()
	value["max_package_bytes"] = UI_LIMIT
	return value

func _mount(path: String) -> Dictionary:
	var archive := Archive.inspect(path, UI_LIMIT, 128 * 1024 * 1024, UI_LIMIT)
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
		return {"error": "invalid_ui_manifest"}
	var manifest = JSON.parse_string(zip.read_file(manifests[0]).get_string_from_utf8())
	if not manifest is Dictionary or manifest.get("kind") != "client_ui" or manifest.get("ui_api") != 1 or manifest.get("sdk") != 1 or manifest.get("engine") != Engine.get_version_info().string or manifest.get("entry") != UI_ENTRY or not manifest.get("build_id") is String or not manifest.build_id.is_valid_identifier() or not manifest.get("files") is Array:
		zip.close()
		return {"error": "incompatible_ui_manifest"}
	var prefix: String = "ui_versions/" + manifest.build_id + "/"
	var allowed := [prefix + "manifest.json"]
	for name in manifest.files:
		if not name is String or not Archive.safe_path(name) or allowed.has(prefix + name) or not (name.begins_with("app/") or name.begins_with("assets/") or name.begins_with("i18n/")) or name in ["app/bootstrap.gd", "app/bootstrap.tscn"]:
			zip.close()
			return {"error": "invalid_ui_file"}
		allowed.append(prefix + name)
	if manifests[0] != prefix + "manifest.json" or allowed.size() != archive.files.size() or not manifest.files.has(UI_ENTRY):
		zip.close()
		return {"error": "namespace_mismatch"}
	for name in archive.files:
		if not allowed.has(name) or zip.read_file(name).size() != archive.files[name]:
			zip.close()
			return {"error": "invalid_archive_files"}
	# Reject malformed/missing translations before they can replace global catalogs.
	var catalog_keys: Array = []
	for locale in ["zh_CN", "en"]:
		var catalog_path: String = prefix + "i18n/" + locale + ".json"
		if not allowed.has(catalog_path):
			zip.close()
			return {"error": "missing_ui_catalog"}
		var messages = JSON.parse_string(zip.read_file(catalog_path).get_string_from_utf8())
		if not messages is Dictionary or messages.is_empty():
			zip.close()
			return {"error": "invalid_ui_catalog"}
		for required in ["APP_NAME", "START_GAME", "JOIN_GAME", "SETTINGS", "BACK", "LAUNCH_GAME", "ADD_GAME"]:
			if not messages.has(required):
				zip.close()
				return {"error": "invalid_ui_catalog"}
		var keys: Array = messages.keys()
		keys.sort()
		if not catalog_keys.is_empty() and keys != catalog_keys:
			zip.close()
			return {"error": "invalid_ui_catalog"}
		catalog_keys = keys
		for key in messages:
			if not key is String or not messages[key] is String:
				zip.close()
				return {"error": "invalid_ui_catalog"}
	zip.close()
	var root := "res://" + prefix.trim_suffix("/")
	if FileAccess.file_exists(root.path_join("manifest.json")):
		return {"error": "build_namespace_reused"}
	if mounts >= 16:
		return {"error": "mount_limit"}
	mounts += 1
	if not ProjectSettings.load_resource_pack(path, false):
		return {"error": "mount_failed"}
	var script = load(root.path_join(UI_ENTRY))
	if not script is GDScript or not script.can_instantiate() or not ClassDB.is_parent_class(script.get_instance_base_type(), "Control") or script.get_script_constant_map().get("UI_API") != 1:
		return {"error": "invalid_ui_entry"}
	return {"root": root, "manifest": manifest}

func _activate(params: Dictionary) -> Dictionary:
	var hash = params.get("build")
	if not hash is String or not builds.has(hash):
		return {"error": "unknown_build"}
	if not app.has_method("debug_replace_client_ui"):
		return {"error": "ui_host_upgrade_required"}
	var old: String = str(active.get("client", BUILTIN))
	if old == hash:
		return {"activated": true, "build": hash, "unchanged": true}
	var guard := FileAccess.open(directory.path_join("booting.json"), FileAccess.WRITE)
	if not guard:
		return {"error": "storage_unavailable"}
	guard.store_string(JSON.stringify({"build": hash, "fallback": old}))
	guard.close()
	var result: Dictionary = app.debug_replace_client_ui(builds[hash].root.path_join(UI_ENTRY), hash)
	if result.has("error"):
		DirAccess.remove_absolute(directory.path_join("booting.json"))
		return result
	var old_previous = previous.get("client")
	active.client = hash
	previous.client = old
	if not _save():
		active.client = old
		if old_previous == null:
			previous.erase("client")
		else:
			previous.client = old_previous
		app.debug_replace_client_ui(builds[old].root.path_join(UI_ENTRY), old)
		DirAccess.remove_absolute(directory.path_join("booting.json"))
		return {"error": "catalog_write_failed"}
	DirAccess.remove_absolute(directory.path_join("booting.json"))
	return result

func _describe(hash: String) -> Dictionary:
	var info: Dictionary = builds[hash]
	return {"build": hash, "build_id": info.manifest.get("build_id", "builtin"), "kind": "client_ui", "ui_api": 1}

func _restore() -> void:
	builds[BUILTIN] = {"root": "res://", "manifest": {"build_id": "builtin"}}
	active.client = BUILTIN
	var path := directory.path_join("catalog.json")
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not catalog is Dictionary or not catalog.get("packages") is Array or catalog.packages.size() > 8:
		return
	for hash in catalog.packages:
		if not _hash(hash) or not FileAccess.file_exists(_package_path(hash)) or FileAccess.get_sha256(_package_path(hash)) != hash:
			continue
		var info := _mount(_package_path(hash))
		if not info.has("error"):
			builds[hash] = info
	var target: String = str(catalog.get("active", {}).get("client", BUILTIN))
	var fallback: String = str(catalog.get("previous", {}).get("client", BUILTIN))
	var boot_path := directory.path_join("booting.json")
	if FileAccess.file_exists(boot_path):
		var interrupted = JSON.parse_string(FileAccess.get_file_as_string(boot_path))
		if interrupted is Dictionary and builds.has(interrupted.get("fallback", "")):
			fallback = interrupted.fallback
		# A process died during UI preparation: do not try that candidate again.
		target = fallback
		DirAccess.remove_absolute(boot_path)
	if not builds.has(fallback):
		fallback = BUILTIN
	if not builds.has(target):
		target = fallback
	previous.client = fallback
	if target != BUILTIN:
		var result := _activate({"build": target})
		if result.has("error") and fallback != BUILTIN:
			_activate({"build": fallback})
		# Restore the persisted rollback target; startup is not a new user activation.
		previous.client = fallback
	_save()
