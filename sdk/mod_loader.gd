extends RefCounted

const SDK_VERSION = 1
const Archive = preload("package_archive.gd")
var error := ""

func inspect(root: String, archive: ZIPReader = null) -> Dictionary:
	error = ""
	var manifest_path := root.path_join("manifest.json")
	# Older UI packs may still probe games no longer bundled with the base app.
	if archive == null and not FileAccess.file_exists(manifest_path):
		return _fail(tr("LDR_INVALID_MANIFEST"))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path) if archive == null else archive.read_file(manifest_path.trim_prefix("res://")).get_string_from_utf8())
	if not manifest is Dictionary:
		return _fail(tr("LDR_INVALID_MANIFEST"))
	if not manifest.get("name") is String or manifest.name.is_empty() or manifest.name.length() > 128 or not manifest.get("version") is String or manifest.version.is_empty():
		return _fail(tr("LDR_MISSING_NAME_VERSION"))
	if manifest.get("sdk") != SDK_VERSION or not manifest.get("id") is String:
		return _fail(tr("LDR_UNSUPPORTED_SDK"))
	var version_root := "res://mod_versions/" + str(manifest.id) + "/" + str(manifest.get("build_id", ""))
	if not manifest.id.is_valid_identifier() or (root != "res://mods/" + manifest.id and (root != version_root or not str(manifest.get("build_id", "")).is_valid_identifier())):
		return _fail(tr("LDR_PACKAGE_PATH"))
	if not manifest.get("files") is Array or manifest.files.size() > 128:
		return _fail(tr("LDR_INVALID_FILES"))
	for entry in [manifest.get("rules", ""), manifest.get("view", "")]:
		if not manifest.files.has(entry) or not str(entry).ends_with(".gd"):
			return _fail(tr("LDR_MISSING_ENTRY"))
	var drop_in: bool = manifest.get("session_mode", "") == "drop_in"
	var bounds = manifest.get("players", {})
	var valid_bounds: bool = bounds is Dictionary and ((bounds.get("min") == 2 and bounds.get("max") == 2) or (drop_in and bounds.get("min") == 1 and bounds.get("max") is float and bounds.max == int(bounds.max) and bounds.max >= 2 and bounds.max <= 8))
	if not valid_bounds:
		return _fail(tr("LDR_TWO_PLAYERS"))
	if manifest.files.size() != _unique_count(manifest.files):
		return _fail(tr("LDR_DUPLICATE_FILES"))
	var hashes := []
	var names = manifest.files.duplicate()
	names.sort()
	for name in names:
		if not name is String or name.is_empty() or name.contains("..") or name.contains(":") or name.begins_with("/") or name.contains("\\"):
			return _fail(tr("LDR_UNSAFE_PATH"))
		var path: String = root.path_join(name)
		if not (FileAccess.file_exists(path) if archive == null else archive.get_files().has(path.trim_prefix("res://"))):
			return _fail(tr("LDR_MISSING_RESOURCE") + name)
		hashes.append(name + ":" + _content_hash(path, archive))
	# Manifest bytes are part of compatibility, including configuration and entrypoints.
	var fingerprint := (_content_hash(manifest_path, archive) + "\n" + "\n".join(hashes)).sha256_text()
	var rule_files = manifest.get("rules_files", manifest.files)
	if not rule_files is Array or rule_files.is_empty() or _unique_count(rule_files) != rule_files.size() or not rule_files.has(manifest.rules):
		return _fail(tr("LDR_INVALID_RULE_FILES"))
	var rule_hashes := []
	var ordered = rule_files.duplicate()
	ordered.sort()
	for name in ordered:
		if not manifest.files.has(name):
			return _fail(tr("LDR_RULE_DEPENDENCY"))
		rule_hashes.append(name + ":" + _content_hash(root.path_join(name), archive))
	var rule_metadata: Dictionary = manifest.duplicate(true)
	for name in ["name", "version", "view", "files", "build_id", "inputs", "localized_names", "cover"]:
		rule_metadata.erase(name)
	var rules_fingerprint := (JSON.stringify(rule_metadata, "", true) + "\n" + "\n".join(rule_hashes)).sha256_text()
	var presentation_hashes := []
	for name in names:
		if not rule_files.has(name):
			presentation_hashes.append(name + ":" + _content_hash(root.path_join(name), archive))
	var presentation_fingerprint := (str(manifest.view) + "\n" + "\n".join(presentation_hashes)).sha256_text()
	return {"manifest": manifest, "root": root, "fingerprint": fingerprint, "rules_fingerprint": rules_fingerprint, "presentation_fingerprint": presentation_fingerprint}

func rules(info: Dictionary):
	var script = load(info.root.path_join(info.manifest.rules))
	if not script is GDScript or not script.can_instantiate():
		error = tr("LDR_INVALID_RULES")
		return null
	var instance = script.new()
	for method in ["initial_state", "apply", "view_for"]:
		if not instance.has_method(method):
			error = tr("LDR_MISSING_RULE_METHOD") + method
			return null
	return instance

