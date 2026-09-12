extends GutTest

var previous_values: Dictionary
var previous_path: String
var previous_audio_state: Dictionary[StringName, Dictionary] = {}
var previous_max_fps: int
var previous_msaa: Viewport.MSAA
var previous_render_scale: float
var previous_window_mode: DisplayServer.WindowMode
var previous_window_size: Vector2i

func before_each() -> void:
	previous_audio_state.clear()
	for bus_name: StringName in PlayerSettings.AUDIO_BUSES.values():
		var bus_index := AudioServer.get_bus_index(bus_name)
		previous_audio_state[bus_name] = {
			"mute": AudioServer.is_bus_mute(bus_index),
			"volume_db": AudioServer.get_bus_volume_db(bus_index),
		}
	previous_max_fps = Engine.max_fps
	previous_msaa = get_tree().root.msaa_3d
	previous_render_scale = get_tree().root.scaling_3d_scale
	previous_window_mode = DisplayServer.window_get_mode()
	previous_window_size = DisplayServer.window_get_size()
	previous_values = PlayerSettings.instance().values.duplicate()
	previous_path = PlayerSettings.instance().settings_path
	PlayerSettings.instance().settings_path = "user://test_settings_%d.cfg" % get_instance_id()
	_cleanup_settings_file()
	PlayerSettings.instance().values = PlayerSettings.DEFAULTS.duplicate()
	PlayerSettings.instance().apply_audio()

func after_each() -> void:
	_cleanup_settings_file()
	PlayerSettings.instance().settings_path = previous_path
	PlayerSettings.instance().values = previous_values
	for bus_name: StringName in previous_audio_state:
		var bus_index := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_mute(bus_index, bool(previous_audio_state[bus_name].mute))
		AudioServer.set_bus_volume_db(bus_index, float(previous_audio_state[bus_name].volume_db))
	Engine.max_fps = previous_max_fps
	get_tree().root.msaa_3d = previous_msaa
	get_tree().root.scaling_3d_scale = previous_render_scale
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(previous_window_mode)
		DisplayServer.window_set_size(previous_window_size)

func test_audio_categories_route_to_master() -> void:
	assert_eq(AudioServer.get_bus_index("Master"), 0)
	for key: String in PlayerSettings.AUDIO_BUSES:
		var name: String = PlayerSettings.AUDIO_BUSES[key]
		var index := AudioServer.get_bus_index(name)
		assert_gte(index, 0)
		if name != "Master":
			assert_eq(AudioServer.get_bus_send(index), &"Master")

func test_audio_volume_only_changes_the_selected_category() -> void:
	var settings := PlayerSettings.instance()
	var ui_index := AudioServer.get_bus_index("UI")
	var missile_index := AudioServer.get_bus_index("Missiles")
	settings.set_value("ui", 0.0)
	assert_true(AudioServer.is_bus_mute(ui_index))
	assert_false(AudioServer.is_bus_mute(0))
	settings.set_value("ui", 0.5)
	assert_false(AudioServer.is_bus_mute(ui_index))
	assert_almost_eq(AudioServer.get_bus_volume_db(ui_index), linear_to_db(0.5), 0.001)
	assert_almost_eq(AudioServer.get_bus_volume_db(missile_index), 0.0, 0.001)

func test_display_preferences_apply_to_runtime() -> void:
	var preferences := PlayerSettings.instance()
	preferences.set_value("antialiasing", 2)
	preferences.set_value("frame_limit", 2)
	assert_eq(get_tree().root.msaa_3d, Viewport.MSAA_4X)
	assert_eq(Engine.max_fps, 60)

func test_display_preferences_round_trip_and_clamp_option_indices() -> void:
	var preferences := PlayerSettings.instance()
	preferences.set_value("antialiasing", 2)
	preferences.set_value("frame_limit", 2)
	preferences.set_value("resolution", 2)
	assert_eq(preferences.save_preferences(), OK)
	preferences.load_preferences()
	assert_eq(preferences.values.antialiasing, 2)
	assert_eq(preferences.values.frame_limit, 2)
	assert_eq(preferences.values.resolution, 2)
	preferences.set_value("resolution", 99)
	assert_eq(preferences.values.resolution, 3)
	preferences.set_value("antialiasing", -1)
	assert_eq(preferences.values.antialiasing, 0)

