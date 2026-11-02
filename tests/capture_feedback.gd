extends SceneTree
var app
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/validation/feedback-" + name + ".png")
func run() -> void:
	root.size = Vector2i(1920, 1080)
	app = load("res://app/main.tscn").instantiate()
	root.add_child(app)
	app.choices.clear()
	for path in app.roots: app._add_choice(path)
	app.set_language("zh_CN")
	app.home.start_button.grab_focus()
	await capture("home-tv")
	app._open_setup(true)
	app.library.cards[0].grab_focus()
	await capture("grid-tv")
	app.library.cards[0].pressed.emit()
	await capture("launch-tv")
	root.size = Vector2i(540, 960)
	app._show_home()
	app.home.start_button.grab_focus()
	await capture("home-phone")
	app._open_setup(true)
	app.library.cards[0].grab_focus()
	await capture("grid-phone")
	app._show_home()
	app._open_settings()
	await capture("settings-phone")
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	await create_timer(0.08).timeout
	quit()