func mount_zip(path: String) -> String:
	error = ""
	if Archive.inspect(path).has("error"):
		error = tr("LDR_OPEN_ZIP")
		return ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		error = tr("LDR_OPEN_ZIP")
		return ""
	var entries := zip.get_files()
	var manifests := []
	for entry in entries:
		if entry.ends_with("/manifest.json"):
			manifests.append(entry)
	if manifests.size() != 1:
		zip.close()
		error = tr("LDR_ZIP_MANIFEST_COUNT")
		return ""
	var manifest = JSON.parse_string(zip.read_file(manifests[0]).get_string_from_utf8())
	if not manifest is Dictionary or not manifest.get("id") is String:
		zip.close()
		error = tr("LDR_ZIP_MANIFEST")
		return ""
	var versioned: bool = manifest.get("build_id") is String and str(manifest.build_id).is_valid_identifier()
	var prefix: String = ("mod_versions/" + manifest.id + "/" + manifest.build_id + "/") if versioned else ("mods/" + manifest.id + "/")
	if manifest.id.is_empty() or not manifest.id.is_valid_identifier() or manifests[0] != prefix + "manifest.json":
		zip.close()
		error = tr("LDR_NAMESPACE")
		return ""
	if not manifest.get("files") is Array:
		zip.close()
		error = tr("LDR_NO_FILES")
		return ""
	var allowed := [prefix + "manifest.json"]
	for name in manifest.files:
		allowed.append(prefix + str(name))
	if entries.size() != allowed.size():
		zip.close()
		error = tr("LDR_FILE_MISMATCH")
		return ""
	for entry in entries:
		if not allowed.has(entry) or not entry.begins_with(prefix) or entry.contains("..") or entry.contains("\\"):
			zip.close()
			error = tr("LDR_ZIP_NAMESPACE")
			return ""
	var root := "res://" + prefix.trim_suffix("/")
	var incoming := inspect(root, zip)
	zip.close()
	if incoming.is_empty():
		return ""
	if FileAccess.file_exists(root.path_join("manifest.json")) and versioned:
		# Reuse only byte-identical content in an immutable namespace.
		var existing := inspect(root)
		if not existing.is_empty() and existing.fingerprint == incoming.fingerprint:
			return root
		error = tr("LDR_ALREADY_LOADED")
		return ""
	if FileAccess.file_exists(root.path_join("manifest.json")):
		error = tr("LDR_ALREADY_LOADED")
		return ""
	if not ProjectSettings.load_resource_pack(path, false):
		error = tr("LDR_MOUNT_ZIP")
		return ""
	return root

func _fail(message: String) -> Dictionary:
	error = message
	return {}

func _unique_count(values: Array) -> int:
	var unique := {}
	for value in values:
		if not value is String:
			return -1
		unique[value] = true
	return unique.size()

# Copy SAF content URIs into private app storage before opening as ZIP.
func install_zip(source: String) -> Dictionary:
	error = ""
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return _fail(tr("LDR_READ_PACKAGE"))
	var length := input.get_length()
	if length <= 0 or length > 16 * 1024 * 1024:
		return _fail(tr("LDR_PACKAGE_SIZE"))
	var bytes := input.get_buffer(length)
	if bytes.size() != length:
		return _fail(tr("LDR_INCOMPLETE_PACKAGE"))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var name := hash.finish().hex_encode() + ".zip"
	var directory := "user://mods"
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _fail(tr("LDR_STORAGE_DIRECTORY"))
	var destination := directory.path_join(name)
	var existed := FileAccess.file_exists(destination)
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return _fail(tr("LDR_SAVE_PACKAGE"))
	output.store_buffer(bytes)
	output.close()
	var mod_root := mount_zip(destination)
	if mod_root.is_empty():
		if not existed:
			DirAccess.remove_absolute(destination)
		return {}
	var info := inspect(mod_root)
	if info.is_empty():
		DirAccess.remove_absolute(destination)
	return info

func installed_packages() -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute("user://mods"):
		return result
	for filename in DirAccess.get_files_at("user://mods"):
		if filename.ends_with(".zip"):
			result.append("user://mods/" + filename)
	result.sort()
	return result

# Download confirmation belongs to the caller. Validate in the ZIP before persisting or mounting.
func install_peer_zip(path: String, expected: Dictionary) -> Dictionary:
	if FileAccess.get_sha256(path) != expected.get("sha256", "") or Archive.inspect(path).has("error"):
		return _fail("package_hash_mismatch")
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return _fail("invalid_package")
	var manifests := []
	for entry in zip.get_files():
		if entry.ends_with("/manifest.json"):
			manifests.append(entry)
	if manifests.size() != 1:
		zip.close()
		return _fail("invalid_package")
	var root: String = "res://" + str(manifests[0]).get_base_dir()
	var info := inspect(root, zip)
	zip.close()
	if info.is_empty() or info.manifest.id != expected.get("game_id") or info.rules_fingerprint != expected.get("rules_fingerprint") or info.presentation_fingerprint != expected.get("presentation_fingerprint"):
		return _fail("package_fingerprint_mismatch")
	if FileAccess.file_exists(root.path_join("manifest.json")):
		var existing := inspect(root)
		if existing.is_empty() or existing.fingerprint != info.fingerprint:
			return _fail("namespace_conflict")
	return install_zip(path)

func _content_hash(path: String, archive: ZIPReader) -> String:
	if archive == null:
		return FileAccess.get_sha256(path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(archive.read_file(path.trim_prefix("res://")))
	return context.finish().hex_encode()
