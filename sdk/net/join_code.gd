extends RefCounted
# Connection invitations contain no player ID, resume token, or Debug credentials.
const PREFIX = "novaparty://join?"
static func encode(address: String, port: int, session_id: String) -> String:
	if not address.is_valid_ip_address() or port < 1024 or port > 65535 or session_id.length() != 32 or not session_id.is_valid_hex_number(false):
		return ""
	return PREFIX + "v=1&address=" + address.uri_encode() + "&port=" + str(port) + "&session=" + session_id
static func decode(value: String) -> Dictionary:
	if value.length() > 1024 or not value.begins_with(PREFIX):
		return {}
	var fields := {}
	for entry in value.trim_prefix(PREFIX).split("&"):
		var pair := entry.split("=", true, 1)
		if pair.size() != 2 or fields.has(pair[0]):
			return {}
		fields[pair[0]] = pair[1].uri_decode()
	if fields.size() != 4 or fields.get("v") != "1" or not fields.get("address", "").is_valid_ip_address() or not str(fields.get("port", "")).is_valid_int():
		return {}
	var address: String = fields.address
	var port := int(fields.port)
	var session_id: String = str(fields.get("session", ""))
	if encode(address, port, session_id).is_empty():
		return {}
	return {"address": address, "port": port, "session_id": session_id}

static func texture(value: String) -> Texture2D:
	if decode(value).is_empty():
		return null
	var encoded := ""
	if OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper"):
		var klass = Engine.get_singleton("JavaClassWrapper").wrap("org.novaparty.sdk.JoinQRCode")
		if klass != null:
			encoded = str(klass.encode(value))
	elif ClassDB.class_exists("NovaBonjour"):
		var bridge = ClassDB.instantiate("NovaBonjour")
		var events = JSON.parse_string(bridge.call("exchange", JSON.stringify({"op": "qr_encode", "value": value})))
		bridge.free()
		if events is Array:
			for event in events:
				if event.get("type") == "qr_image":
					encoded = str(event.get("data", ""))
	var image := Image.new()
	if encoded.is_empty() or image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
		return null
	return ImageTexture.create_from_image(image)

static func decode_png(bytes: PackedByteArray) -> String:
	if bytes.is_empty() or bytes.size() > 3 * 1024 * 1024:
		return ""
	var data := Marshalls.raw_to_base64(bytes)
	if OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper"):
		var klass = Engine.get_singleton("JavaClassWrapper").wrap("org.novaparty.sdk.JoinQRCode")
		return str(klass.decodeImage(data)) if klass != null else ""
	if ClassDB.class_exists("NovaBonjour"):
		var bridge = ClassDB.instantiate("NovaBonjour")
		var events = JSON.parse_string(bridge.call("exchange", JSON.stringify({"op": "qr_decode_image", "data": data})))
		bridge.free()
		if events is Array:
			for event in events:
				if event.get("type") == "qr_decoded":
					return str(event.get("value", ""))
	return ""
