extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")
const APP_SCENE := preload("res://main/app.tscn")

var main: AirscainMain

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	if OS.get_cmdline_user_args().has("--capture-operation-menus-only"):
		await _capture_operation_menus()
		quit(0)
		return
	_apply_requested_seed()
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	for index: int in 20:
		await process_frame
	_save_capture("/tmp/airscain_initial.png")
	if OS.get_cmdline_user_args().has("--capture-selection-panel-only"):
		var selection_ok := await _capture_selection_panel()
		if not selection_ok:
			quit(1)
			return
		print("VISUAL_CAPTURE_OK power_asset_selection asset_selection track_selection engagement_review")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-topbar-menus-only"):
		await _capture_topbar_menus()
		print("VISUAL_CAPTURE_OK defense_assets_menu city_status_menu")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-game-over-only"):
		main.hud.set_catalog_expanded(true)
		main.objective.apply_mission_damage(main.objective.current_integrity)
		for index: int in 5:
			await process_frame
		if not main.hud.game_over_blocker.visible or not main.hud.game_over_panel.visible:
			push_error("Game-over modal did not cover the gameplay HUD")
			quit(1)
			return
		if main.hud.catalog.visible or not main.hud.defense_menu_button.disabled or not main.hud.pause_button.disabled:
			push_error("Game-over modal left tactical controls active")
			quit(1)
			return
		if not main.hud.game_over_main_menu_button.visible:
			push_error("Game-over modal did not expose the main-menu action")
			quit(1)
			return
		_save_capture("/tmp/airscain_game_over_modal.png")
		print("VISUAL_CAPTURE_OK modal_input_block restart_and_main_menu_actions")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-popup-input-priority-only"):
		var popup_input_ok := await _capture_popup_input_priority()
		if not popup_input_ok:
			quit(1)
			return
		print("VISUAL_CAPTURE_OK popup_visual_and_pointer_order")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-asset-catalog-only"):
		await _capture_asset_catalog_and_support_base()
		print("VISUAL_CAPTURE_OK multiline_purchase_tooltip integrated_support_base")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-placement-dependencies-only"):
		await _capture_placement_dependencies()
		print("VISUAL_CAPTURE_OK consistent_c2_links support_service_relations global_power_status")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-city-restoration-only"):
		main.objective.apply_mission_damage(20)
		await process_frame
		var restoration_button := main.hud.city_restoration_button
		main.hud.set_city_menu_expanded(true)
		if restoration_button.disabled or main.hud.city_action_label.text != "피해 복구" or main.hud.city_action_meta_label.text != "+10    $200":
			push_error("City restoration control is unavailable while the city is damaged")
			quit(1)
			return
		var budget_before := main.session.budget
		restoration_button.pressed.emit()
		await process_frame
		if main.objective.current_integrity != 90 or main.session.budget != budget_before - 200:
			push_error("City restoration did not exchange budget for integrity")
			quit(1)
			return
		main.hud.set_city_menu_expanded(true)
		_save_capture("/tmp/airscain_city_restoration.png")
		print("VISUAL_CAPTURE_OK city_restoration immediate_budget_exchange")
		quit(0)
		return

	if OS.get_cmdline_user_args().has("--capture-training-guidance-only"):
		var training_guidance_ok := await _capture_training_guidance()
		if not training_guidance_ok:
			quit(1)
			return
		print("VISUAL_CAPTURE_OK training_entry_stable confirmed_distant_track_actual_click")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-city-only"):
		await _capture_city_detail()
		print("VISUAL_CAPTURE_OK western_city_detail contextual_rooftop_pads")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-marker-only"):
		await _capture_offscreen_marker_full_edge()
		print("VISUAL_CAPTURE_OK collapsible_catalog offscreen_marker_full_edge")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-ground-placement-only"):
		await _capture_open_city_ground_placement()
		print("VISUAL_CAPTURE_OK actual_building_footprints open_city_ground")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-reacquisition-only"):
		await _capture_retarget_and_cruise_terminal_guidance()
		print("VISUAL_CAPTURE_OK interceptor_reacquisition_grace interceptor_retarget")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-terminal-guidance-only"):
		await _capture_retarget_and_cruise_terminal_guidance()
		print("VISUAL_CAPTURE_OK interceptor_reacquisition_grace interceptor_retarget cruise_terminal_impact")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-curved-launch-only"):
		await _capture_curved_missile_launch()
		print("VISUAL_CAPTURE_OK broad_launch_sector curved_missile_departure")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-smoke-only"):
		await _capture_missile_smoke_trail()
		print("VISUAL_CAPTURE_OK missile_smoke_timed_fade")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-building-impact-only"):
		await _capture_building_impact_smoke()
		print("VISUAL_CAPTURE_OK building_swept_impact exact_impact_smoke")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-smoke-shadow-only"):
		await _capture_smoke_ground_shadow()
		print("VISUAL_CAPTURE_OK smoke_ground_shadow gradual_shadow_fade")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-explosion-isolation-only"):
		await _capture_explosion_instance_isolation()
		print("VISUAL_CAPTURE_OK explosion isolated_shockwave_material")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-terrain-impact-only"):
		await _capture_friendly_missile_terrain_impact()
		print("VISUAL_CAPTURE_OK friendly_missile first_terrain_impact")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-hpm-bird-only"):
		await _capture_hpm_bird_fall()
		print("VISUAL_CAPTURE_OK hpm weak_biological_coupling bird_fall_without_explosion")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-missile-rack-only"):
		await _capture_missile_rack_rapid_fire()
		print("VISUAL_CAPTURE_OK six_cell_rack rapid_launch uncluttered_world_marker")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-time-controls-only"):
		await _capture_time_control_buttons()
		print("VISUAL_CAPTURE_OK speed_state_on_buttons no_duplicate_label")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-sandbox-input-only"):
		var sandbox_input_ok := await _capture_sandbox_continuous_input()
		if not sandbox_input_ok:
			quit(1)
			return
		print("VISUAL_CAPTURE_OK sandbox_actual_clicks continuous_defense continuous_threat switched_threat")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-resolved-target-only"):
		main.hud.visible = false
		main.altitude_profile.visible = false
		var resolved_target_center := main.objective.global_position + Vector3(0.0, 100.0, 80.0)
		main.camera_rig.camera.global_position = resolved_target_center + Vector3(60.0, 50.0, 190.0)
		main.camera_rig.camera.look_at(resolved_target_center, Vector3.UP)
		await _capture_resolved_target_interceptor(resolved_target_center)
		print("VISUAL_CAPTURE_OK destroyed_target climb_and_self_destruct")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-surface-strike-only"):
		await _capture_surface_strike_smoke()
		print("VISUAL_CAPTURE_OK surface_strike delayed_damage exact_impact_smoke")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-light-only"):
		await _capture_hdr_light_vfx()
		print("VISUAL_CAPTURE_OK hdr_explosion laser_glow")
		quit(0)
		return
	await _verify_catalog_wheel_input()
	await _capture_camera_rotation()
	if OS.get_cmdline_user_args().has("--capture-camera-only"):
		print("VISUAL_CAPTURE_OK camera_rotation")
		quit(0)
		return
	main.placement.select(main.scenario.available_defenses[1])
	var rooftop_position: Vector3 = main.battlefield.rooftop_pads[0].position
	Input.warp_mouse(main.camera_rig.camera.unproject_position(rooftop_position))
	for index: int in 20:
		await process_frame
	if not main.placement.candidate_valid or not main.placement.preview.visible or main.placement.candidate_position.y < rooftop_position.y - 1.0:
		push_error("Placement preview did not acquire the designated rooftop")
		quit(1)
		return
	_save_capture("/tmp/airscain_placement.png")
	main.placement.cancel()
	_place_initial_assets()
	if OS.get_cmdline_user_args().has("--capture-cram-only"):
		await _capture_close_in_gun_barrage()
		print("VISUAL_CAPTURE_OK close_in_gun dense_tracer_barrage muzzle_flash")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-friendly-icons-only"):
		await _capture_friendly_identity_icons()
		print("VISUAL_CAPTURE_OK friendly_role_icons persistent_status_markers")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-countermeasure-only"):
		var countermeasure_center := main.objective.global_position + Vector3(0.0, 90.0, 80.0)
		main.camera_rig.camera.global_position = countermeasure_center + Vector3(0.0, 36.0, 105.0)
		main.camera_rig.camera.look_at(countermeasure_center, Vector3.UP)
		main.hud.visible = false
		main.altitude_profile.visible = false
		await _capture_countermeasure_defeat(countermeasure_center, false)
		print("VISUAL_CAPTURE_OK chaff_initial_volume noise_shimmer delayed_diversion")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-city-status-only"):
		await _capture_city_smoke_and_ammo_status()
		print("VISUAL_CAPTURE_OK city_damage_smoke ammo_depleted_status")
		quit(0)
		return
	await _capture_missile_battery_variants()
	if OS.get_cmdline_user_args().has("--capture-batteries-only"):
		print("VISUAL_CAPTURE_OK missile_battery_variants")
		quit(0)
		return
	await _capture_missile_smoke_trail()
	var city_camera_position := main.camera_rig.global_position
	var city_camera_zoom := main.camera_rig.zoom_distance
	_apply_city_building_impacts(35, 2)
	main.camera_rig.focus_on(main.objective.global_position)
	main.camera_rig.zoom_distance = 360.0
	main.camera_rig._update_camera()
	for index: int in 15:
		await process_frame
	if main.objective.damage_smoke_effects.size() < 2:
		push_error("City damage did not create persistent smoke sites")
		quit(1)
		return
	_save_capture("/tmp/airscain_city_damage.png")
	main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	main.camera_rig.global_position = city_camera_position
	main.camera_rig.zoom_distance = city_camera_zoom
	main.camera_rig._update_camera()
	for defense: DefenseUnit in main.defenses:
		if defense.definition.id == &"long_range_missile":
			defense.receive_damage(50.0)
			main.placement.pick_asset_at(defense.global_position)
			break
	main.session.start_defense()
	main.director.enabled = false
	for index: int in 8:
		var threat := main.director.spawn_one()
		var angle := TAU * float(index) / 8.0
		var target_position := Vector3(cos(angle) * 230.0, 72.0, sin(angle) * 230.0)
		threat.global_position = target_position
	for entry_index: int in range(2, 6):
		var mission_threat := main.director._spawn_entry(main.scenario.threat_entries[entry_index], TAU * float(entry_index) / 5.0, 0.0)
		mission_threat.global_position = Vector3(-320.0 + float(entry_index) * 110.0, 90.0 if entry_index < 5 else 28.0, 260.0)
	var jammer := main.director._spawn_entry(main.scenario.threat_entries[7], 0.4, 0.0)
	jammer.global_position = Vector3(60.0, 90.0, 120.0)
	for entry_index: int in range(9, 12):
		var advanced_threat := main.director._spawn_entry(main.scenario.threat_entries[entry_index], PI + float(entry_index - 9) * 0.16, 0.0)
		advanced_threat.global_position = Vector3(-520.0, 35.0 + float(entry_index - 9) * 55.0, -150.0 + float(entry_index - 9) * 150.0)
	await _capture_strike_vfx()
	_spawn_swarm_near_close_in_gun()
	var visual_target := main.director._spawn_entry(main.scenario.threat_entries[0], 0.0, 0.0)
	var visual_target_position := Vector3(-70.0, 105.0, 40.0)
	visual_target.global_position = visual_target_position
	visual_target.receive_damage(10000.0)
	for index: int in 6:
		await process_frame
	if main.effects_parent.get_node_or_null("FallingWreck") == null:
		push_error("Neutralized aircraft did not leave a falling wreck")
		quit(1)
		return
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	main.camera_rig.focus_on(visual_target_position)
	main.camera_rig.zoom_distance = 260.0
	main.camera_rig._update_camera()
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_combat_vfx.png")
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()
	for index: int in 30:
		await process_frame
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			(defense as CloseInGun).magazine.rounds = 0
			(defense as CloseInGun).magazine.reserve = 0
			defense._process(0.0)
			break
	main.altitude_profile.call("refresh_snapshot")
	if (main.altitude_profile.get("track_markers") as Array).is_empty() or (main.altitude_profile.get("projectile_markers") as Array).is_empty():
		push_error("Altitude profile did not render public tracks and friendly projectiles")
		quit(1)
		return
	_save_capture("/tmp/airscain_altitude_profile.png")
	_save_capture("/tmp/airscain_layered_defense.png")
	main.hud._on_c2_overlay_pressed()
	for index: int in 3:
		await process_frame
	if main.tactical_range_overlay.get("mode") != &"sensor":
		push_error("Sensor range overlay did not activate")
		quit(1)
		return
	_save_capture("/tmp/airscain_sensor_overlay.png")
	for index: int in 3:
		main.hud._on_c2_overlay_pressed()
	for index: int in 3:
		await process_frame
	if main.tactical_range_overlay.get("mode") != &"electronic":
		push_error("Electronic impact overlay did not activate")
		quit(1)
		return
	_save_capture("/tmp/airscain_electronic_overlay.png")
	main.hud._on_c2_overlay_pressed()
	main.hud._on_c2_overlay_pressed()
	var early_tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	if early_tracks.is_empty():
		push_error("No public track was available for tactical selection capture")
		quit(1)
		return
	main._on_world_selected(early_tracks[0].estimated_position)
	if main.selected_track == null or main.track_display.selection_lines.mesh == null:
		push_error("Selected track tactical relations were not rendered")
		quit(1)
		return
	for index: int in 3:
		await process_frame
	if main.hud.selected_track_label.text.is_empty() or not main.hud.selected_track_label.visible:
		push_error("Selected track detail panel was not populated")
		quit(1)
		return
	_save_capture("/tmp/airscain_tactical_selection.png")
	var review_source: DefenseUnit
	for defense: DefenseUnit in main.defenses:
		if defense.supports_engagement_controls():
			review_source = defense
			break
	if review_source == null:
		push_error("No armed asset was available for engagement review capture")
		quit(1)
		return
	main._on_asset_selected(review_source)
	main._on_world_selected(early_tracks[0].estimated_position)
	for index: int in 3:
		await process_frame
	if not main.hud.engagement_section.visible or main.track_display.selected_engagement_source != review_source:
		push_error("Engagement review did not preserve both selections")
		quit(1)
		return
	_save_capture("/tmp/airscain_engagement_review.png")
	for index: int in 150:
		await process_frame
	var known_tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	if not known_tracks.is_empty():
		main._on_world_selected(known_tracks[0].estimated_position)
	_save_capture("/tmp/airscain_combat.png")
	for defense: DefenseUnit in main.defenses:
		if defense is SearchRadar:
			defense.active = false
	main.set_process(false)
	main.player_knowledge.call("gameplay_tick", 0.7)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_coasting.png")
	_apply_city_building_impacts(main.objective.current_integrity, 4)
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_game_over.png")
	print("VISUAL_CAPTURE_OK initial catalog_wheel camera_rotation placement missile_battery_variants missile_smoke_trail combat_vfx strike_vfx altitude_profile layered_defense sensor_overlay electronic_overlay tactical_selection engagement_review combat coasting city_damage game_over")
	quit(0)

