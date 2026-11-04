extends RefCounted
# Public, versioned appearance. Never serialize the local identity/settings wholesale.
const CHARACTERS = ["bear", "fox", "bunny", "cat", "dog", "panda"]
const PALETTES = ["honey", "berry", "mint", "ocean"]
const THEMES = {"sky": "2058e0", "violet": "ab6de0", "rose": "e56a9d", "mint": "258c78", "orange": "dc7840", "gold": "a87d12"}
static var _textures := {}
static var _catalog := {}

static func clean_name(value, fallback: String = "Player") -> String:
	if not value is String: return fallback
	var result := ""
	for letter in value:
		var point: int = letter.unicode_at(0)
		if point >= 32 and point != 127 and point not in [0x202a,0x202b,0x202c,0x202d,0x202e,0x2066,0x2067,0x2068,0x2069]: result += letter
	return result.strip_edges().left(32) if not result.strip_edges().is_empty() else fallback

static func device_name() -> String:
	var result := ""
	if OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper") and Engine.has_singleton("AndroidRuntime"):
		var klass = Engine.get_singleton("JavaClassWrapper").wrap("org.novaparty.sdk.LanDiscovery")
		if klass != null: result = str(klass.deviceName(Engine.get_singleton("AndroidRuntime").get_activity()))
	elif ClassDB.class_exists("NovaBonjour"):
		var bridge = ClassDB.instantiate("NovaBonjour")
		var events = JSON.parse_string(bridge.call("exchange", '{"op":"device_name"}'))
		bridge.free()
		if events is Array:
			for event in events:
				if event.get("type") == "device_name": result = str(event.get("name", ""))
	if result.is_empty(): result = OS.get_environment("COMPUTERNAME") if OS.get_name() == "Windows" else OS.get_environment("HOSTNAME")
	if result.is_empty(): result = OS.get_model_name()
	if result in ["", "Generic", "Unknown"]: result = OS.get_name()
	return clean_name(result)

static func normalize(value, seed: String = "", fallback_name: String = "Player") -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var index := posmod(seed.hash(),24) if not seed.is_empty() else 0
	var avatar_value = source.get("avatar", {})
	var avatar: Dictionary = avatar_value if avatar_value is Dictionary else {}
	var character = avatar.get("character", CHARACTERS[index / 4])
	var palette = avatar.get("palette", PALETTES[index % 4])
	var color = source.get("theme_color", "sky")
	return {"schema": 1, "display_name": clean_name(source.get("display_name", fallback_name), clean_name(fallback_name)), "avatar": {"character": character if character in CHARACTERS else CHARACTERS[index / 4], "palette": palette if palette in PALETTES else PALETTES[index % 4]}, "theme_color": color if color is String and THEMES.has(color) else "sky"}

static func local_public(local: Dictionary, fallback_name: String = "") -> Dictionary:
	var display := clean_name(local.get("nickname", ""), fallback_name if not fallback_name.is_empty() else device_name())
	return normalize({"display_name":display,"avatar":local.get("avatar",{}),"theme_color":local.get("theme_color","sky")},str(local.get("id","")),display)

static func color(value) -> Color:
	return Color(THEMES[normalize(value).theme_color])

static func texture(value) -> Texture2D:
	var profile := normalize(value)
	var key: String = profile.avatar.character + "/" + profile.avatar.palette
	if not _textures.has(key):
		if _catalog.is_empty(): _catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/characters.json"))
		var image := Image.new()
		if image.load_svg_from_string(_catalog[key]) != OK: return null
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]
