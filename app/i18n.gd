extends Node

const Catalogs = preload("res://sdk/ui_catalogs.gd")
const UI_ROOT := "res://"

func _enter_tree() -> void:
	install()
	select("system")

static func install() -> bool:
	return Catalogs.apply(UI_ROOT)

static func select(language: String) -> void:
	var locale := OS.get_locale() if language == "system" else language
	TranslationServer.set_locale("zh_CN" if locale.begins_with("zh") else "en")

static func game_name(info: Dictionary) -> String:
	var id: String = info.manifest.id
	if id == "gomoku":
		return TranslationServer.translate("GAME_GOMOKU")
	if id == "hidden_cards":
		return TranslationServer.translate("GAME_HIDDEN_CARDS")
	# External games may supply a locale-to-name map without changing IDs/fingerprints.
	var names = info.manifest.get("localized_names", {})
	var locale := TranslationServer.get_locale()
	return str(names.get(locale, names.get(locale.get_slice("_", 0), info.manifest.name))) if names is Dictionary else str(info.manifest.name)
