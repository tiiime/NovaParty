extends SceneTree
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL UI STATE: " + message)

func _initialize() -> void:
	call_deferred("run")

func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-package="):
			path = argument.trim_prefix("--ui-package=")
	var zip := ZIPReader.new()
	check(zip.open(path) == OK, "open UI archive")
	var entry := ""
	for name in zip.get_files():
		if name.ends_with("/manifest.json"):
			var manifest: Dictionary = JSON.parse_string(zip.read_file(name).get_string_from_utf8())
			entry = "res://" + name.get_base_dir().path_join(manifest.entry)
	zip.close()
	check(ProjectSettings.load_resource_pack(path, false), "mount portable UI resources")
	root.size = Vector2i(540, 1170)
	var host = load("res://app/bootstrap.tscn").instantiate()
	root.add_child(host)
	await process_frame
	host.client.set_language("en")
	host.client._add_choice("res://mods/hidden_cards")
	host.client._add_choice("res://mods/jump_rope")
	host.client._open_setup(true)
	host.client.library.cards[1].pressed.emit()
	host.client.library.cards[1].grab_focus()
	host.client.address.text = "192.0.2.20"
	host.client.port.value = 29001
	check(not host.debug_replace_client_ui(entry, "state-1").has("error"), "swap from game selection")
	check(host.client.choices.selected == 1 and host.client.library.selection == 1, "selection retained")
	check(root.gui_get_focus_owner() == host.client.library.cards[1], "selected cover focus retained")
	check(host.client.address.text == "192.0.2.20" and host.client.port.value == 29001, "connection fields retained")
	check(host.client.create_button.visible and not host.client.home.visible, "launch page retained")
	check(TranslationServer.get_locale() == "en", "language retained")
	host.client._open_settings()
	host.client.motion_choice.button_pressed = true
	host.client.motion_choice.grab_focus()
	check(not host.debug_replace_client_ui("res://app/main.gd", "builtin:client").has("error"), "swap with settings open")
	check(host.client.settings_dialog.visible and host.client.motion_choice.button_pressed, "settings and preference retained")
	check(root.gui_get_focus_owner() == host.client.motion_choice, "settings toggle focus retained")
	host.client.settings_dialog.close()
	host.client._open_setup(false)
	host.client._show_manual_join()
	host.client.address.grab_focus()
	check(not host.debug_replace_client_ui(entry, "state-2").has("error"), "swap join page")
	check(host.client.network_row.visible and host.client.join_button.visible, "join mode retained")
	check(root.gui_get_focus_owner() == host.client.address, "address focus retained")
	check(host.client.home.reduced_motion, "motion preference retained")
	# Exercise actual directional input across the scroll/grid/footer boundary.
	for viewport_size in [Vector2i(1280, 720), Vector2i(540, 960)]:
		root.size = viewport_size
		host.client._open_setup(true)
		for frame in range(4): await process_frame
		check(not host.client.settings_action.visible, "selection page has no settings button")
		host.client.library.cards[1].grab_focus()
		await press(KEY_ENTER)
		check(root.gui_get_focus_owner() == host.client.create_button and host.client.choices.selected == 1, "confirm game selects it and focuses launch")
		await press(KEY_ESCAPE)
		check(not host.client.home.visible and root.gui_get_focus_owner() == host.client.library.cards[1], "back from launch returns to selected game")
		await press(KEY_ESCAPE)
		check(host.client.home.visible, "back from grid returns home")
		host.client._open_setup(true)
		for frame in range(3): await process_frame
		for card in host.client.library.cards:
			card.grab_focus()
			var previous: Control = card
			for step in range(host.client.library.cards.size() + 1):
				if root.gui_get_focus_owner() == host.client.create_button: break
				previous = root.gui_get_focus_owner()
				await press(KEY_DOWN)
			check(root.gui_get_focus_owner() == host.client.create_button, "every grid column reaches launch: " + str(viewport_size))
			await press(KEY_UP)
			check(root.gui_get_focus_owner() == previous, "launch returns to last focused card")
		host.client.create_button.grab_focus()
		if viewport_size.x > viewport_size.y:
			await press(KEY_LEFT)
			check(root.gui_get_focus_owner() == host.client.back_button, "TV launch to back without hidden settings")
			await press(KEY_RIGHT)
			check(root.gui_get_focus_owner() == host.client.create_button, "TV footer returns to launch")
		else:
			await press(KEY_DOWN)
			check(root.gui_get_focus_owner() == host.client.back_button, "phone launch to bottom navigation")
			await press(KEY_RIGHT)
			check(root.gui_get_focus_owner() == host.client.back_button, "phone skips hidden settings")
			await press(KEY_UP)
			check(root.gui_get_focus_owner() == host.client.create_button, "phone back navigation returns to launch")
	DirAccess.remove_absolute(host.client.profile_path)
	host.queue_free()
	await process_frame
	await create_timer(0.06).timeout # Let the audio mixer release stopped playbacks.
	print("UI_STATE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