func _capture_operation_menus() -> void:
	var capture_save_path := "/tmp/airscain_operation_menu_save.json"
	_remove_capture_save(capture_save_path)
	var app := APP_SCENE.instantiate() as AirscainApp
	app.save_path = capture_save_path
	root.add_child(app)
	for index: int in 10:
		await process_frame
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	for index: int in 20:
		await process_frame
	if app.gameplay.hud.get_node_or_null("%SaveButton") != null or app.gameplay.hud.get_node_or_null("%LoadButton") != null or app.gameplay.hud.start_button.get_parent() != app.gameplay.hud:
		push_error("Gameplay controls still contain persistence actions or a catalog-owned start action")
		quit(1)
		return
	_save_capture("/tmp/airscain_preparation_start_control.png")
	app.set_pause_menu(true)
	app.pause_save_button.pressed.emit()
	await process_frame
	if app.pause_save_button.disabled or app.pause_load_button.disabled:
		push_error("Pause menu did not expose sustained-operation save and load actions")
		quit(1)
		return
	_save_capture("/tmp/airscain_pause_operation_menu.png")
	app.return_to_main_menu()
	await process_frame
	if app.main_load_button.disabled:
		push_error("Main menu did not expose the saved operation")
		quit(1)
		return
	_save_capture("/tmp/airscain_main_load_menu.png")
	app.main_load_button.pressed.emit()
	await process_frame
	if app.gameplay == null or app.main_menu.visible:
		push_error("Main-menu load did not enter the saved operation")
		quit(1)
		return
	_remove_capture_save(capture_save_path)
	print("VISUAL_CAPTURE_OK independent_start_control main_load pause_save_load")

func _remove_capture_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)

func _verify_catalog_wheel_input() -> void:
	var defense_scroll := main.hud.get_node("Catalog/VBox/DefenseScroll") as ScrollContainer
	var target_button: Button
	for child: Node in main.hud.defense_list.get_children():
		if child is Button:
			target_button = child as Button
			break
	if target_button == null:
		push_error("Catalog did not expose a child button for wheel verification")
		quit(1)
		return
	defense_scroll.scroll_vertical = 0
	Input.warp_mouse(target_button.get_global_rect().get_center())
	for index: int in 2:
		await process_frame
	for index: int in 3:
		var scroll_down := InputEventMouseButton.new()
		scroll_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
		scroll_down.pressed = true
		scroll_down.position = target_button.get_global_rect().get_center()
		scroll_down.global_position = scroll_down.position
		Input.parse_input_event(scroll_down)
		await process_frame
	if defense_scroll.scroll_vertical <= 0:
		push_error("Catalog wheel did not scroll while the pointer was over a child button")
		quit(1)
		return
	defense_scroll.scroll_vertical = int(defense_scroll.get_v_scroll_bar().max_value)
	var initial_zoom := main.camera_rig.zoom_distance
	var boundary_scroll := InputEventMouseButton.new()
	boundary_scroll.button_index = MOUSE_BUTTON_WHEEL_DOWN
	boundary_scroll.pressed = true
	boundary_scroll.position = defense_scroll.get_global_rect().get_center()
	boundary_scroll.global_position = boundary_scroll.position
	Input.parse_input_event(boundary_scroll)
	await process_frame
	if not is_equal_approx(main.camera_rig.zoom_distance, initial_zoom):
		push_error("Catalog boundary wheel propagated to the battlefield camera")
		quit(1)
		return
	defense_scroll.scroll_vertical = 0

func _capture_camera_rotation() -> void:
	var initial_yaw := main.camera_rig.yaw_radians
	var initial_camera_position := main.camera_rig.camera.position
	main.camera_rig.yaw_radians += deg_to_rad(55.0)
	main.camera_rig._update_camera()
	for index: int in 5:
		await process_frame
	if main.camera_rig.camera.position.is_equal_approx(initial_camera_position):
		push_error("Camera rotation did not orbit the battlefield view")
		quit(1)
		return
	_save_capture("/tmp/airscain_camera_rotated.png")
	main.camera_rig.yaw_radians = initial_yaw
	main.camera_rig._update_camera()

func _apply_requested_seed() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			AirscainMain.requested_seed = int(argument.trim_prefix("--seed="))
		elif argument == "--mode=training":
			AirscainMain.requested_mode = AirscainMain.GameMode.TRAINING
		elif argument == "--mode=sandbox":
			AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX

func _place_initial_assets() -> void:
	main.session.budget = 5000
	main._on_pressure_changed(5)
	_place_asset(main.scenario.available_defenses[0], -1.0)
	_place_asset(main.scenario.available_defenses[1], 1.0)
	_place_asset(main.scenario.available_defenses[2], 1.0)
	_place_asset(main.scenario.available_defenses[3], -1.0)
	_place_asset(main.scenario.available_defenses[4], 1.0)
	_place_asset(main.scenario.available_defenses[5], -1.0)
	_place_asset(main.scenario.available_defenses[6], 1.0)
	_place_asset(main.scenario.available_defenses[7], -1.0)
	_place_asset(main.scenario.available_defenses[8], 1.0)
	_place_asset(main.scenario.available_defenses[9], -1.0)
	_place_asset(main.scenario.available_defenses[10], 1.0)
	var rooftop_position: Vector3 = main.battlefield.rooftop_pads[0].position
	main.session.request_placement(main.scenario.available_defenses[1], rooftop_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)

