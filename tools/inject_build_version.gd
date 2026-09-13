extends SceneTree

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		push_error("Usage: inject_build_version.gd -- <build-date> <short-sha> [dirty]")
		quit(2)
		return
	var dirty := arguments.size() >= 3 and String(arguments[2]) == "dirty"
	var version := BuildVersion.from_build(String(arguments[0]), String(arguments[1]), dirty)
	if version == BuildVersion.DEVELOPMENT_LABEL:
		push_error("Build date and commit SHA must not be empty")
		quit(2)
		return
	var directory := ProjectSettings.globalize_path(BuildVersion.GENERATED_PATH.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		push_error("Could not create build version directory: %s" % error_string(directory_error))
		quit(directory_error)
		return
	var file := FileAccess.open(BuildVersion.GENERATED_PATH, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("Could not write build version: %s" % error_string(open_error))
		quit(open_error)
		return
	file.store_line(version)
	file.close()
	print("BUILD_VERSION=%s" % version)
	quit()
