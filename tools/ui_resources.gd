extends SceneTree
var failed := false

func _initialize() -> void:
	var destination := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			destination = argument.trim_prefix("--output=")
	assert(not destination.is_empty())
	_convert("assets/ui", destination, false)
	_convert("assets/fonts", destination, true)
	if failed:
		quit(1)
		return
	print("UI_ENGINE=" + Engine.get_version_info().string)
	print("UI_RESOURCES_OK")
	quit()

func _convert(folder: String, destination: String, fonts: bool) -> void:
	DirAccess.make_dir_recursive_absolute(destination.path_join(folder))
	for child in DirAccess.get_directories_at("res://" + folder):
		_convert(folder.path_join(child), destination, fonts)
	for name in DirAccess.get_files_at("res://" + folder):
		var extension := name.get_extension().to_lower()
		if not extension in (["ttf", "otf"] if fonts else ["svg", "png", "jpg", "jpeg", "webp"]):
			continue
		var target := destination.path_join(folder.path_join(name.get_basename() + ".res"))
		# Do not silently collide foo.svg with foo.png in a portable package.
		if FileAccess.file_exists(target):
			failed = true
			return
		var source = load("res://" + folder.path_join(name))
		var resource: Resource = source if fonts else ImageTexture.create_from_image(source.get_image())
		if ResourceSaver.save(resource, target) != OK:
			failed = true
