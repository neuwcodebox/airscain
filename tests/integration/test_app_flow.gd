extends GutTest

const APP_SCENE := preload("res://main/app.tscn")

func test_settings_from_pause_keep_simulation_paused_and_block_camera() -> void:
	var preferences := PlayerSettings.instance()
	var original_path := preferences.settings_path
	preferences.settings_path = "user://test_app_settings.cfg"
	var app := add_child_autofree(APP_SCENE.instantiate()) as AirscainApp
	app.main_menu.get_node("Panel/VBox/SettingsButton").pressed.emit()
	assert_true(app.settings_menu.visible)
	app.settings_menu.visible = false
	app.start_game(AirscainMain.GameMode.SANDBOX)
	app.gameplay.session.set_simulation_speed(2.0)
	app.set_pause_menu(true)
	app.pause_menu.get_node("Panel/VBox/SettingsButton").pressed.emit()
	assert_true(app.settings_menu.visible)
	assert_true(app.gameplay.camera_rig.input_blocked)
	assert_eq(app.gameplay.session.simulation_speed, 0.0)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	app._input(escape)
	assert_false(app.settings_menu.visible)
	assert_true(app.pause_menu.visible)
	assert_eq(app.gameplay.session.simulation_speed, 0.0)
	app.set_pause_menu(false)
	assert_false(app.gameplay.camera_rig.input_blocked)
	assert_eq(app.gameplay.session.simulation_speed, 2.0)
	DirAccess.remove_absolute(preferences.settings_path)
	preferences.settings_path = original_path

func after_each() -> void:
	AirscainMain.requested_seed = -1
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED

func test_menu_demo_runs_bounded_live_defense_and_keeps_player_state_separate() -> void:
	var app := add_child_autofree(APP_SCENE.instantiate()) as AirscainApp
	await get_tree().process_frame
	var backdrop := app.main_menu.get_node("Background")
	var demo := backdrop.get("demo") as AirscainMain
	var controller := backdrop.get("controller") as MenuDefenseDemo
	controller.set_process(false)
	assert_null(app.main_menu.get_node_or_null("WorldCaption"))
	watch_signals(demo.objective)
	assert_eq(demo.defenses.size(), 6)
	assert_false(demo.director.enabled)
	assert_false(demo.combat_audio.enabled)
	assert_true(demo.session.unlimited_budget)
	var visible_seconds: Dictionary[int, float] = {}
	for index: int in 3000:
		controller.tick(0.1)
		for threat: ThreatUnit in demo.registry.get_active():
			if threat.definition.affiliation == ThreatDefinition.Affiliation.HOSTILE and demo.camera_rig.camera.is_position_in_frustum(threat.global_position):
				visible_seconds[threat.runtime_id] = visible_seconds.get(threat.runtime_id, 0.0) + 0.1
		assert_lte(controller.hostile_count(), MenuDefenseDemo.MAX_HOSTILES)
		if index % 20 == 0:
			await get_tree().process_frame
	assert_gt(demo.session.weapon_fire_count, 0, "실제 센서·C2·무장이 발사합니다")
	assert_gt(demo.session.neutralized_count, 0, "실제 요격체로 시연 위협을 격추합니다")
	assert_gte(controller.spawn_count, 15)
	var readable_approaches := 0
	for duration: float in visible_seconds.values():
		if duration >= 2.0:
			readable_approaches += 1
	assert_gte(readable_approaches, controller.spawn_count - MenuDefenseDemo.MAX_HOSTILES, "적기는 화면 안에서 접근을 볼 시간이 확보된 뒤 요격됩니다")
	assert_gte(demo.session.neutralized_count, controller.spawn_count - MenuDefenseDemo.MAX_HOSTILES)
	assert_signal_not_emitted(demo.objective, "damage_received", "모든 진입 방향을 실제 방공망으로 막습니다")
	assert_eq(demo.objective.current_integrity, demo.objective.definition.maximum_integrity)
	for unit: DefenseUnit in demo.defenses:
		assert_false(unit.combat_resource_depleted())
		if unit.uses_ammunition():
			assert_true(demo.support_manager.can_service(unit))
			for sensor: DefenseUnit in demo.defenses:
				if sensor.c2_roles() & DefenseUnit.C2Role.SENSOR:
					assert_true(demo.c2_network.has_command_path(unit, sensor.runtime_id))
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	assert_ne(demo.get_world_3d(), app.gameplay.get_world_3d())
	assert_eq(app.gameplay.session.weapon_fire_count, 0)
	assert_eq(app.gameplay.defenses.size(), 0)
	assert_false(backdrop.can_process())
	assert_false(controller.can_process())