func test_render_resolution_preserves_native_pixels_and_aspect_ratio() -> void:
	assert_eq(PlayerSettings.render_scale_for(Vector2i(2560, 1440), 0), 1.0)
	assert_eq(PlayerSettings.render_scale_for(Vector2i(2560, 1440), 4), 1.0)
	assert_eq(PlayerSettings.render_scale_for(Vector2i(2560, 1440), 2), 0.625)
	assert_eq(PlayerSettings.render_scale_for(Vector2i(3840, 2160), 4), 2.0 / 3.0)
	assert_eq(PlayerSettings.render_scale_for(Vector2i.ZERO, 2), 1.0)
	var preferences := PlayerSettings.instance()
	var output := get_tree().root.size
	preferences.set_value("render_resolution", 2)
	assert_almost_eq(get_tree().root.scaling_3d_scale, PlayerSettings.render_scale_for(output, 2), 0.0001)
	assert_eq(get_tree().root.size, output, "렌더링 해상도는 창 크기를 바꾸지 않습니다")
	assert_eq(preferences.save_preferences(), OK)
	preferences.load_preferences()
	assert_eq(preferences.values.render_resolution, 2)

func test_numeric_preferences_round_trip() -> void:
	PlayerSettings.instance().set_value("missile", 0.35)
	PlayerSettings.instance().set_value("pan", 1.5)
	assert_eq(PlayerSettings.instance().save_preferences(), OK)
	PlayerSettings.instance().values.clear()
	PlayerSettings.instance().load_preferences()
	assert_eq(PlayerSettings.instance().values.missile, 0.35)
	assert_eq(PlayerSettings.instance().values.pan, 1.5)

func test_invalid_control_and_audio_values_keep_safe_limits() -> void:
	PlayerSettings.instance().set_value("zoom", -100)
	PlayerSettings.instance().set_value("ui", NAN)
	assert_eq(PlayerSettings.instance().values.zoom, 0.25)
	assert_eq(PlayerSettings.instance().values.ui, 1.0)

func test_combat_events_route_to_the_matching_audio_category() -> void:
	var combat := add_child_autofree(CombatAudio.new()) as CombatAudio
	assert_true(combat.play_event(CombatAudio.CONTACT))
	assert_not_null(_player_with_stream_on_bus(combat, &"Alerts"))
	var missile := add_child_autofree(Node.new()) as Node
	assert_true(combat.play_missile_event(CombatAudio.MISSILE, missile))
	assert_not_null(_player_with_stream_on_bus(combat, &"Missiles"))
	assert_true(combat.play_event(CombatAudio.EXPLOSION))
	assert_not_null(_player_with_stream_on_bus(combat, &"Explosions"))
	assert_eq((combat.get_node("GunAirbursts") as AudioStreamPlayer).bus, &"Guns")

func test_ui_players_route_to_the_ui_category() -> void:
	var ui := add_child_autofree(UiAudio.new()) as UiAudio
	assert_true(ui.play_event(UiAudio.CLICK))
	assert_true(ui.play_event(UiAudio.ACTION_COMPLETE))
	assert_eq(_players_on_bus(ui, &"UI").size(), 2)

func test_gun_players_route_to_the_gun_category() -> void:
	var gun := add_child_autofree(GunAudio.new()) as GunAudio
	assert_eq(gun.bus, &"Guns")
	assert_eq(_players_on_bus(gun, &"Guns").size(), 1)

func test_settings_menu_slider_updates_value_and_readout() -> void:
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	menu.open()
	menu.sliders["ui"].value = 0
	assert_eq(PlayerSettings.instance().values.ui, 0.0)
	assert_eq(menu.readouts["ui"].text, "0%")

func test_settings_menu_reopens_on_first_tab() -> void:
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	menu.open()
	menu.tabs.current_tab = 1
	menu.close()
	menu.open()
	assert_eq(menu.tabs.current_tab, 0)

func test_settings_menu_close_saves_and_emits_closed() -> void:
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	watch_signals(menu)
	menu.open()
	menu.sliders["ui"].value = 0
	menu.close()
	assert_false(menu.visible)
	assert_signal_emitted(menu, "closed")
	PlayerSettings.instance().load_preferences()
	assert_eq(PlayerSettings.instance().values.ui, 0.0)

func test_invalid_config_values_keep_safe_defaults() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "master", "loud")
	config.set_value("settings", "rotation", 99)
	config.set_value("settings", "fullscreen", "yes")
	assert_eq(config.save(PlayerSettings.instance().settings_path), OK)
	PlayerSettings.instance().load_preferences()
	assert_eq(PlayerSettings.instance().values.master, 1.0)
	assert_eq(PlayerSettings.instance().values.rotation, 2.0)
	assert_false(PlayerSettings.instance().values.fullscreen)

func _player_with_stream_on_bus(root: Node, bus: StringName) -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players_on_bus(root, bus):
		if player.stream != null:
			return player
	return null

func _players_on_bus(root: Node, bus: StringName) -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var player := node as AudioStreamPlayer
		if player.bus == bus:
			result.append(player)
	return result

func _cleanup_settings_file() -> void:
	var path := PlayerSettings.instance().settings_path
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