func _capture_selection_panel() -> bool:
	main.session.budget = 5000
	main._on_pressure_changed(5)
	_place_asset(main.scenario.available_defenses[0], -1.0)
	_place_asset(main.scenario.available_defenses[1], 1.0)
	_place_asset(main.scenario.available_defenses[6], 1.0)
	var battery: DefenseUnit
	var radar: SearchRadar
	var laser: HighEnergyLaser
	for defense: DefenseUnit in main.defenses:
		if defense is MissileBattery:
			battery = defense
		elif defense is SearchRadar:
			radar = defense as SearchRadar
		elif defense is HighEnergyLaser:
			laser = defense as HighEnergyLaser
	if battery == null or radar == null or laser == null:
		push_error("Selection capture could not place its radar and armed assets")
		return false
	main._on_asset_selected(laser)
	for index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_power_asset_selection.png")
	main._on_asset_selected(battery)
	main.camera_rig.focus_on(battery.global_position)
	main.camera_rig.zoom_distance = 430.0
	main.camera_rig._update_camera()
	for index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_asset_selection.png")
	var threat := main.director.spawn_one()
	threat.global_position = radar.global_position + Vector3(180.0, 70.0, 0.0)
	radar.gameplay_tick(0.8)
	var tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	if tracks.is_empty():
		push_error("Selection capture did not produce a public track")
		return false
	var track := tracks[0]
	main._on_asset_selected(radar)
	main._on_world_selected(track.estimated_position)
	for index: int in 4:
		await process_frame
	if not main.hud.track_section.visible or radar.identity_marker.get("selected"):
		push_error("Track-only selection did not replace a non-weapon asset")
		return false
	_save_capture("/tmp/airscain_track_selection.png")
	main._on_asset_selected(battery)
	main._on_world_selected(track.estimated_position)
	for index: int in 4:
		await process_frame
	if not main.hud.engagement_section.visible or not bool(battery.identity_marker.get("selected")) or not main.track_display.engagement_distance_label.visible:
		push_error("Engagement review did not preserve the armed asset selection")
		return false
	_save_capture("/tmp/airscain_engagement_review.png")
	return true

func _spawn_swarm_near_close_in_gun() -> void:
	var gun: CloseInGun
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			gun = defense as CloseInGun
			break
	if gun == null:
		return
	var definition: ThreatDefinition = main.scenario.threat_entries[1].threat_definition
	for index: int in 4:
		var threat := definition.scene.instantiate() as ThreatUnit
		main.threat_parent.add_child(threat)
		threat.global_position = gun.global_position + Vector3(125.0 + float(index) * 7.0, 48.0, (float(index) - 1.5) * 9.0)
		threat.setup(1000 + index, definition)
		threat.configure_mission(main.objective, main.battlefield, main.objective.global_position, 1.0)
		main.registry.add(threat)
		main._on_threat_spawned(threat)

