extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL FEEDBACK: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var app = load("res://app/main.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.3).timeout
	check(app.ui_feedback.streams.size() == 5, "all licensed OGG cues load from raw bytes")
	for stream in app.ui_feedback.streams.values():
		check(stream.get_length() > 0.02 and stream.get_length() < 3, "short nonempty cue")
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "FeedbackValidation")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus, capture)
	app.ui_feedback.navigation.bus = "FeedbackValidation"
	app.ui_feedback.action.bus = "FeedbackValidation"
	app.ui_feedback.play("launch")
	await create_timer(0.18).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in samples: peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	check(samples.size() > 0 and peak > 0.001, "OGG decodes and produces actual nonzero mixer output")
	app._open_setup(true)
	app.library.cards[0].grab_focus()
	await create_timer(0.3).timeout
	check(app.library.cards[0].scale.x > 1.02, "focused game card visibly enlarges")
	var effect = app.library.cards[0].get_node("FocusFeedback")
	check(effect.is_processing(), "focused effect breathes while motion enabled")
	app.motion_choice.button_pressed = true
	check(not effect.is_processing(), "reduce motion freezes halo")
	check(app.library.cards[0].scale.x > 1.02, "reduced motion preserves static focus enlargement")
	var counts: Dictionary = app.ui_feedback.played.duplicate()
	app.sound_choice.button_pressed = true
	app.sound_choice.button_pressed = false
	counts = app.ui_feedback.played.duplicate()
	app.ui_feedback.play("launch")
	app.ui_feedback.play("move")
	check(app.ui_feedback.played == counts and not app.ui_feedback.action.playing and not app.ui_feedback.navigation.playing, "muted cues do not play and current sounds stop")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.profile_path))
	check(saved.ui_sounds == false and saved.reduce_motion == true, "sound and motion preferences persist")
	app.sound_choice.button_pressed = true
	await create_timer(0.08).timeout
	check(app.ui_feedback.sound_enabled(), "sound can be enabled again")
	DirAccess.remove_absolute(app.profile_path)
	app.queue_free()
	await process_frame
	AudioServer.remove_bus(bus)
	print("UI_FEEDBACK_RESULT checks=%d failures=%d mixer_peak=%.4f frames=%d" % [checks, failures, peak, samples.size()])
	quit(1 if failures else 0)
