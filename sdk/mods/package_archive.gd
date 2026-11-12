extends RefCounted
# Validate central directory sizes before ZIPReader allocates/decompresses files.
const MAX_EXPANDED = 32 * 1024 * 1024

static func inspect(path: String, package_limit: int = 16 * 1024 * 1024, expanded_limit: int = MAX_EXPANDED, file_limit: int = 16 * 1024 * 1024) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 22 or bytes.size() > package_limit:
		return {"error": "invalid_zip_size"}
	var end := -1
	for i in range(bytes.size() - 22, maxi(-1, bytes.size() - 65558), -1):
		if bytes.decode_u32(i) == 0x06054b50 and i + 22 + bytes.decode_u16(i + 20) == bytes.size():
			end = i
			break
	if end < 0 or bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0:
		return {"error": "invalid_zip_directory"}
	var count := bytes.decode_u16(end + 10)
	var cursor := bytes.decode_u32(end + 16)
	var directory_end := cursor + bytes.decode_u32(end + 12)
	if count < 1 or count > 129 or count != bytes.decode_u16(end + 8) or directory_end != end:
		return {"error": "invalid_zip_directory"}
	var files := {}
	var total := 0
	for _index in range(count):
		if cursor + 46 > directory_end or bytes.decode_u32(cursor) != 0x02014b50:
			return {"error": "invalid_zip_entry"}
		var length := bytes.decode_u16(cursor + 28)
		var next := cursor + 46 + length + bytes.decode_u16(cursor + 30) + bytes.decode_u16(cursor + 32)
		if next > directory_end or bytes.decode_u16(cursor + 8) & 1 or not bytes.decode_u16(cursor + 10) in [0, 8] or bytes.decode_u16(cursor + 34) != 0:
			return {"error": "unsupported_zip_entry"}
		var raw := bytes.slice(cursor + 46, cursor + 46 + length)
		var name := raw.get_string_from_utf8()
		if name.to_utf8_buffer() != raw or files.has(name) or not safe_path(name):
			return {"error": "unsafe_zip_path"}
		var size := bytes.decode_u32(cursor + 24)
		total += size
		if size > file_limit or total > expanded_limit or (name.ends_with("/manifest.json") and size > 65536):
			return {"error": "expanded_size_limit"}
		files[name] = size
		cursor = next
	if cursor != directory_end:
		return {"error": "invalid_zip_directory"}
	return {"files": files}

static func safe_path(name: String) -> bool:
	if name.is_empty() or name.contains(":") or name.contains("\\"):
		return false
	for part in name.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true