func test_menu_city_impact_keeps_smoke_until_delayed_recovery() -> void:
	var app := add_child_autofree(APP_SCENE.instantiate()) as AirscainApp
	await get_tree().process_frame
	var backdrop := app.main_menu.get_node("Background")
	var demo := backdrop.get("demo") as AirscainMain
	var controller := backdrop.get("controller") as MenuDefenseDemo
	controller.set_process(false)
	controller.until_spawn = 1000
	var bounds := demo.battlefield.city_building_bounds(0)
	var roof := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	demo.objective.apply_building_impact(10, roof, bounds.size.y)
	assert_eq(demo.objective.current_integrity, 90)
	assert_eq(demo.objective.damage_smoke_effects.size(), 1)
	controller.tick(MenuDefenseDemo.CITY_RECOVERY_DELAY * 0.5)
	assert_eq(demo.objective.damage_smoke_effects.size(), 1)
	controller.tick(MenuDefenseDemo.CITY_RECOVERY_DELAY * 0.5 + 0.1)
	assert_eq(demo.objective.current_integrity, 100)
	assert_eq(demo.objective.damage_smoke_effects.size(), 0)

func test_main_menu_starts_modes_and_escape_menu_returns_home() -> void:
	var app: Node = add_child_autofree(APP_SCENE.instantiate())
	await get_tree().process_frame
	var main_menu := app.get("main_menu") as Control
	var pause_menu := app.get("pause_menu") as Control
	assert_true(main_menu.visible)
	assert_false(pause_menu.visible)
	assert_null(app.get("gameplay"))
	var backdrop := main_menu.get_node("Background") as SubViewportContainer
	var preview := backdrop.get_child(0) as SubViewport
	assert_true(preview.own_world_3d, "메뉴 배경의 월드는 실제 작전과 분리됩니다")
	assert_eq(preview.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	var expected_prepared_combat_streams := CombatAudio.all_streams().size() if OS.has_feature("web") else 0
	assert_eq(app.get("prepared_combat_stream_count"), expected_prepared_combat_streams)
	assert_true((app as AirscainApp).combat_vfx_warmup_started)
	for frame_index: int in 160:
		await get_tree().process_frame
		if (app as AirscainApp).combat_vfx_warmup_completed and app.get_node_or_null("CombatVfxWarmup") == null:
			break
	assert_true((app as AirscainApp).combat_vfx_warmup_completed)
	assert_null(app.get_node_or_null("CombatVfxWarmup"))
	app.call("start_game", AirscainMain.GameMode.TRAINING)
	await get_tree().process_frame
	var gameplay := app.get("gameplay") as AirscainMain
	assert_not_null(gameplay)
	var first_seed := gameplay.scenario.world_seed
	assert_eq(gameplay.game_mode, AirscainMain.GameMode.TRAINING)
	assert_false(main_menu.visible)
	assert_eq(preview.render_target_update_mode, SubViewport.UPDATE_DISABLED, "작전 중 메뉴 배경을 렌더하지 않습니다")
	assert_false(backdrop.can_process())
	assert_null(gameplay.hud.get_node_or_null("%ModeOption"))
	app.call("set_pause_menu", true)
	assert_true(pause_menu.visible)
	assert_eq(gameplay.session.simulation_speed, 0.0)
	assert_true((app.get("pause_save_button") as Button).disabled)
	app.call("set_pause_menu", false)
	assert_false(pause_menu.visible)
	assert_eq(gameplay.session.simulation_speed, 1.0)
	app.call("return_to_main_menu")
	assert_true(main_menu.visible)
	assert_eq(preview.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_null(app.get("gameplay"))
	await get_tree().process_frame
	app.call("start_game", AirscainMain.GameMode.SANDBOX)
	await get_tree().process_frame
	var next_gameplay := app.get("gameplay") as AirscainMain
	assert_not_null(next_gameplay)
	assert_ne(next_gameplay.scenario.world_seed, first_seed)

func test_game_over_restart_replaces_gameplay_without_showing_main_menu() -> void:
	var app: AirscainApp = add_child_autofree(APP_SCENE.instantiate()) as AirscainApp
	await get_tree().process_frame
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	await get_tree().process_frame
	var first_gameplay := app.gameplay
	var first_seed := first_gameplay.scenario.world_seed
	first_gameplay._on_restart_requested(true)
	await get_tree().process_frame
	assert_not_same(app.gameplay, first_gameplay)
	assert_eq(app.gameplay.scenario.world_seed, first_seed)
	assert_eq(app.gameplay.game_mode, AirscainMain.GameMode.SUSTAINED)
	assert_false(app.main_menu.visible)
	var same_seed_gameplay := app.gameplay
	same_seed_gameplay._on_restart_requested(false)
	await get_tree().process_frame
	assert_not_same(app.gameplay, same_seed_gameplay)
	assert_ne(app.gameplay.scenario.world_seed, first_seed)
	assert_false(app.main_menu.visible)

func test_game_over_blocks_escape_menu_and_returns_home_from_result_panel() -> void:
	var app: AirscainApp = add_child_autofree(APP_SCENE.instantiate()) as AirscainApp
	await get_tree().process_frame
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	await get_tree().process_frame
	var gameplay := app.gameplay
	gameplay.hud.set_catalog_expanded(true)
	gameplay.session.end_game()
	assert_false(gameplay.hud.catalog.visible)
	assert_true(gameplay.hud.game_over_blocker.visible)
	assert_true(gameplay.hud.game_over_panel.visible)
	assert_true(gameplay.hud.defense_menu_button.disabled)
	assert_true(gameplay.hud.pause_button.disabled)
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	app._unhandled_input(cancel_event)
	assert_false(app.pause_menu.visible)
	app.set_pause_menu(true)
	assert_false(app.pause_menu.visible)
	gameplay.hud.game_over_main_menu_button.pressed.emit()
	assert_null(app.gameplay)
	assert_true(app.main_menu.visible)
	assert_false(app.pause_menu.visible)

func test_save_and_load_controls_belong_to_main_and_pause_menus() -> void:
	var test_save_path := "user://app_menu_save_test_%d.json" % get_instance_id()
	_cleanup_save_path(test_save_path)
	var app := APP_SCENE.instantiate() as AirscainApp
	app.save_path = test_save_path
	add_child_autofree(app)
	await get_tree().process_frame
	assert_true(app.main_load_button.disabled)
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	await get_tree().process_frame
	assert_null(app.gameplay.hud.get_node_or_null("%SaveButton"))
	assert_null(app.gameplay.hud.get_node_or_null("%LoadButton"))
	app.gameplay.session.budget = 317
	app.set_pause_menu(true)
	assert_false(app.pause_save_button.disabled)
	assert_true(app.pause_load_button.disabled)
	var click_count := app.ui_audio.played_count(UiAudio.CLICK)
	var completion_count := app.ui_audio.played_count(UiAudio.ACTION_COMPLETE)
	app.pause_save_button.pressed.emit()
	assert_eq(app.pause_feedback_label.text, "저장 완료")
	assert_false(app.pause_load_button.disabled)
	assert_eq(app.ui_audio.played_count(UiAudio.CLICK), click_count + 1)
	assert_eq(app.ui_audio.played_count(UiAudio.ACTION_COMPLETE), completion_count + 1)
	app.gameplay.session.budget = 999
	app.pause_load_button.pressed.emit()
	assert_eq(app.pause_feedback_label.text, "불러오기 완료")
	assert_eq(app.gameplay.session.budget, 317)
	assert_eq(app.gameplay.session.simulation_speed, 0.0)
	app.return_to_main_menu()
	assert_false(app.main_load_button.disabled)
	app.main_load_button.pressed.emit()
	await get_tree().process_frame
	assert_not_null(app.gameplay)
	assert_eq(app.gameplay.session.budget, 317)
	assert_false(app.main_menu.visible)
	_cleanup_save_path(test_save_path)

func _cleanup_save_path(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
