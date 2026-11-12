extends SceneTree
var app

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.size = Vector2i(1920, 1080)
	app = load("res://app/main.tscn").instantiate()
	app.profile_path = "user://home-capture-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	app.set_language("zh_CN")
	await create_timer(0.6).timeout
	await capture("res://build/validation/home-tv-zh.png")
	await create_timer(1.3).timeout
	await capture("res://build/validation/home-tv-motion.png")
	app.set_language("en")
	await capture("res://build/validation/home-tv-en.png")
	root.size = Vector2i(540, 1170)
	await create_timer(0.3).timeout
	await capture("res://build/validation/home-phone-en.png")
	app.set_language("zh_CN")
	await capture("res://build/validation/home-phone-zh.png")
	app._open_settings()
	await capture("res://build/validation/home-settings.png")
	app.settings_dialog.hide()
	app._open_setup(true)
	await capture("res://build/validation/library-phone-zh.png")
	root.size = Vector2i(1920, 1080)
	await create_timer(0.3).timeout
	await capture("res://build/validation/library-tv-zh.png")
	app.set_language("en")
	await capture("res://build/validation/library-tv-en.png")
	root.size = Vector2i(540, 1170)
	await create_timer(0.3).timeout
	await capture("res://build/validation/library-phone-en.png")
	app._open_setup(false)
	await capture("res://build/validation/home-join-en.png")
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	print("HOME_CAPTURE_OK")
	quit()
