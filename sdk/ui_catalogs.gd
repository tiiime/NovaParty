extends RefCounted
# Stable registry: only replace global translations after validating both catalogs.
static var current_root := ""
static var installed: Array[Translation] = []

static func apply(root: String) -> bool:
	if current_root == root:
		return true
	var prepared: Array[Translation] = []
	for locale in ["zh_CN", "en"]:
		var path := root.path_join("i18n/" + locale + ".json")
		if not FileAccess.file_exists(path):
			return false
		var messages = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not messages is Dictionary or messages.is_empty():
			return false
		var catalog := Translation.new()
		catalog.locale = locale
		for key in messages:
			if not key is String or not messages[key] is String:
				return false
			catalog.add_message(key, messages[key])
		prepared.append(catalog)
	for catalog in installed:
		TranslationServer.remove_translation(catalog)
	installed = prepared
	for catalog in installed:
		TranslationServer.add_translation(catalog)
	current_root = root
	return true
