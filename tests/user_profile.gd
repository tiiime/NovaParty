extends SceneTree
const Profile = preload("res://sdk/user_profile.gd")
const Loader = preload("res://sdk/mod_loader.gd")
const Room = preload("res://sdk/room.gd")
const Session = preload("res://sdk/session.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("PROFILE FAIL: " + message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var local := {"id":"stable-local","nickname":"","language":"en","last_address":"private-address","token":"private-token"}
	var public := Profile.local_public(local,"Living room TV")
	check(public.display_name == "Living room TV", "empty name defaults to device name")
	check(not public.has("id") and not public.has("token") and not public.has("last_address") and not public.has("language"), "public whitelist excludes local settings and credentials")
	var bad := Profile.normalize({"avatar":{"character":[],"palette":"bad"},"theme_color":{},"display_name":"\nA\tB\u202e"})
	check(bad.display_name == "AB" and bad.avatar.character == "bear" and bad.avatar.palette == "honey" and bad.theme_color == "sky", "malformed values and text controls normalize safely")
	check(Profile.normalize({"display_name":"x".repeat(80)}).display_name.length() == 32, "display name bounded")
	for role in Profile.CHARACTERS:
		for palette in Profile.PALETTES:
			check(Profile.texture({"avatar":{"character":role,"palette":palette}}) != null, "avatar decoded " + role + palette)
	var loader := Loader.new()
	var info := loader.inspect("res://mods/gomoku")
	var room = Room.new(info,loader.rules(info),"host","Host",12,public)
	var hello := {"protocol":2,"rules_fingerprint":info.rules_fingerprint,"player_id":"guest","nickname":"Guest","profile":{"display_name":"Fox","avatar":{"character":"fox","palette":"mint"},"theme_color":"rose","token":"forbidden"}}
	var welcome: Dictionary = room.hello(hello)
	check(welcome.type == "welcome" and room.snapshot(0).players[1].nickname == "Fox", "profile shared during hello with legacy nickname kept consistent")
	var before: Dictionary = room.snapshot(0)
	room._update_profile(1,{"display_name":"Bunny","avatar":{"character":"bunny","palette":"ocean"}})
	var after: Dictionary = room.snapshot(0)
	check(before.revision == after.revision and before.view == after.view, "appearance changes do not change game revision or rules state")
	after.players[1].profile.avatar.character = "dog"
	check(room.snapshot(0).players[1].profile.avatar.character == "bunny", "snapshots detach nested appearance")
	room.set_connected(1,false)
	var retry: Dictionary = hello.duplicate(true)
	retry.resume_token = "invalid"
	retry.profile = {"display_name":"Hijacked"}
	var denied: Dictionary = room.hello(retry)
	check(denied.code == "invalid_resume_token" and room.players[1].nickname == "Bunny", "failed resume cannot mutate profile")
	retry = hello.duplicate(true)
	retry.resume_token = welcome.resume_token
	var resumed: Dictionary = room.hello(retry)
	check(resumed.type == "welcome" and room.players[1].profile.avatar.character == "fox", "authenticated resume refreshes profile")
	# Exercise production app editor and its private persistence path.
	var app = load("res://app/main.gd").new()
	app.profile_path = "user://profile-test-" + str(OS.get_process_id()) + ".json"
	root.size = Vector2i(540,1100)
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	check(app.ui_ready and app.home.nickname_button.visible, "home profile entry is visible")
	app._open_user_profile()
	await process_frame
	check(app.user_panel.visible and app.user_panel.character_buttons.size() == 6 and app.user_panel.palette_buttons.size() == 4, "editor offers six animals and four palettes")
	app.user_panel.name_input.text = "Local Fox"
	app.user_panel.name_input.text_changed.emit("Local Fox")
	app.user_panel.character_buttons[1].pressed.emit()
	app.user_panel.palette_buttons[2].pressed.emit()
	app.user_panel.theme_buttons[2].pressed.emit()
	app.user_panel.save_button.pressed.emit()
	check(not app.user_panel.visible and app.profile.nickname == "Local Fox" and app.profile.avatar == {"character":"fox","palette":"mint"} and app.profile.theme_color == "rose", "save persists all edited fields")
	var persisted = JSON.parse_string(FileAccess.get_file_as_string(app.profile_path))
	check(persisted.id == app.profile.id and persisted.avatar == app.profile.avatar, "stable local ID survives saving appearance")
	app._open_user_profile()
	app.user_panel.palette_buttons[3].pressed.emit()
	app.user_panel.cancel_button.pressed.emit()
	check(app.profile.avatar.palette == "mint", "cancel discards draft")
	app._open_user_profile()
	app.user_panel.name_input.text = ""
	app.user_panel.name_input.text_changed.emit("")
	app.user_panel.save_button.pressed.emit()
	check(app.profile.nickname.is_empty() and app.nickname.text == Profile.device_name(), "clear custom name restores device fallback")
	app._open_user_profile()
	await process_frame
	check(app.user_panel.panel.position.x >= 0 and app.user_panel.panel.size.x <= root.size.x, "phone editor fits width")
	if OS.get_cmdline_user_args().has("--capture"):
		await create_timer(.3).timeout
		root.get_texture().get_image().save_png("res://build/validation/user-profile-phone.png")
	root.size = Vector2i(1920,1080)
	await process_frame
	await process_frame
	check(app.user_panel.panel.position.x >= 0 and app.user_panel.panel.position.x + app.user_panel.panel.size.x <= app.size.x and app.user_panel.panel.size.y <= app.size.y, "TV editor fits logical viewport including width")
	check(app.user_panel.character_grid.columns == 6, "TV uses six-column character selection")
	if OS.get_cmdline_user_args().has("--capture"):
		await create_timer(.3).timeout
		root.get_texture().get_image().save_png("res://build/validation/user-profile-tv.png")
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	await process_frame
	print("USER_PROFILE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
