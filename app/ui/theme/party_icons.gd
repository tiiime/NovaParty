extends RefCounted
## Original 24-unit outline glyphs. Always pair action glyphs with visible text.
const PATHS := {
	"play": "M9 5l11 7-11 7z",
	"join": "M10 5H5v14h5M12 12h9m-4-4 4 4-4 4",
	"settings": "M4 7h16M4 17h16M8 4v6m8 4v6",
	"profile": "M5 20v-2a4 4 0 0 1 4-4h6a4 4 0 0 1 4 4v2M16 8a4 4 0 1 1-8 0 4 4 0 0 1 8 0z",
	"back": "M19 12H5m6-6-6 6 6 6",
	"scan": "M9 4H4v5m11-5h5v5M4 15v5h5m11-5v5h-5M8 12h8",
	"radio": "M3 8a15 15 0 0 1 18 0M6 12a10 10 0 0 1 12 0m-9 4a5 5 0 0 1 6 0m-3 4h.01",
	"link": "M10 13l4-4m-6 7-1 1a3 3 0 0 1-4-4l4-4a3 3 0 0 1 4 0m2 2a3 3 0 0 0 4 0l4-4a3 3 0 0 0-4-4l-1 1",
	"refresh": "M20 6v5h-5M20 11a8 8 0 1 0-1 6",
	"plus": "M12 5v14M5 12h14",
	"check": "M5 12l4 4L19 6",
	"bluetooth": "M12 3v18l5-5L6 7m0 10L17 8l-5-5"
}
static var _cache := {}

static func get_icon(key: String, color: Color, extent: int = 28) -> Texture2D:
	var cache_key := "%s-%s-%d" % [key, color.to_html(false), extent]
	if not _cache.has(cache_key):
		var image := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [extent, extent, PATHS[key], color.to_html(false)]
		if image.load_svg_from_string(svg) == OK:
			_cache[cache_key] = ImageTexture.create_from_image(image)
	return _cache.get(cache_key)
