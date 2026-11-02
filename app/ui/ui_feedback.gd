extends Node
signal preferences_changed
const AUDIO_ROOT := "res://assets/audio/ui/"
var streams := {}
var navigation: AudioStreamPlayer
var action: AudioStreamPlayer
var played := {}
var last_event := ""
var last_move := -1000
var last_action := -1000
var started := 0
var welcomed := false

func _ready() -> void:
	started = Time.get_ticks_msec()
	for cue in ["move", "confirm", "launch", "back", "welcome"]:
		var path: String = AUDIO_ROOT + cue + ".ogg"
		# Hot UI packs contain raw OGG; APK exports contain Godot-imported remaps.
		var stream: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path)) if FileAccess.file_exists(path) else load(path)
		if stream != null:
			streams[cue] = stream
	navigation = AudioStreamPlayer.new()
	navigation.volume_db = -12
	add_child(navigation)
	action = AudioStreamPlayer.new()
	action.volume_db = -8
	action.max_polyphony = 2
	add_child(action)

func sound_enabled() -> bool:
	return bool(get_parent().profile.get("ui_sounds", true))

func reduced_motion() -> bool:
	return bool(get_parent().profile.get("reduce_motion", false))

func play(cue: String) -> void:
	if not sound_enabled() or not streams.has(cue) or get_parent().ui_preparing or not get_parent().is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	# Initial focus, hot swaps and fast held DPAD keys should not make a sound storm.
	if cue == "move":
		if now - started < 200 or now - last_move < 85 or now - last_action < 110:
			return
		last_move = now
		navigation.stream = streams[cue]
		navigation.play()
	else:
		if now - last_action < 65:
			return
		last_action = now
		navigation.stop()
		action.stream = streams[cue]
		action.play()
	last_event = cue
	played[cue] = int(played.get(cue, 0)) + 1

func refresh_preferences() -> void:
	if not sound_enabled():
		navigation.stop()
		action.stop()
	preferences_changed.emit()

func welcome() -> void:
	if welcomed:
		return
	welcomed = true
	play("welcome")

func diagnostic() -> Dictionary:
	return {"enabled": sound_enabled(), "reduced_motion": reduced_motion(), "loaded": streams.size(), "last_event": last_event, "played": played.duplicate(), "mix_rate": AudioServer.get_mix_rate()}

func _exit_tree() -> void:
	for player in [navigation, action]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	streams.clear()
