class_name PlayerSettings
extends Node
## App preferences are independent of operation snapshots.

signal changed
const AUDIO_BUSES := {"master": "Master", "missile": "Missiles", "gun": "Guns", "explosion": "Explosions", "alert": "Alerts", "ui": "UI"}
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const FRAME_LIMITS: Array[int] = [0, 30, 60, 120, 144]
const OPTION_LIMITS := {"resolution": 3, "antialiasing": 3, "frame_limit": 4}
const DEFAULTS := {"master": 1.0, "missile": 1.0, "gun": 1.0, "explosion": 1.0, "alert": 1.0, "ui": 1.0, "pan": 1.0, "rotation": 1.0, "zoom": 1.0, "fullscreen": false, "resolution": 1, "antialiasing": 1, "frame_limit": 0}
var values: Dictionary = DEFAULTS.duplicate()
var settings_path: String = "user://settings.cfg"

static func instance() -> PlayerSettings:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameSettings") as PlayerSettings

func _ready() -> void:
	for bus_name: String in AUDIO_BUSES.values():
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_preferences()
	apply_audio()
	apply_rendering()
	if not OS.has_feature("web"):
		apply_display()

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	if key == "fullscreen":
		if not value is bool:
			return
	else:
		if not (value is float or value is int) or not is_finite(float(value)):
			return
		value = clampi(int(value), 0, OPTION_LIMITS[key]) if OPTION_LIMITS.has(key) else clampf(float(value), 0.0 if AUDIO_BUSES.has(key) else 0.25, 1.0 if AUDIO_BUSES.has(key) else 2.0)
	values[key] = value
	if AUDIO_BUSES.has(key):
		apply_audio()
	elif key in ["fullscreen", "resolution"]:
		apply_display()
	elif key in ["antialiasing", "frame_limit"]:
		apply_rendering()
	changed.emit()

func apply_audio() -> void:
	for key: String in AUDIO_BUSES:
		var index := AudioServer.get_bus_index(AUDIO_BUSES[key])
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(values[key]), 0.0001)))
			AudioServer.set_bus_mute(index, float(values[key]) <= 0.0)

func apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		if not OS.has_feature("web") and not values.fullscreen:
			var usable := DisplayServer.screen_get_usable_rect()
			var requested := RESOLUTIONS[int(values.resolution)]
			var size := requested.min((usable.size - Vector2i(32, 64)).max(Vector2i(640, 360)))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)

func apply_rendering() -> void:
	get_tree().root.msaa_3d = int(values.antialiasing) as Viewport.MSAA
	Engine.max_fps = FRAME_LIMITS[int(values.frame_limit)]

func reset_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply_audio()
	apply_display()
	apply_rendering()
	changed.emit()

func load_preferences() -> void:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	for key: String in DEFAULTS:
		var value: Variant = config.get_value("settings", key, DEFAULTS[key])
		if key == "fullscreen":
			if value is bool:
				values[key] = value
		elif (value is int or value is float) and is_finite(float(value)):
			values[key] = clampi(int(value), 0, OPTION_LIMITS[key]) if OPTION_LIMITS.has(key) else clampf(float(value), 0.0 if AUDIO_BUSES.has(key) else 0.25, 1.0 if AUDIO_BUSES.has(key) else 2.0)

func save_preferences() -> Error:
	var config := ConfigFile.new()
	for key: String in DEFAULTS:
		config.set_value("settings", key, values[key])
	return config.save(settings_path)
