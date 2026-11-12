extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Emulate a host with no platform catalog, as with an older SDK 1 client.
	TranslationServer.clear()
	for game in ["gomoku", "hidden_cards", "jump_rope"]:
		var rules = load("res://mods/" + game + "/rules.gd").new()
		var snapshot := {"seat": 0, "players": [{}, {}], "view": rules.view_for(rules.initial_state(42), 0)}
		var original: Dictionary = snapshot.duplicate(true)
		var view = load("res://mods/" + game + "/view.gd").new()
		root.add_child(view)
		for locale in ["en", "zh_CN", "fr"]:
			TranslationServer.set_locale(locale)
			view.render(snapshot)
			var text: String = view.title.text if game == "jump_rope" else view.label.text if game == "gomoku" else view.get_child(0).text
			var expected: String = {"gomoku": ["五子棋", "Gomoku"], "hidden_cards": ["暗牌", "Hidden Cards"], "jump_rope": ["跳绳", "Jump Rope"]}[game][0 if locale == "zh_CN" else 1]
			assert(text.contains(expected))
			assert(snapshot == original, "language rendering mutated player state")
		view.queue_free()
		await process_frame
	print("MOD_I18N_OK standalone catalogs, English fallback, unchanged player state")
	quit()
