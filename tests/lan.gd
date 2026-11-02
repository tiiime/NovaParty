extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Sharing = preload("res://sdk/mod_sharing.gd")
const Archive = preload("res://sdk/package_archive.gd")
const Code = preload("res://sdk/join_code.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL LAN: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var loader := Loader.new()
	for game in ["gomoku", "hidden_cards", "jump_rope"]:
		var info := loader.inspect("res://mods/" + game)
		var sharing := Sharing.new()
		var package := sharing.offer(info)
		check(not package.has("error"), "active Mod can be packaged")
		check(sharing.offer(info) == package, "package is immutable within offer")
		check(not Archive.inspect(package.path).has("error"), "bounded ZIP validates")
		var zip := ZIPReader.new()
		zip.open(package.path)
		var prefix: String = str(zip.get_files()[0]).get_base_dir()
		var transported := loader.inspect("res://" + prefix, zip)
		check(not transported.is_empty() and transported.rules_fingerprint == info.rules_fingerprint and transported.presentation_fingerprint == info.presentation_fingerprint, "source and portable namespace fingerprints match")
		zip.close()
		var expected := {"sha256": package.sha256, "game_id": game, "rules_fingerprint": info.rules_fingerprint, "presentation_fingerprint": info.presentation_fingerprint}
		var destination: String = "user://mods/" + str(package.sha256) + ".zip"
		var existed := FileAccess.file_exists(destination)
		expected.rules_fingerprint = "bad"
		check(loader.install_peer_zip(package.path, expected).is_empty(), "mismatched rules rejected before mount")
		check(FileAccess.file_exists(destination) == existed, "rejected package is never persisted")
	var bad := "user://lan-unsafe.zip"
	var zip := ZIPPacker.new()
	zip.open(bad)
	zip.start_file("mods/test/../escape.gd")
	zip.write_file("unsafe".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(Archive.inspect(bad).has("error"), "ZIP traversal rejected")
	DirAccess.remove_absolute(bad)
	var sid := "0123456789abcdef0123456789abcdef"
	var uri := Code.encode("192.0.2.10", 27840, sid)
	check(uri.begins_with("novaparty://join?"), "invitation uses NovaParty scheme")
	check(Code.decode(uri) == {"address": "192.0.2.10", "port": 27840, "session_id": sid}, "connection QR URI round trip")
	check(not uri.contains("token") and not uri.contains("player"), "invite has no credentials")
	for value in ["https://example.com", uri + "&port=2", uri.replace("v=1", "v=2"), uri.replace("27840", "80"), uri.replace("192.0.2.10", "example.com"), uri.replace(sid, "oops"), uri + "&secret=x"]:
		check(Code.decode(value).is_empty(), "invalid or ambiguous QR rejected")
	var texture := Code.texture(uri)
	check(texture != null, "native QR image generated")
	if texture != null:
		var bridge = ClassDB.instantiate("NovaBonjour")
		var bytes: PackedByteArray = texture.get_image().save_png_to_buffer()
		var events = JSON.parse_string(bridge.call("exchange", JSON.stringify({"op": "qr_decode_image", "data": Marshalls.raw_to_base64(bytes)})))
		check(events.size() == 1 and events[0].value == uri, "real QR pixels decode to exact invitation")
		texture.get_image().save_png("res://build/validation/join-qr.png")
		bridge.free()
	print("LAN_QR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