func _capture_close_in_gun_barrage() -> void:
	var gun: CloseInGun
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			gun = defense as CloseInGun
			break
	if gun == null:
		push_error("Close-in gun was not available for barrage capture")
		quit(1)
		return
	var target := gun.global_position + Vector3(230.0, 95.0, -35.0)
	for index: int in 8:
		gun._aim_turret(target, 0.25)
	var burst := preload("res://effects/tracer_burst/tracer_burst.tscn").instantiate() as TracerBurst
	main.projectile_parent.add_child(burst)
	burst.setup(gun.muzzle.global_position, target)
	burst._process(0.19)
	burst.set_process(false)
	gun.muzzle_flash.global_position = gun.muzzle.global_position
	gun.muzzle_flash.visible = true
	gun.muzzle_light.global_position = gun.muzzle.global_position
	gun.muzzle_light.visible = true
	var visible_tracers := 0
	for tracer: MeshInstance3D in burst.tracers:
		if tracer.visible:
			visible_tracers += 1
	if visible_tracers < 40:
		push_error("Close-in gun barrage did not expose enough simultaneous tracer streaks")
		quit(1)
		return
	var center := gun.muzzle.global_position.lerp(target, 0.5)
	main.camera_rig.camera.global_position = center + Vector3(20.0, 78.0, 190.0)
	main.camera_rig.camera.look_at(center, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	for index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_close_in_gun_barrage.png")

func _capture_hdr_light_vfx() -> void:
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	if not environment.glow_enabled or environment.glow_strength < 0.75:
		push_error("HDR glow environment was not enabled strongly enough")
		quit(1)
		return
	var center := main.objective.global_position + Vector3(0.0, 82.0, 260.0)
	var laser_from := center + Vector3(-92.0, -18.0, 0.0)
	var laser_to := center + Vector3(36.0, 18.0, 0.0)
	var pulse := preload("res://effects/laser_pulse/laser_pulse.tscn").instantiate() as LaserPulse
	main.projectile_parent.add_child(pulse)
	pulse.setup(laser_from, laser_to)
	var explosion := preload("res://effects/explosion/explosion.tscn").instantiate() as ExplosionEffect
	main.effects_parent.add_child(explosion)
	explosion.global_position = center + Vector3(92.0, 8.0, -12.0)
	explosion.setup(Color(1.0, 0.3, 0.04), 12.0)
	main.camera_rig.camera.global_position = center + Vector3(15.0, 72.0, 190.0)
	main.camera_rig.camera.look_at(center, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	await process_frame
	if not is_instance_valid(pulse) or not (pulse.get_node("Beam") as MeshInstance3D).mesh is CylinderMesh:
		push_error("Laser pulse did not render a volumetric core")
		quit(1)
		return
	_save_capture("/tmp/airscain_hdr_light_vfx.png")
	await _wait_seconds(0.22)
	main.camera_rig.camera.global_position = explosion.global_position + Vector3(0.0, 16.0, 48.0)
	main.camera_rig.camera.look_at(explosion.global_position, Vector3.UP)
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_explosion_close.png")

func _capture_city_detail() -> void:
	main.camera_rig.focus_on(main.objective.global_position)
	main.camera_rig.yaw_radians = deg_to_rad(32.0)
	main.camera_rig.zoom_distance = 285.0
	main.camera_rig._update_camera()
	main.hud.visible = false
	main.altitude_profile.visible = false
	for pad: MeshInstance3D in main.battlefield.rooftop_pad_visuals:
		if pad.visible:
			push_error("Rooftop placement pad was visible outside placement mode")
			quit(1)
			return
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_western_city_detail.png")
	var rooftop_definition := main.scenario.available_defenses[1]
	main.placement.select(rooftop_definition)
	var visible_pad_count := 0
	for pad: MeshInstance3D in main.battlefield.rooftop_pad_visuals:
		if pad.visible:
			visible_pad_count += 1
	if visible_pad_count == 0:
		push_error("Rooftop placement pads did not appear for a compatible asset")
		quit(1)
		return
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_western_city_rooftop_placement.png")
	main.placement.cancel()

func _capture_asset_catalog_and_support_base() -> void:
	main.hud.set_catalog_expanded(true)
	var support_button := main.hud.defense_buttons[5]
	main.hud.defense_scroll.ensure_control_visible(support_button)
	await process_frame
	Input.warp_mouse(support_button.get_global_rect().get_center())
	await _wait_seconds(1.0)
	if support_button.tooltip_text.count("\n") != 1 or not support_button.tooltip_text.contains("전력을 공급"):
		push_error("Support base purchase tooltip is not a two-line role summary")
		quit(1)
		return
	_save_capture("/tmp/airscain_asset_purchase_tooltip.png")
	main.session.budget = 5000
	_place_asset(main.scenario.available_defenses[5], -1.0)
	var support: SupportFacility
	for unit: DefenseUnit in main.defenses:
		if unit is SupportFacility:
			support = unit as SupportFacility
			break
	if support == null or support.get_node_or_null("Generator") == null or support.get_node_or_null("TransformerLeft") == null:
		push_error("Integrated support base visual is missing logistics or power equipment")
		quit(1)
		return
	main.hud.visible = false
	main.altitude_profile.visible = false
	main.camera_rig.camera.global_position = support.global_position + Vector3(42.0, 30.0, 48.0)
	main.camera_rig.camera.look_at(support.global_position + Vector3.UP * 4.0, Vector3.UP)
	await _wait_seconds(0.5)
	_save_capture("/tmp/airscain_integrated_support_base.png")

func _capture_topbar_menus() -> void:
	if main.hud.defense_menu_button.text != "방공 자산  ▼" or main.hud.city_menu_button.text != "도시 상태  100 / 100  ▼":
		push_error("Top bar menu labels do not expose defense assets and city status")
		quit(1)
		return
	main.hud.defense_menu_button.pressed.emit()
	await process_frame
	if not main.hud.catalog.visible or main.hud.city_menu.visible:
		push_error("Defense assets menu did not open by itself")
		quit(1)
		return
	_save_capture("/tmp/airscain_defense_assets_menu.png")
	main.objective.apply_mission_damage(20)
	main.hud.city_menu_button.pressed.emit()
	await process_frame
	if main.hud.catalog.visible or not main.hud.city_menu.visible:
		push_error("City status menu did not replace the defense assets menu")
		quit(1)
		return
	_save_capture("/tmp/airscain_city_status_menu.png")

func _capture_popup_input_priority() -> bool:
	main.session.unlimited_budget = true
	main._on_pressure_changed(5)
	_place_asset(main.scenario.available_defenses[0], -1.0)
	if main.defenses.is_empty():
		push_error("Could not place an asset for popup overlap verification")
		return false
	main._on_asset_selected(main.defenses[0])
	main.hud.set_catalog_expanded(true)
	for index: int in 2:
		await process_frame
	var catalog := main.hud.catalog
	var defense_scroll := main.hud.get_node("Catalog/VBox/DefenseScroll") as ScrollContainer
	var catalog_rect := catalog.get_global_rect()
	var selected_rect := main.hud.selected_asset_panel.get_global_rect()
	var scroll_rect := defense_scroll.get_global_rect()
	var overlap_start := Vector2(maxf(catalog_rect.position.x, maxf(selected_rect.position.x, scroll_rect.position.x)), maxf(catalog_rect.position.y, maxf(selected_rect.position.y, scroll_rect.position.y)))
	var overlap_end := Vector2(minf(catalog_rect.end.x, minf(selected_rect.end.x, scroll_rect.end.x)), minf(catalog_rect.end.y, minf(selected_rect.end.y, scroll_rect.end.y)))
	var overlap := Rect2(overlap_start, overlap_end - overlap_start)
	var target_button: Button
	var click_position := Vector2.ZERO
	for scroll_position: int in [0, int(defense_scroll.get_v_scroll_bar().max_value * 0.5), int(defense_scroll.get_v_scroll_bar().max_value)]:
		defense_scroll.scroll_vertical = scroll_position
		await process_frame
		for button: Button in main.hud.defense_buttons:
			var button_rect := button.get_global_rect()
			if button.disabled or not button_rect.intersects(overlap):
				continue
			var clickable_overlap := button_rect.intersection(overlap)
			if clickable_overlap.size.x >= 12.0 and clickable_overlap.size.y >= 12.0:
				target_button = button
				click_position = clickable_overlap.get_center()
				break
		if target_button != null:
			break
	if target_button == null:
		push_error("No enabled catalog row overlapped the selected asset panel")
		return false
	var target_index := main.hud.defense_buttons.find(target_button)
	Input.warp_mouse(click_position)
	for index: int in 2:
		await process_frame
	var hovered := main.get_viewport().gui_get_hovered_control()
	if hovered == null or not catalog.is_ancestor_of(hovered):
		push_error("The visually front catalog did not own the overlapping pointer position")
		return false
	_save_capture("/tmp/airscain_popup_input_priority.png")
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = click_position
		click.global_position = click_position
		Input.parse_input_event(click)
		await process_frame
	if main.placement.selected != main.scenario.available_defenses[target_index] or main.hud.catalog.visible:
		push_error("The overlapping catalog row did not receive the click")
		return false
	return true

func _capture_placement_dependencies() -> void:
	main.session.unlimited_budget = true
	main._on_pressure_changed(3)
	_place_asset(main.scenario.available_defenses[1], -1.0)
	_place_asset(main.scenario.available_defenses[2], 1.0)
	_place_asset(main.scenario.available_defenses[5], -1.0)
	var definition := main.scenario.available_defenses[6]
	var candidate := Vector3(0.0, main.battlefield.terrain_height(0.0, 0.0), 0.0)
	for z: int in range(-180, 181, 20):
		for x: int in range(-180, 181, 20):
			var tested := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(tested, definition.placement_profile).valid:
				candidate = tested
				break
		if main.battlefield.placement_result(candidate, definition.placement_profile).valid:
			break
	main.placement.select(definition)
	main.placement.process_mode = Node.PROCESS_MODE_DISABLED
	main.placement.candidate_position = candidate
	main.placement.preview.global_position = candidate
	main.placement.preview.visible = true
	main._on_placement_preview_changed(definition, candidate, true)
	for index: int in 5:
		await process_frame
	if not main.c2_overlay.placement_ready or main.c2_overlay.visible_link_count < 1:
		push_error("Placement preview did not show a ready C2 path")
		quit(1)
		return
	if not main.hud.placement_power_panel.visible or not main.hud.placement_power_label.text.contains("배치 후  12 / 20"):
		push_error("Placement preview did not show the energy power impact")
		quit(1)
		return
	_save_capture("/tmp/airscain_placement_dependencies.png")
	_place_asset(definition, 1.0)
	var support_definition := main.scenario.available_defenses[5]
	var support_candidate := candidate + Vector3(90.0, 0.0, 80.0)
	support_candidate.y = main.battlefield.terrain_height(support_candidate.x, support_candidate.z)
	main.placement.select(support_definition)
	main.placement.process_mode = Node.PROCESS_MODE_DISABLED
	main.placement.candidate_position = support_candidate
	main.placement.preview.global_position = support_candidate
	main.placement.preview.visible = true
	main._on_placement_preview_changed(support_definition, support_candidate, true)
	for index: int in 5:
		await process_frame
	if main.c2_overlay.visible_c2_link_count != 0 or main.c2_overlay.visible_support_link_count < 1 or not main.hud.placement_power_label.text.contains("배치 후  12 / 40"):
		push_error("Support base preview did not show its service relations and global power impact")
		quit(1)
		return
	_save_capture("/tmp/airscain_support_placement_dependencies.png")
	main.placement.cancel()
	for unit: DefenseUnit in main.defenses:
		if unit is SupportFacility:
			main._on_asset_selected(unit)
			break
	await process_frame
	if main.c2_overlay.visible_support_link_count < 1:
		push_error("Selected support base did not preserve its service relations")
		quit(1)
		return
	_save_capture("/tmp/airscain_support_selected_relations.png")

func _capture_offscreen_marker_full_edge() -> void:
	var viewport_size: Vector2 = root.get_visible_rect().size
	main.hud.set_catalog_expanded(false)
	var track := PlayerTrack.new()
	track.track_id = 9991
	track.state = PlayerTrack.State.CONFIRMED
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 1.0
	var altitude_profile_rect := main.altitude_profile.get_global_rect()
	var target_screen_position := Vector2(viewport_size.x + 500.0, altitude_profile_rect.get_center().y)
	track.estimated_position = main.camera_rig.camera.project_position(target_screen_position, 500.0) - Vector3.UP * 12.0
	main.player_knowledge.tracks.append(track)
	main.tactical_screen_overlay.select_track(track)
	for index: int in 3:
		await process_frame
	var marker: Vector2 = main.tactical_screen_overlay.track_marker_screen_position(track)
	if marker.x > viewport_size.x - TacticalScreenOverlay.EDGE_MARGIN + 0.01 or marker.x < viewport_size.x - TacticalScreenOverlay.EDGE_MARGIN - 0.01:
		push_error("Offscreen marker did not use the full viewport edge")
		quit(1)
		return
	var selected_marker_bounds := Rect2(marker - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
	if selected_marker_bounds.intersects(altitude_profile_rect):
		push_error("Offscreen marker overlaps the altitude profile")
		quit(1)
		return
	_save_capture("/tmp/airscain_offscreen_marker_full_edge.png")

func _capture_open_city_ground_placement() -> void:
	var definition := main.scenario.available_defenses[0]
	var profile := definition.placement_profile
	var open_position := Vector3.INF
	for z: int in range(-140, 141, 10):
		for x: int in range(-140, 141, 10):
			var candidate := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if Vector2(candidate.x, candidate.z).length() < main.objective.exclusion_radius and main.battlefield.placement_result(candidate, profile).valid:
				open_position = candidate
				break
		if open_position.is_finite():
			break
	if not open_position.is_finite():
		push_error("No open city ground remained available for placement")
		quit(1)
		return
	main.camera_rig.focus_on(open_position)
	main.camera_rig.yaw_radians = deg_to_rad(28.0)
	main.camera_rig.zoom_distance = 250.0
	main.camera_rig._update_camera()
	main.placement.select(definition)
	for index: int in 5:
		await process_frame
	Input.warp_mouse(main.camera_rig.camera.unproject_position(open_position))
	for index: int in 12:
		await process_frame
	if not main.placement.candidate_valid or main.placement.candidate_position.distance_to(open_position) > 3.0:
		push_error("Open city ground did not show a valid placement preview")
		quit(1)
		return
	_save_capture("/tmp/airscain_open_city_ground_placement.png")

func _capture_retarget_and_cruise_terminal_guidance() -> void:
	main.registry.clear()
	main.hud.visible = false
	main.altitude_profile.visible = false
	var threat_definition := main.scenario.threat_entries[0].threat_definition
	var original := threat_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(original)
	original.setup(9801, threat_definition)
	original.global_position = main.objective.global_position + Vector3(-20.0, 105.0, -25.0)
	main.registry.add(original)
	var alternate := threat_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(alternate)
	alternate.setup(9802, threat_definition)
	alternate.global_position = main.objective.global_position + Vector3(130.0, 115.0, 65.0)
	main.registry.add(alternate)
	var original_track := PlayerTrack.new()
	original_track.track_id = 9801
	original_track.state = PlayerTrack.State.CONFIRMED
	original_track.classification = threat_definition.signature_class
	original_track.affiliation = PlayerTrack.Affiliation.HOSTILE
	original_track.affiliation_confidence = 1.0
	original_track.estimated_position = original.global_position
	var alternate_track := PlayerTrack.new()
	alternate_track.track_id = 9802
	alternate_track.state = PlayerTrack.State.LOST
	alternate_track.classification = threat_definition.signature_class
	alternate_track.affiliation = PlayerTrack.Affiliation.HOSTILE
	alternate_track.affiliation_confidence = 1.0
	alternate_track.estimated_position = alternate.global_position
	var candidates: Array[PlayerTrack] = [original_track, alternate_track]
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = original.global_position + Vector3(-170.0, -10.0, 0.0)
	var munition := (main.scenario.available_defenses[0] as MissileBatteryDefinition).munitions[0]
	interceptor.configure(original_track, main.registry, munition, Vector3.RIGHT, 9800, 0, candidates)
	for index: int in 5:
		interceptor.gameplay_tick(0.05)
		await process_frame
	original.health = 0.0
	main.registry.remove(original)
	original.queue_free()
	for index: int in 10:
		interceptor.gameplay_tick(0.05)
		await process_frame
	if interceptor.target_track != original_track or interceptor.reacquisition_remaining <= 0.0 or interceptor.is_queued_for_deletion():
		push_error("Interceptor did not remain in the reacquisition grace state")
		quit(1)
		return
	var grace_center := interceptor.global_position
	main.camera_rig.camera.global_position = grace_center + Vector3(0.0, 75.0, 180.0)
	main.camera_rig.camera.look_at(grace_center, Vector3.UP)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_interceptor_reacquisition_grace.png")
	alternate_track.state = PlayerTrack.State.CONFIRMED
	interceptor.gameplay_tick(0.05)
	if interceptor.target_track != alternate_track or interceptor.reacquisition_remaining >= 0.0:
		push_error("Interceptor did not acquire the alternate visible track")
		quit(1)
		return
	for index: int in 20:
		if not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.05)
		await process_frame
	var retarget_center := original_track.estimated_position.lerp(alternate_track.estimated_position, 0.35)
	main.camera_rig.camera.global_position = retarget_center + Vector3(0.0, 115.0, 260.0)
	main.camera_rig.camera.look_at(retarget_center, Vector3.UP)
	for index: int in 8:
		await process_frame
	_save_capture("/tmp/airscain_interceptor_retarget.png")
	if is_instance_valid(interceptor):
		interceptor.queue_free()
	alternate.queue_free()
	main.registry.clear()
	if OS.get_cmdline_user_args().has("--capture-reacquisition-only"):
		return
	var cruise_entry := main.scenario.threat_entries[5]
	var cruise_definition := cruise_entry.threat_definition as AttackUavDefinition
	var cruise := main.director._spawn_entry(cruise_entry, 0.0, 0.0) as AttackUav
	var target := cruise.mission_runtime.fixed_target
	cruise.global_position = target + Vector3(cruise_definition.movement.terminal_distance * 0.8, cruise_definition.movement.cruise_altitude, 0.0)
	cruise.mover.velocity = Vector3(0.0, 0.0, cruise_definition.movement.speed)
	main.camera_rig.camera.global_position = target + Vector3(145.0, 105.0, 190.0)
	main.camera_rig.camera.look_at(target + Vector3.UP * 12.0, Vector3.UP)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_cruise_terminal_approach.png")
	var maximum_height := cruise.global_position.y
	for frame: int in 80:
		cruise.gameplay_tick(0.25)
		maximum_height = maxf(maximum_height, cruise.global_position.y)
		if cruise.resolved_state:
			break
		await process_frame
	if not cruise.resolved_state or maximum_height > main.battlefield.flight_surface_height(target.x, target.z) + cruise_definition.movement.cruise_altitude + 1.0:
		push_error("Cruise missile climbed out instead of completing terminal impact")
		quit(1)
		return
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_cruise_terminal_impact.png")

func _capture_curved_missile_launch() -> void:
	main.registry.clear()
	main.hud.visible = false
	main.altitude_profile.visible = false
	var definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	var battery := definition.scene.instantiate() as MissileBattery
	main.effects_parent.add_child(battery)
	battery.setup(9701, definition)
	battery.global_position = main.objective.global_position + Vector3(-120.0, 0.0, 210.0)
	battery.global_position.y = main.battlefield.terrain_height(battery.global_position.x, battery.global_position.z)
	battery.configure_combat(main.registry, main.projectile_parent)
	var launch_origin := battery.launch_point.global_position
	var launch_direction := battery.launcher_forward()
	var target_direction := launch_direction.rotated(Vector3.UP, deg_to_rad(battery.launch_sector_degrees * 0.68))
	var target_position := launch_origin + target_direction * 360.0
	var initial_yaw := battery.turret.rotation.y
	var initial_pitch := battery.elevation.rotation.x
	if not battery._aim_turret(target_position, 0.1) or battery.turret.rotation.y != initial_yaw or battery.elevation.rotation.x != initial_pitch:
		push_error("Battery rotated despite target being inside its launch sector")
		quit(1)
		return
	var track := PlayerTrack.new()
	track.track_id = 9702
	track.state = PlayerTrack.State.CONFIRMED
	track.classification = &"aircraft"
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 1.0
	track.estimated_position = target_position
	battery._spawn_interceptor(track, definition.munitions[0], 0, 0.0)
	var interceptor := battery.interceptors[0]
	if interceptor.velocity.normalized().angle_to(target_direction) < deg_to_rad(10.0):
		push_error("Interceptor did not depart along the physical launcher direction")
		quit(1)
		return
	for index: int in 24:
		interceptor.gameplay_tick(0.04)
		await process_frame
	var closest_on_launch_ray := Geometry3D.get_closest_point_to_segment(interceptor.global_position, launch_origin, launch_origin + launch_direction * 600.0)
	if interceptor.global_position.distance_to(closest_on_launch_ray) < 8.0:
		push_error("Interceptor departure path did not curve toward the off-axis target")
		quit(1)
		return
	var camera_target := launch_origin.lerp(interceptor.global_position, 0.5)
	main.camera_rig.camera.global_position = camera_target + Vector3(80.0, 90.0, 210.0)
	main.camera_rig.camera.look_at(camera_target, Vector3.UP)
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_curved_missile_launch.png")

func _capture_building_impact_smoke() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	var closest_index := 0
	var closest_distance := INF
	for index: int in main.battlefield.city_buildings.size():
		var distance := main.battlefield.city_building_bounds(index).get_center().distance_squared_to(main.objective.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	var bounds := main.battlefield.city_building_bounds(closest_index)
	var target := bounds.get_center()
	var definition := main.scenario.threat_entries[0].threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	threat.setup(9801, definition)
	var start_position := Vector3(bounds.position.x - 55.0, target.y, target.z)
	var expected_impact := main.battlefield.building_segment_impact(start_position, target)
	if expected_impact.is_empty():
		push_error("Building impact capture path did not cross the city")
		quit(1)
		return
	threat.global_position = start_position
	threat.configure_mission(main.objective, main.battlefield, target, 1.0)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var expected_position := expected_impact.position as Vector3
	main.camera_rig.camera.global_position = expected_position + Vector3(-105.0, 70.0, 135.0)
	main.camera_rig.camera.look_at(expected_position, Vector3.UP)
	for tick: int in 80:
		if threat.resolved_state:
			break
		threat.gameplay_tick(0.05)
		if threat.resolved_state:
			break
		await process_frame
	if not threat.resolved_state or main.objective.damage_smoke_effects.is_empty():
		push_error("Threat did not resolve against a procedural building")
		quit(1)
		return
	var resolved_position: Vector3 = threat.global_position
	var smoke_effect := main.objective.damage_smoke_effects.back() as Node3D
	var smoke_position: Vector3 = smoke_effect.global_position
	if smoke_position.distance_to(resolved_position) > 0.01:
		push_error("Building smoke did not start at the swept impact point")
		quit(1)
		return
	await _wait_simulation_seconds(0.5)
	_save_capture("/tmp/airscain_building_impact_smoke.png")
	await _wait_simulation_seconds(2.7)
	var smoke := smoke_effect.get_node("Smoke") as GPUParticles3D
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	var smoke_shadow := smoke.get_node("SmokeShadow") as GPUParticles3D
	if smoke.amount < 1500 or smoke_process.spread > 7.0 or smoke_process.initial_velocity_min < 7.5 or smoke_process.initial_velocity_max > 10.5 or smoke_process.gravity.y >= 0.0 or smoke_process.gravity.x <= 0.0 or not smoke_shadow.draw_pass_1 is SphereMesh:
		push_error("Building smoke did not keep dense decelerating motion and round shadow geometry")
		quit(1)
		return
	_save_capture("/tmp/airscain_building_smoke_dense.png")
	await _wait_simulation_seconds(2.8)
	_save_capture("/tmp/airscain_building_smoke_crosswind.png")

func _capture_smoke_ground_shadow() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	(interceptor.get_node("Missile") as MeshInstance3D).visible = false
	(interceptor.get_node("Trail") as MeshInstance3D).visible = false
	(interceptor.get_node("FlameLight") as OmniLight3D).visible = false
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	var center := main.objective.global_position + Vector3(-340.0, 0.0, -80.0)
	var ground_height := main.battlefield.terrain_height(center.x, center.z)
	var smoke_height := ground_height + 28.0
	var from_position := Vector3(center.x - 95.0, smoke_height, center.z)
	var to_position := Vector3(center.x + 95.0, smoke_height, center.z)
	interceptor.global_position = from_position
	for step_index: int in 20:
		var next_position := from_position.lerp(to_position, float(step_index + 1) / 20.0)
		smoke.sample_world_segment(interceptor.global_position, next_position)
		interceptor.global_position = next_position
		await process_frame
	smoke.emitting = false
	main.camera_rig.camera.global_position = center + Vector3(0.0, 115.0, 145.0)
	main.camera_rig.camera.look_at(Vector3(center.x, ground_height + 12.0, center.z), Vector3.UP)
	smoke.speed_scale = 0.0
	for frame_index: int in 60:
		await process_frame
	_save_capture("/tmp/airscain_smoke_ground_shadow.png")
	var smoke_shadow := smoke.get_node("SmokeShadow") as GPUParticles3D
	smoke_shadow.visible = false
	for frame_index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_smoke_without_shadow.png")
	smoke_shadow.visible = true
	smoke.release_to(main.effects_parent)
	smoke._process(smoke.release_fade_duration * 0.5)
	for frame_index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_smoke_shadow_half_faded.png")
	smoke._process(smoke.release_fade_duration * 0.35)
	for frame_index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_smoke_shadow_near_end.png")
	if smoke.current_shadow_opacity_ratio >= 0.1:
		push_error("Smoke shadow opacity did not fade continuously with visible smoke")

func _capture_explosion_instance_isolation() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	var center := main.objective.global_position + Vector3(-260.0, 55.0, -110.0)
	var explosion_scene := preload("res://effects/explosion/explosion.tscn")
	var first := explosion_scene.instantiate() as ExplosionEffect
	main.effects_parent.add_child(first)
	first.global_position = center + Vector3.LEFT * 42.0
	first.setup(Color(1.0, 0.3, 0.04), 12.0)
	(first.get_node("Smoke") as GPUParticles3D).emitting = false
	(first.get_node("Sparks") as GPUParticles3D).emitting = false
	first._process(1.1)
	first.set_process(false)
	var second := explosion_scene.instantiate() as ExplosionEffect
	main.effects_parent.add_child(second)
	second.global_position = center + Vector3.RIGHT * 42.0
	second.setup(Color(1.0, 0.52, 0.08), 12.0)
	(second.get_node("Smoke") as GPUParticles3D).emitting = false
	(second.get_node("Sparks") as GPUParticles3D).emitting = false
	second._process(0.18)
	second.set_process(false)
	var first_material := first.get_node("Shockwave").get("material_override") as StandardMaterial3D
	if first_material.albedo_color.a > 0.001:
		push_error("A later explosion reactivated the faded shockwave")
		quit(1)
		return
	main.camera_rig.camera.global_position = center + Vector3(0.0, 70.0, 180.0)
	main.camera_rig.camera.look_at(center, Vector3.UP)
	for index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_explosion_instance_isolation.png")

func _capture_friendly_missile_terrain_impact() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	var x := -330.0
	var z := 160.0
	var ground_height := main.battlefield.terrain_height(x, z)
	var track := PlayerTrack.new()
	track.track_id = 8801
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = Vector3(x, ground_height - 120.0, z)
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 1.0
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = Vector3(x, ground_height + 18.0, z)
	var munition := (main.scenario.available_defenses[0] as MissileBatteryDefinition).munitions[0]
	interceptor.configure(track, main.registry, munition, Vector3.DOWN, 8802, 0, [track], main.battlefield)
	interceptor.gameplay_tick(0.12)
	var explosion := main.projectile_parent.get_node_or_null("Explosion") as ExplosionEffect
	if not interceptor.is_queued_for_deletion() or explosion == null or absf(explosion.global_position.y - ground_height) > 0.1:
		push_error("Friendly missile did not stop at the terrain surface")
		quit(1)
		return
	explosion._process(0.12)
	explosion.set_process(false)
	var center := Vector3(x, ground_height + 5.0, z)
	main.camera_rig.camera.global_position = center + Vector3(65.0, 48.0, 105.0)
	main.camera_rig.camera.look_at(center, Vector3.UP)
	for index: int in 4:
		await process_frame
	_save_capture("/tmp/airscain_friendly_missile_terrain_impact.png")

func _capture_hpm_bird_fall() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	for existing_threat: ThreatUnit in main.registry.get_active():
		existing_threat.queue_free()
	main.registry.clear()
	await process_frame
	main._on_pressure_changed(5)
	var hpm_definition := main.scenario.available_defenses[9] as HighPowerMicrowaveDefinition
	_place_asset(hpm_definition, -1.0)
	var hpm: HighPowerMicrowave
	for defense: DefenseUnit in main.defenses:
		if defense.definition.id == hpm_definition.id:
			hpm = defense as HighPowerMicrowave
			break
	if hpm == null:
		push_error("Could not place HPM for bird fall capture")
		quit(1)
		return
	var bird_definition := main.scenario.ambient_contacts[0]
	var bird := bird_definition.scene.instantiate() as BirdContact
	main.threat_parent.add_child(bird)
	var target_position := hpm.global_position + Vector3(105.0, 70.0, 0.0)
	bird.global_position = target_position
	bird.setup(9820, bird_definition)
	bird.configure_patrol(main.battlefield, Vector3(14.0, 0.0, 3.0))
	main.registry.add(bird)
	main._on_threat_spawned(bird)
	var track := PlayerTrack.new()
	track.track_id = bird.runtime_id
	track.estimated_position = bird.global_position
	while not bird.resolved_state:
		hpm._fire_pulse(track)
	var falling_bird := main.effects_parent.get_node_or_null("FallingWreck") as FallingWreckEffect
	if falling_bird == null or (falling_bird.get_node("SmokeTrail") as GPUParticles3D).emitting or main.effects_parent.get_node_or_null("Explosion") != null:
		push_error("HPM-neutralized bird did not enter a clean falling state")
		quit(1)
		return
	falling_bird._process(0.42)
	falling_bird.set_process(false)
	main.camera_rig.camera.global_position = target_position + Vector3(95.0, 55.0, 135.0)
	main.camera_rig.camera.look_at(target_position + Vector3.DOWN * 8.0, Vector3.UP)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_hpm_bird_fall.png")

func _capture_missile_rack_rapid_fire() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	var definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	var battery := definition.scene.instantiate() as MissileBattery
	main.effects_parent.add_child(battery)
	battery.global_position = Vector3(-330.0, main.battlefield.terrain_height(-330.0, -140.0), -140.0)
	battery.setup(9830, definition)
	battery.configure_combat(main.registry, main.projectile_parent)
	var target_position := battery.launch_point.global_position + battery.launcher_forward() * 420.0 + Vector3.UP * 55.0
	var track := PlayerTrack.new()
	track.track_id = 9831
	track.state = PlayerTrack.State.CONFIRMED
	track.classification = &"cruise_missile"
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 1.0
	track.estimated_position = target_position
	var munition := definition.munitions[0]
	battery._fire_round(track, munition)
	if battery.interceptors.size() != 1:
		push_error("Missile rack did not launch exactly one ready round")
		quit(1)
		return
	for frame_index: int in ceili(definition.launch_interval / 0.05):
		for interceptor: HomingInterceptor in battery.interceptors:
			interceptor.gameplay_tick(0.05)
		await process_frame
	battery._fire_round(track, munition)
	if battery.interceptors.size() != 2:
		push_error("Missile rack did not launch the next ready round")
		quit(1)
		return
	for interceptor: HomingInterceptor in battery.interceptors:
		interceptor.gameplay_tick(definition.launch_interval)
	for launch_index: int in munition.magazine_capacity - 2:
		battery._fire_round(track, munition)
		for frame_index: int in 4:
			for interceptor: HomingInterceptor in battery.interceptors:
				if is_instance_valid(interceptor) and not interceptor.is_queued_for_deletion():
					interceptor.gameplay_tick(0.05)
			await process_frame
	battery._process(0.0)
	if battery.magazines[munition.id].rounds != 0 or not battery.magazines[munition.id].is_reloading() or battery.status_marker.visible or battery._launcher_caps().any(func(cap: Node3D) -> bool: return cap.visible):
		push_error("Missile rack did not empty its cells or retained a cluttering ammunition label")
		quit(1)
		return
	var camera_target := battery.global_position + Vector3(0.0, 13.0, -34.0)
	main.camera_rig.camera.global_position = battery.global_position + Vector3(62.0, 38.0, 92.0)
	main.camera_rig.camera.look_at(camera_target, Vector3.UP)
	for frame_index: int in 8:
		await process_frame
	_save_capture("/tmp/airscain_missile_rack_rapid_fire.png")

func _capture_time_control_buttons() -> void:
	var fast_button := main.hud.get_node("%FastButton") as Button
	fast_button.pressed.emit()
	for frame_index: int in 4:
		await process_frame
	if main.session.simulation_speed != 2.0 or not fast_button.button_pressed or main.hud.get_node_or_null("%SpeedLabel") != null:
		push_error("Speed controls retained a duplicate label or did not highlight the current button")
		quit(1)
		return
	_save_capture("/tmp/airscain_time_controls_2x.png")
	var pause_button := main.hud.get_node("%PauseButton") as Button
	pause_button.pressed.emit()
	for frame_index: int in 4:
		await process_frame
	if not is_zero_approx(main.session.simulation_speed) or not pause_button.button_pressed or fast_button.button_pressed:
		push_error("Pause button did not become the sole selected time state")
		quit(1)
		return
	_save_capture("/tmp/airscain_time_controls_paused.png")

func _capture_training_guidance() -> bool:
	if main.game_mode != AirscainMain.GameMode.TRAINING:
		push_error("Training guidance capture requires --mode=training")
		return false
	main.hud.set_catalog_expanded(false)
	await process_frame
	var marker_without_catalog: Vector2 = main.tactical_screen_overlay.call("training_marker_screen_position")
	var approach_label_rect: Rect2 = main.tactical_screen_overlay.call("training_approach_label_rect")
	if approach_label_rect.intersects(main.hud.training_panel.get_global_rect()):
		push_error("Training approach label overlaps the training panel")
		return false
	_save_capture("/tmp/airscain_training_entry_clear.png")
	main.hud.set_catalog_expanded(true)
	await process_frame
	var marker_with_catalog: Vector2 = main.tactical_screen_overlay.call("training_marker_screen_position")
	if not marker_with_catalog.is_equal_approx(marker_without_catalog):
		push_error("Training approach marker moved when the asset menu opened")
		return false
	_save_capture("/tmp/airscain_training_entry_catalog_open.png")
	main.hud.set_catalog_expanded(false)
	main.training_controller._set_step(TrainingController.Step.SUPPORT)
	await process_frame
	if main.hud.catalog_expanded or not main.hud.training_panel.visible:
		push_error("Training support step opened the asset catalog over its instructions")
		return false
	_save_capture("/tmp/airscain_training_support_instructions.png")
	main.training_controller._set_step(TrainingController.Step.ACQUIRE)
	await process_frame
	if bool(main.tactical_screen_overlay.get("training_approach_visible")):
		push_error("Training approach remained visible during target acquisition")
		return false
	_save_capture("/tmp/airscain_training_acquire_clear.png")
	var track_position := main.objective.global_position + Vector3.RIGHT * main.scenario.battlefield_size * 1.5
	track_position.y = main.battlefield.flight_surface_height(track_position.x, track_position.z) + 80.0
	var observation := SensorObservation.new()
	observation.setup(9802, 0.0, track_position, 0.95, 4.0, 0.4, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.8)
	var track: PlayerTrack = main.player_knowledge.call("submit_observation", observation)
	main._refresh_tactical_ui()
	if main.training_controller.step != TrainingController.Step.ACQUIRE or not is_equal_approx(main.session.simulation_speed, 1.0):
		push_error("Training paused for an unselectable tentative track")
		return false
	observation = SensorObservation.new()
	observation.setup(9802, 0.1, track_position, 0.95, 4.0, 0.4, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.8)
	track = main.player_knowledge.call("submit_observation", observation)
	main._refresh_tactical_ui()
	var marker_position: Vector2 = main.tactical_screen_overlay.call("track_marker_screen_position", track)
	if main.training_controller.step != TrainingController.Step.SELECT_TRACK or not is_zero_approx(main.session.simulation_speed) or not marker_position.is_finite():
		push_error("Training did not pause with a selectable confirmed distant track")
		return false
	Input.warp_mouse(marker_position)
	for frame_index: int in 4:
		await process_frame
	await _send_left_click(marker_position)
	if main.selected_track != track or main.training_controller.step != TrainingController.Step.SELECT_ASSET:
		var selected_id := main.selected_track.track_id if main.selected_track != null else -1
		push_error("Actual click on the distant track marker did not select it (expected=%d selected=%d step=%d)" % [track.track_id, selected_id, main.training_controller.step])
		return false
	_save_capture("/tmp/airscain_training_distant_track_selected.png")
	return true

func _capture_sandbox_continuous_input() -> bool:
	if main.game_mode != AirscainMain.GameMode.SANDBOX:
		push_error("Sandbox input capture requires --mode=sandbox")
		return false
	main.hud.set_catalog_expanded(true)
	await process_frame
	var defense_definition := main.scenario.available_defenses[0]
	var defense_button := main.hud.defense_buttons[0]
	var positions := _visible_valid_placement_positions(defense_definition.placement_profile, 6)
	if positions.size() < 6:
		push_error("Could not find enough visible sandbox placement positions")
		return false
	var defense_count_before := main.defenses.size()
	await _click_control(defense_button)
	if main.placement.selected != defense_definition:
		push_error("Visible sandbox defense button did not activate placement")
		return false
	await _click_world_position(positions[0])
	if main.defenses.size() != defense_count_before + 1 or main.placement.selected != defense_definition:
		push_error("Sandbox defense mode ended after the first actual click")
		return false
	await _click_world_position(positions[1])
	if main.defenses.size() != defense_count_before + 2 or main.placement.selected != defense_definition:
		push_error("Sandbox defense mode did not place continuously")
		return false
	var hostile_count_before := main.registry.hostile_count()
	main.hud.set_threat_menu_expanded(true)
	await process_frame
	await _click_control(main.hud.sandbox_threat_button)
	var initial_definition := main.hud.threat_definitions[main.hud.sandbox_threat_option.selected]
	await _click_world_position(positions[2])
	await _click_world_position(positions[3])
	if main.registry.hostile_count() != hostile_count_before + 2 or main.placement.selected_threat != initial_definition:
		push_error("Sandbox threat mode did not place continuously")
		return false
	var replacement_index := 1
	var replacement_definition := main.hud.threat_definitions[replacement_index]
	main.hud.sandbox_threat_option.select(replacement_index)
	main.hud.sandbox_threat_option.item_selected.emit(replacement_index)
	await process_frame
	await _click_world_position(positions[4])
	var last_threat: ThreatUnit = main.registry.get_hostile_active().back()
	if last_threat.definition != replacement_definition or main.placement.selected_threat != replacement_definition:
		push_error("Sandbox threat dropdown change did not reach the active placement mode")
		return false
	Input.warp_mouse(main.camera_rig.camera.unproject_position(positions[5]))
	for frame_index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_sandbox_continuous_input.png")
	return true

func _visible_valid_placement_positions(profile: PlacementProfile, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for z: int in range(-520, 521, 30):
		for x: int in range(-520, 521, 30):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if not main.battlefield.placement_result(position, profile).valid or main.camera_rig.camera.is_position_behind(position):
				continue
			var screen_position := main.camera_rig.camera.unproject_position(position)
			if screen_position.x < 70.0 or screen_position.x > 1180.0 or screen_position.y < 110.0 or screen_position.y > 820.0:
				continue
			var separated := true
			for existing: Vector3 in result:
				if existing.distance_to(position) < 70.0:
					separated = false
					break
			if not separated:
				continue
			result.append(position)
			if result.size() >= count:
				return result
	return result

func _click_control(control: Control) -> void:
	var screen_position := control.get_global_rect().get_center()
	Input.warp_mouse(screen_position)
	for frame_index: int in 3:
		await process_frame
	await _send_left_click(screen_position)

func _click_world_position(world_position: Vector3) -> void:
	var screen_position := main.camera_rig.camera.unproject_position(world_position)
	Input.warp_mouse(screen_position)
	for frame_index: int in 4:
		await process_frame
	await _send_left_click(screen_position)

func _send_left_click(screen_position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = screen_position
		event.global_position = screen_position
		Input.parse_input_event(event)
		await process_frame

func _capture_surface_strike_smoke() -> void:
	main.hud.visible = false
	main.altitude_profile.visible = false
	var target := main.objective.global_position
	var found_open_ground := false
	for radius: float in [90.0, 120.0, 150.0, 180.0]:
		for angle_index: int in 16:
			var angle := TAU * float(angle_index) / 16.0
			var candidate := main.objective.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			if main.battlefield.overlaps_city_building(candidate, 3.0):
				continue
			candidate.y = main.battlefield.terrain_height(candidate.x, candidate.z)
			target = candidate
			found_open_ground = true
			break
		if found_open_ground:
			break
	if not found_open_ground:
		push_error("Could not find open city ground for strike capture")
		quit(1)
		return
	var definition := main.scenario.threat_entries[11].threat_definition as AttackUavDefinition
	var strike := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(strike)
	strike.global_position = target + Vector3(0.0, definition.movement.terminal_altitude, 80.0)
	strike.setup(9810, definition)
	strike.configure_mission(main.objective, main.battlefield, target, 1.0, null, strike.global_position + Vector3(600.0, 0.0, 0.0))
	var integrity_before := main.objective.current_integrity
	strike.gameplay_tick(0.1)
	if main.objective.current_integrity != integrity_before or main.threat_parent.get_node_or_null("StrikeMunition") == null:
		push_error("Surface strike did not defer damage to its visible munition")
		quit(1)
		return
	main.camera_rig.camera.global_position = target + Vector3(95.0, 72.0, 120.0)
	main.camera_rig.camera.look_at(target + Vector3.UP * 8.0, Vector3.UP)
	for frame_index: int in 120:
		if main.threat_parent.get_node_or_null("StrikeMunition") == null:
			break
		await process_frame
	if main.objective.current_integrity != integrity_before - roundi(definition.mission.damage) or main.objective.damage_smoke_effects.is_empty():
		push_error("Surface strike did not apply damage and smoke at munition impact")
		quit(1)
		return
	var smoke_effect := main.objective.damage_smoke_effects.back() as Node3D
	if smoke_effect.global_position.distance_to(target) > 0.01:
		push_error("Surface strike smoke was not attached to the impact point")
		quit(1)
		return
	await _wait_simulation_seconds(0.7)
	_save_capture("/tmp/airscain_surface_strike_smoke.png")

func _apply_city_building_impacts(total_damage: int, impact_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = main.scenario.world_seed ^ 0x31D4A7
	var remaining_damage := total_damage
	for impact_index: int in impact_count:
		var target := main.battlefield.random_city_building_target(rng)
		var approach := target + Vector3(rng.randf_range(-45.0, 45.0), 180.0, rng.randf_range(-45.0, 45.0))
		var impact := main.battlefield.building_segment_impact(approach, target)
		if impact.is_empty():
			continue
		var damage := remaining_damage if impact_index == impact_count - 1 else maxi(1, roundi(float(total_damage) / float(impact_count)))
		remaining_damage -= damage
		main.objective.apply_building_impact(damage, impact.position, float(impact.building_height))

func _capture_city_smoke_and_ammo_status() -> void:
	var target := main.objective.global_position
	var smoke_start_msec := Time.get_ticks_msec()
	_apply_city_building_impacts(55, 3)
	var smoke_spawn_msec := Time.get_ticks_msec() - smoke_start_msec
	if smoke_spawn_msec > 100:
		push_error("City smoke spawn blocked the main thread for %dms" % smoke_spawn_msec)
		quit(1)
		return
	main.camera_rig.camera.global_position = target + Vector3(125.0, 82.0, 145.0)
	main.camera_rig.camera.look_at(target + Vector3.UP * 32.0, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	await _wait_simulation_seconds(0.8)
	if main.objective.damage_smoke_effects.size() < 3:
		push_error("City damage did not create dense multi-site smoke")
		quit(1)
		return
	var emitter_positions: Array[Vector3] = []
	for effect: Node3D in main.objective.damage_smoke_effects:
		emitter_positions.append((effect.get_node("Smoke") as GPUParticles3D).global_position)
	_save_capture("/tmp/airscain_city_damage_smoke.png")
	await _wait_simulation_seconds(2.4)
	var city_smoke := main.objective.damage_smoke_effects[0].get_node("Smoke") as GPUParticles3D
	var city_process := city_smoke.process_material as ParticleProcessMaterial
	var city_growth := city_process.scale_curve as CurveTexture
	if not city_smoke.emitting or city_smoke.amount < 1500 or city_smoke.lifetime < 18.0 or city_process.spread > 7.0 or city_process.initial_velocity_min < 7.5 or city_process.initial_velocity_max > 10.5 or city_process.gravity.y >= 0.0 or city_process.gravity.x <= 0.0 or city_process.turbulence_enabled or city_growth == null or city_growth.curve.sample(0.0) >= city_growth.curve.sample(1.0):
		push_error("City smoke did not maintain a stable rising plume")
		quit(1)
		return
	_save_capture("/tmp/airscain_city_damage_smoke_rising.png")
	await _wait_simulation_seconds(2.8)
	_save_capture("/tmp/airscain_city_damage_smoke_plume.png")
	if city_smoke.amount < 1500 or city_smoke.capture_aabb().size.y < 24.0:
		push_error("City smoke plume lacks sustained rising particle density")
		quit(1)
		return
	for index: int in main.objective.damage_smoke_effects.size():
		var smoke := main.objective.damage_smoke_effects[index].get_node("Smoke") as GPUParticles3D
		if smoke.local_coords or smoke.global_position.distance_to(emitter_positions[index]) > 0.001 or main.objective.damage_smoke_effects[index].get_node_or_null("SmokeMiddle") != null:
			push_error("City smoke emitter moved or retained obsolete plume layers")
			quit(1)
			return
	main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	var gun: CloseInGun
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			gun = defense as CloseInGun
			break
	if gun == null:
		push_error("Close-in gun was unavailable for ammunition status capture")
		quit(1)
		return
	gun.magazine.rounds = 0
	gun.magazine.reserve = 0
	gun._process(0.0)
	var label := gun.status_marker.get_node("Label") as Label3D
	if label.text != "탄약 고갈" or label.pixel_size > 0.0011:
		push_error("Depleted ammunition status was not concise and screen-sized")
		quit(1)
		return
	main.camera_rig.camera.global_position = gun.global_position + Vector3(42.0, 28.0, 52.0)
	main.camera_rig.camera.look_at(gun.global_position + Vector3.UP * 11.0, Vector3.UP)
	await _wait_seconds(0.2)
	_save_capture("/tmp/airscain_ammo_depleted_status.png")
	gun.receive_damage(gun.definition.maximum_integrity * 0.5)
	gun._process(0.0)
	var unit_smoke: GPUParticles3D = gun.damage_smoke.get_node("Smoke") as GPUParticles3D if gun.damage_smoke != null else null
	var unit_process: ParticleProcessMaterial = unit_smoke.process_material as ParticleProcessMaterial if unit_smoke != null else null
	var unit_growth: CurveTexture = unit_process.scale_curve as CurveTexture if unit_process != null else null
	var identity_icon := gun.identity_marker.get_node("Icon") as Label3D
	if gun.damage_smoke == null or label.text != "손상" or not label.no_depth_test or label.render_priority < 100 or not identity_icon.no_depth_test or identity_icon.render_priority < 100 or unit_growth == null or unit_growth.curve.sample(0.0) >= unit_growth.curve.sample(1.0):
		push_error("Damaged unit did not expose smoke and a damage status marker")
		quit(1)
		return
	main.camera_rig.camera.global_position = gun.global_position + Vector3(48.0, 34.0, 62.0)
	main.camera_rig.camera.look_at(gun.global_position + Vector3.UP * 18.0, Vector3.UP)
	await _wait_simulation_seconds(3.0)
	var status_screen_position := main.camera_rig.camera.unproject_position(gun.status_marker.global_position)
	var identity_screen_position := main.camera_rig.camera.unproject_position(gun.identity_marker.global_position)
	if status_screen_position.distance_to(identity_screen_position) < 14.0:
		push_error("Damage status and role icon overlap at the tactical camera distance")
		quit(1)
		return
	_save_capture("/tmp/airscain_damaged_unit_smoke.png")

func _capture_friendly_identity_icons() -> void:
	var icons: Dictionary = {}
	for defense: DefenseUnit in main.defenses:
		if defense.identity_marker == null or not defense.identity_marker.visible:
			push_error("Friendly defense did not expose an identity marker")
			quit(1)
			return
		var icon := defense.identity_marker.get_node("Icon") as Label3D
		icons[icon.text] = true
	if not icons.has("◎") or not icons.has("◆") or not icons.has("▲") or not icons.has("■"):
		push_error("Friendly identity markers did not cover every asset role")
		quit(1)
		return
	main.camera_rig.focus_on(main.objective.global_position)
	main.camera_rig.yaw_radians = deg_to_rad(24.0)
	main.camera_rig.zoom_distance = 620.0
	main.camera_rig._update_camera()
	main.hud.visible = false
	main.altitude_profile.visible = false
	for index: int in 12:
		await process_frame
	_save_capture("/tmp/airscain_friendly_identity_icons.png")

func _capture_missile_battery_variants() -> void:
	var definitions: Array[MissileBatteryDefinition] = [
		main.scenario.available_defenses[8] as MissileBatteryDefinition,
		main.scenario.available_defenses[0] as MissileBatteryDefinition,
		main.scenario.available_defenses[7] as MissileBatteryDefinition,
	]
	var expected_nodes: Array[String] = ["QuickReactionCluster", "SixCellRack", "FourCanisterBank"]
	var showcase: Array[MissileBattery] = []
	var center := main.objective.global_position + Vector3(0.0, 0.0, 360.0)
	for index: int in definitions.size():
		var battery := definitions[index].scene.instantiate() as MissileBattery
		main.effects_parent.add_child(battery)
		battery.setup(-100 - index, definitions[index])
		var position := center + Vector3((float(index) - 1.0) * 30.0, 0.0, 0.0)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		battery.global_position = position
		battery.rotation.y = -0.45
		if battery.get_node_or_null("Turret/Elevation/Launcher/%s" % expected_nodes[index]) == null:
			push_error("Missile battery variant did not expose its distinct launcher silhouette")
			quit(1)
			return
		showcase.append(battery)
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	main.camera_rig.camera.global_position = center + Vector3(58.0, 34.0, 72.0)
	main.camera_rig.camera.look_at(center + Vector3.UP * 7.0, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_missile_battery_variants.png")
	for battery: MissileBattery in showcase:
		battery.queue_free()
	main.hud.visible = true
	main.altitude_profile.visible = true
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()

func _capture_strike_vfx() -> void:
	var strike := main.director._spawn_entry(main.scenario.threat_entries[11], 0.0, 0.0) as AttackUav
	var target := main.objective.global_position
	strike.global_position = target + Vector3(0.0, 105.0, 20.0)
	strike.configure_mission(main.objective, main.battlefield, target, 1.0, null, strike.global_position + Vector3(500.0, 0.0, 0.0))
	strike.gameplay_tick(0.1)
	var munition := main.threat_parent.get_node_or_null("StrikeMunition") as Node3D
	if munition == null:
		push_error("Strike aircraft did not release its visible munition")
		quit(1)
		return
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	main.camera_rig.camera.global_position = target + Vector3(130.0, 125.0, 165.0)
	main.camera_rig.camera.look_at(target + Vector3.UP * 58.0, Vector3.UP)
	main.hud.visible = false
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_strike_vfx.png")
	main.hud.visible = true
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()

func _capture_missile_smoke_trail() -> void:
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	var start := main.objective.global_position + Vector3(-120.0, 95.0, -35.0)
	var target := PlayerTrack.new()
	target.track_id = 9901
	target.state = PlayerTrack.State.CONFIRMED
	target.estimated_position = main.objective.global_position + Vector3(150.0, 125.0, -35.0)
	interceptor.global_position = start
	var battery_definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(target, ThreatRegistry.new(), battery_definition.munitions[0], start.direction_to(target.estimated_position), 9901)
	for index: int in 18:
		interceptor.gameplay_tick(0.04)
		await process_frame
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	var midpoint := start.lerp(interceptor.global_position, 0.5)
	var overview_camera_position := midpoint + Vector3(0.0, 75.0, 190.0)
	main.camera_rig.camera.global_position = overview_camera_position
	main.camera_rig.camera.look_at(midpoint, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	await _wait_seconds(0.35)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	var smoke_bounds := smoke.smoke_bounds()
	_save_capture("/tmp/airscain_missile_smoke_trail.png")
	main.camera_rig.camera.global_position = midpoint + Vector3(0.0, 11.0, 34.0)
	main.camera_rig.camera.look_at(midpoint, Vector3.UP)
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_missile_smoke_close.png")
	main.camera_rig.camera.global_position = overview_camera_position
	main.camera_rig.camera.look_at(midpoint, Vector3.UP)
	if smoke_bounds.size.length() < 25.0:
		push_error("Missile smoke trail did not produce a visible particle footprint")
		quit(1)
		return
	smoke.call("release_to", main.effects_parent)
	interceptor.queue_free()
	var fade_quarter := smoke.release_fade_duration * 0.25
	await _wait_seconds(fade_quarter)
	var aged_smoke_bounds := smoke.smoke_bounds()
	_save_capture("/tmp/airscain_missile_smoke_aged.png")
	if maxf(aged_smoke_bounds.size.y, aged_smoke_bounds.size.z) < 4.0:
		push_error("Missile smoke trail did not develop a visible turbulent cross-section")
		quit(1)
		return
	var aged_opacity := smoke.current_opacity_ratio
	await _wait_seconds(fade_quarter)
	_save_capture("/tmp/airscain_missile_smoke_fading.png")
	var fading_opacity := smoke.current_opacity_ratio
	await _wait_seconds(fade_quarter)
	_save_capture("/tmp/airscain_missile_smoke_near_end.png")
	var near_end_opacity := smoke.current_opacity_ratio
	if not (aged_opacity > fading_opacity and fading_opacity > near_end_opacity and near_end_opacity > 0.0):
		push_error("Missile smoke trail opacity did not decrease continuously")
		quit(1)
		return
	await _wait_seconds(fade_quarter + 0.05)
	_save_capture("/tmp/airscain_missile_smoke_transparent_tail.png")
	if not is_instance_valid(smoke) or smoke.current_opacity_ratio > 0.001 or smoke.release_remaining <= 0.0:
		push_error("Missile smoke trail was not fully transparent before cleanup")
		quit(1)
		return
	await _wait_seconds(smoke.transparent_cleanup_delay + 0.1)
	if is_instance_valid(smoke):
		push_error("Fully transparent missile smoke trail was not cleaned up")
		quit(1)
		return
	var self_destruct := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(self_destruct)
	var lost_track := PlayerTrack.new()
	lost_track.track_id = 9902
	lost_track.state = PlayerTrack.State.LOST
	lost_track.estimated_position = midpoint
	self_destruct.global_position = midpoint + Vector3(0.0, 15.0, 0.0)
	self_destruct.configure(lost_track, ThreatRegistry.new(), battery_definition.munitions[0], Vector3.FORWARD, 9902)
	self_destruct.gameplay_tick(HomingInterceptor.REACQUISITION_GRACE_DURATION + 0.05)
	for index: int in 3:
		await process_frame
	var detonation := main.projectile_parent.get_node_or_null("Explosion") as ExplosionEffect
	if detonation == null or detonation.effect_radius < 7.0:
		push_error("Interceptor self-destruct did not leave a visible detonation")
		quit(1)
		return
	_save_capture("/tmp/airscain_interceptor_self_destruct.png")
	await _capture_countermeasure_defeat(midpoint)
	main.hud.visible = true
	main.altitude_profile.visible = true
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()

func _capture_countermeasure_defeat(center: Vector3, capture_resolved_after: bool = true) -> void:
	for effect: Node in main.projectile_parent.get_children():
		if effect.name == "Explosion" or effect.name == "InterceptorMiss":
			effect.queue_free()
	await process_frame
	var strike_definition := main.scenario.threat_entries[11].threat_definition as AttackUavDefinition
	var strike := strike_definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(strike)
	strike.setup(9950, strike_definition)
	strike.global_position = center + Vector3(48.0, 12.0, 0.0)
	main.registry.add(strike)
	var track := PlayerTrack.new()
	track.track_id = 9950
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = strike.global_position
	track.estimated_velocity = Vector3(96.0, 0.0, 0.0)
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = strike.global_position + Vector3(-100.0, 0.0, 0.0)
	var long_range := main.scenario.available_defenses[7] as MissileBatteryDefinition
	interceptor.configure(track, main.registry, long_range.munitions[0], Vector3.RIGHT, 9950)
	var test_rng := RandomNumberGenerator.new()
	var successful_seed := 1
	while successful_seed < 1000:
		test_rng.seed = successful_seed
		if test_rng.randf() < strike_definition.chaff_effectiveness * long_range.munitions[0].radar_sensitivity:
			break
		successful_seed += 1
	interceptor.rng.seed = successful_seed
	interceptor.gameplay_tick(0.01)
	for index: int in 10:
		await process_frame
	var burst := main.projectile_parent.get_node_or_null("CountermeasureBurst") as Node3D
	if burst == null or burst.get_node_or_null("Reason") != null or not (burst.get_node("Chaff") as GPUParticles3D).emitting or not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
		push_error("Chaff did not create a label-free cloud and delayed interceptor diversion")
		quit(1)
		return
	var chaff := burst.get_node("Chaff") as GPUParticles3D
	var initial_chaff_bounds := chaff.capture_aabb()
	_save_capture("/tmp/airscain_chaff_cloud.png")
	await _wait_seconds(2.0)
	var settled_chaff_bounds := chaff.capture_aabb()
	if settled_chaff_bounds.size.length() > initial_chaff_bounds.size.length() + 8.0:
		push_error("Chaff cloud expanded after its initial volume was established")
		quit(1)
		return
	_save_capture("/tmp/airscain_chaff_shimmer.png")
	for tick: int in 40:
		if not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.05)
		await process_frame
	var miss := main.projectile_parent.get_node_or_null("InterceptorMiss") as InterceptorMissEffect
	if is_instance_valid(interceptor) or miss == null or (miss.get_node("Reason") as Label3D).text != "유도 이탈":
		push_error("Chaff-diverted interceptor did not miss after flying toward the decoy cloud")
		quit(1)
		return
	_save_capture("/tmp/airscain_countermeasure_defeat.png")
	main.registry.remove(strike)
	strike.queue_free()
	if capture_resolved_after:
		await _capture_resolved_target_interceptor(center)

func _capture_resolved_target_interceptor(center: Vector3) -> void:
	for effect: Node in main.projectile_parent.get_children():
		if effect.name == "Explosion" or effect.name == "InterceptorMiss" or effect.name == "CountermeasureBurst":
			effect.queue_free()
	await process_frame
	main.registry.clear()
	var threat_definition := main.scenario.threat_entries[0].threat_definition
	var threat := threat_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(threat)
	threat.setup(9960, threat_definition)
	threat.global_position = center + Vector3(110.0, 18.0, 0.0)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var track := PlayerTrack.new()
	track.track_id = 9960
	track.state = PlayerTrack.State.CONFIRMED
	track.classification = threat_definition.signature_class
	track.estimated_position = threat.global_position
	track.position_uncertainty = 8.0
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = threat.global_position + Vector3(-260.0, 0.0, 0.0)
	var battery_definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(track, main.registry, battery_definition.munitions[0], Vector3.RIGHT, 9960)
	for index: int in 5:
		interceptor.gameplay_tick(0.05)
		await process_frame
	var position_at_resolution := interceptor.global_position
	threat.receive_damage(10000.0)
	interceptor.gameplay_tick(0.05)
	if interceptor.is_queued_for_deletion() or interceptor.global_position.y <= position_at_resolution.y:
		push_error("Interceptor did not climb after its correlated target was destroyed")
		quit(1)
		return
	for tick: int in ceili(interceptor.maximum_lifetime / 0.05) + 1:
		if not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.05)
		await process_frame
	var explosion := main.projectile_parent.get_node_or_null("Explosion") as Node3D
	if is_instance_valid(interceptor) or main.projectile_parent.get_node_or_null("InterceptorMiss") != null or explosion == null:
		push_error("Destroyed-target interceptor did not complete its climb with a clean self-destruct")
		quit(1)
		return
	var capture_center := position_at_resolution.lerp(explosion.global_position, 0.5)
	main.camera_rig.camera.global_position = capture_center + Vector3(40.0, 35.0, 680.0)
	main.camera_rig.camera.look_at(capture_center, Vector3.UP)
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_target_resolved_interceptor.png")

func _place_asset(definition: DefenseDefinition, direction: float) -> void:
	for offset: int in range(0, 180, 10):
		var position := Vector3(direction * (210.0 + float(offset)), 0.0, 0.0)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		if main.battlefield.placement_result(position, definition.placement_profile).valid:
			main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			return

func _save_capture(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save visual capture: %s" % error_string(error))

func _wait_seconds(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _wait_simulation_seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await process_frame
		elapsed += minf(main.get_process_delta_time(), 0.1)
