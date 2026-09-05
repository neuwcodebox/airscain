extends GutTest

var previous_values: Dictionary
var previous_path: String

func before_each() -> void:
	previous_values = PlayerSettings.instance().values.duplicate()
	previous_path = PlayerSettings.instance().settings_path
	PlayerSettings.instance().settings_path = "user://test_settings_%d.cfg" % get_instance_id()
	PlayerSettings.instance().values = PlayerSettings.DEFAULTS.duplicate()
	PlayerSettings.instance().apply_audio()

func after_each() -> void:
	if FileAccess.file_exists(PlayerSettings.instance().settings_path):
		DirAccess.remove_absolute(PlayerSettings.instance().settings_path)
	PlayerSettings.instance().settings_path = previous_path
	PlayerSettings.instance().values = previous_values
	PlayerSettings.instance().apply_audio()
	PlayerSettings.instance().apply_rendering()

func test_audio_categories_route_to_master_and_preserve_independent_levels() -> void:
	var settings := PlayerSettings.instance()
	assert_eq(AudioServer.get_bus_index("Master"), 0)
	for key: String in PlayerSettings.AUDIO_BUSES:
		var name: String = PlayerSettings.AUDIO_BUSES[key]
		var index := AudioServer.get_bus_index(name)
		assert_gte(index, 0)
		if name != "Master":
			assert_eq(AudioServer.get_bus_send(index), &"Master")
	settings.set_value("ui", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")))
	assert_false(AudioServer.is_bus_mute(0))
	settings.set_value("ui", 0.5)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI")), linear_to_db(0.5), 0.001)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Missiles")), 0.0, 0.001)

func test_display_preferences_apply_and_round_trip() -> void:
	var preferences := PlayerSettings.instance()
	preferences.set_value("antialiasing", 2)
	preferences.set_value("frame_limit", 2)
	preferences.set_value("resolution", 2)
	assert_eq(get_tree().root.msaa_3d, Viewport.MSAA_4X)
	assert_eq(Engine.max_fps, 60)
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

func test_preferences_round_trip_and_clamp_invalid_input() -> void:
	PlayerSettings.instance().set_value("missile", 0.35)
	PlayerSettings.instance().set_value("pan", 1.5)
	PlayerSettings.instance().set_value("zoom", -100)
	PlayerSettings.instance().set_value("ui", NAN)
	assert_eq(PlayerSettings.instance().values.zoom, 0.25)
	assert_eq(PlayerSettings.instance().values.ui, 1.0)
	assert_eq(PlayerSettings.instance().save_preferences(), OK)
	PlayerSettings.instance().values.clear()
	PlayerSettings.instance().load_preferences()
	assert_eq(PlayerSettings.instance().values.missile, 0.35)
	assert_eq(PlayerSettings.instance().values.pan, 1.5)
	assert_eq(PlayerSettings.instance().values.zoom, 0.25)

func test_audio_categories_are_independent_and_zero_mutes() -> void:
	PlayerSettings.instance().set_value("gun", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Guns")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Missiles")))
	PlayerSettings.instance().set_value("gun", 0.5)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Guns")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Guns")), linear_to_db(0.5), 0.001)

func test_players_route_to_the_matching_category() -> void:
	var combat := add_child_autofree(CombatAudio.new()) as CombatAudio
	assert_eq(combat._play_stream(CombatAudio.CONTACT, 1.0).bus, &"Alerts")
	assert_eq(combat._play_stream(CombatAudio.MISSILE, 1.0).bus, &"Missiles")
	assert_eq(combat._play_stream(CombatAudio.EXPLOSION, 1.0).bus, &"Explosions")
	assert_eq(combat.gun_airbursts.bus, &"Guns")
	var ui := add_child_autofree(UiAudio.new()) as UiAudio
	assert_eq(ui.click_player.bus, &"UI")
	assert_eq(ui.feedback_player.bus, &"UI")
	var gun := add_child_autofree(GunAudio.new()) as GunAudio
	assert_eq(gun.bus, &"Guns")
	assert_eq(gun.ending_player.bus, &"Guns")

func test_settings_menu_updates_silently_and_saves_on_close() -> void:
	var menu := add_child_autofree(SettingsMenu.new()) as SettingsMenu
	menu.open()
	menu.sliders["ui"].value = 0
	assert_eq(PlayerSettings.instance().values.ui, 0.0)
	assert_eq(menu.readouts["ui"].text, "0%")
	menu.tabs.current_tab = 1
	menu.close()
	assert_false(menu.visible)
	menu.open()
	assert_eq(menu.tabs.current_tab, 0)
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
