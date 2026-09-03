extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func before_each() -> void:
	AirscainMain.requested_seed = 73129
	main = add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	await get_tree().process_frame

func test_scenario_starts_with_generated_world_and_preparation_state() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1600)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 900)
	assert_not_null(main.objective)
	assert_gt(main.battlefield.terrain.mesh.get_surface_count(), 0)
	var terrain_material := main.battlefield.terrain.material_override as ShaderMaterial
	assert_not_null(terrain_material)
	assert_true(terrain_material.shader.code.contains("contour_distance"))
	assert_eq(main.battlefield.battlefield_size, 2400.0)
	assert_eq((main.battlefield.ocean.mesh as PlaneMesh).size.x, 19200.0)
	assert_eq(main.camera_rig.camera.far, 14400.0)
	assert_gt(main.battlefield.city_visuals.get_child_count(), 30)
	assert_eq(main.registry.count(), 4)
	assert_eq(main.registry.hostile_count(), 0)
	assert_eq(main.session.phase, GameSession.Phase.PREPARATION)
	for pad: MeshInstance3D in main.battlefield.rooftop_pad_visuals:
		assert_false(pad.visible)
	assert_eq(main.session.budget, main.scenario.starting_budget)
	assert_eq(main.scenario.available_defenses.size(), 11)
	assert_eq(main.scenario.available_defenses[1].id, &"search_radar")
	assert_eq(main.scenario.available_defenses[2].id, &"command_post")
	assert_eq(main.scenario.available_defenses[3].id, &"tracking_radar")
	assert_eq(main.scenario.available_defenses[4].id, &"close_in_gun")
	assert_eq(main.scenario.available_defenses[5].id, &"support_facility")
	assert_eq(main.scenario.available_defenses[6].id, &"high_energy_laser")
	assert_eq(main.scenario.threat_entries[1].threat_definition.id, &"swarm_uav")
	assert_eq(main.scenario.threat_entries[1].group_size, 4)
	assert_eq(main.scenario.threat_entries.size(), 12)
	assert_eq(main.scenario.threat_entries[2].threat_definition.id, &"recon_uav")
	assert_eq(main.scenario.threat_entries[3].threat_definition.id, &"support_strike_uav")
	assert_eq(main.scenario.threat_entries[4].threat_definition.id, &"command_strike_uav")
	assert_eq(main.scenario.threat_entries[5].threat_definition.id, &"cruise_missile")
	assert_eq(main.scenario.threat_entries[6].threat_definition.id, &"decoy_uav")
	assert_eq(main.scenario.threat_entries[7].threat_definition.id, &"electronic_warfare_uav")
	assert_eq(main.scenario.threat_entries[8].threat_definition.id, &"anti_radiation_missile")
	assert_eq(main.scenario.threat_entries[9].threat_definition.id, &"ballistic_missile")
	assert_eq(main.scenario.threat_entries[10].threat_definition.id, &"rocket")
	assert_eq(main.scenario.threat_entries[11].threat_definition.id, &"strike_aircraft")
	assert_false(main.session.start_defense())

func test_time_control_buttons_are_the_only_speed_state_indicator() -> void:
	var pause_button := main.hud.get_node("%PauseButton") as Button
	var normal_button := main.hud.get_node("%NormalButton") as Button
	var fast_button := main.hud.get_node("%FastButton") as Button
	var very_fast_button := main.hud.get_node("%VeryFastButton") as Button
	assert_null(main.hud.get_node_or_null("%SpeedLabel"))
	assert_true(normal_button.button_pressed)
	assert_false(pause_button.button_pressed)
	var selected_style := normal_button.get_theme_stylebox("pressed") as StyleBoxFlat
	assert_not_null(selected_style)
	assert_gt(selected_style.bg_color.b, 0.65)
	assert_gt(selected_style.bg_color.a, 0.9)
	fast_button.pressed.emit()
	assert_eq(main.session.simulation_speed, 2.0)
	assert_true(fast_button.button_pressed)
	assert_false(normal_button.button_pressed)
	very_fast_button.pressed.emit()
	assert_eq(main.session.simulation_speed, 4.0)
	assert_true(very_fast_button.button_pressed)
	pause_button.pressed.emit()
	assert_eq(main.session.simulation_speed, 0.0)
	assert_true(pause_button.button_pressed)
	assert_false(very_fast_button.button_pressed)

func test_pressure_unlocks_advanced_defense_in_domain_and_catalog() -> void:
	var definition := main.scenario.available_defenses[3]
	var position := _find_valid_position_for(definition.placement_profile)
	var locked_result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_false(locked_result.success)
	assert_string_contains(locked_result.reason, "전투 강도 2")
	assert_true(main.hud.defense_buttons[3].disabled)
	assert_string_contains(main.hud.defense_buttons[3].text, "강도 2 해금")
	main._on_pressure_changed(2)
	assert_false(main.hud.defense_buttons[3].disabled)
	assert_true(main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent).success)

func test_training_mode_guides_real_deployment_flow_and_disables_saves() -> void:
	AirscainMain.requested_mode = AirscainMain.GameMode.TRAINING
	var training := add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	await get_tree().process_frame
	assert_eq(training.game_mode, AirscainMain.GameMode.TRAINING)
	assert_eq(training.training_step, AirscainMain.TrainingStep.CAMERA)
	assert_true(training.hud.training_panel.visible)
	assert_string_contains(training.hud.training_title.text, "1/13")
	assert_true(bool(training.tactical_screen_overlay.get("training_approach_visible")))
	var approach_position: Vector3 = training.tactical_screen_overlay.get("training_approach_position")
	assert_gt(approach_position.x, training.objective.global_position.x + training.scenario.battlefield_size * 0.55)
	assert_lte(training.battlefield.terrain_height(approach_position.x, approach_position.z), training.battlefield.generator.sea_level)
	var approach_marker: Vector2 = training.tactical_screen_overlay.call("training_marker_screen_position")
	assert_lte(approach_marker.x, training.tactical_screen_overlay.size.x - TacticalScreenOverlay.EDGE_MARGIN)
	assert_gte(approach_marker.y, 100.0)
	assert_eq(training.tactical_screen_overlay.call("training_approach_label_text"), "훈련 표적 진입")
	training.camera_rig.yaw_radians += PI * 0.5
	training.camera_rig._update_camera()
	var rotated_marker: Vector2 = training.tactical_screen_overlay.call("training_marker_screen_position")
	assert_lte(rotated_marker.x, training.tactical_screen_overlay.size.x - TacticalScreenOverlay.EDGE_MARGIN)
	assert_gte(rotated_marker.y, 100.0)
	training.camera_rig.yaw_radians -= PI * 0.5
	training.camera_rig._update_camera()
	assert_true(training.hud.save_button.disabled)
	training._on_training_next_requested()
	assert_eq(training.training_step, AirscainMain.TrainingStep.RADAR)
	var radar_result := _place_for(training, training.scenario.available_defenses[1])
	assert_true(radar_result.success)
	assert_eq(training.training_step, AirscainMain.TrainingStep.COMMAND)
	var command_result := _place_for(training, training.scenario.available_defenses[2])
	assert_true(command_result.success)
	assert_eq(training.training_step, AirscainMain.TrainingStep.WEAPON)
	var battery_result := _place_for(training, training.scenario.available_defenses[0])
	assert_true(battery_result.success)
	var battery := battery_result.unit as MissileBattery
	assert_true(battery.doctrine.hold_fire)
	assert_eq(training.training_step, AirscainMain.TrainingStep.START)
	var hostile_count := training.registry.hostile_count()
	training._on_start_requested()
	assert_eq(training.training_step, AirscainMain.TrainingStep.ACQUIRE)
	assert_false(training.director.enabled)
	assert_eq(training.registry.hostile_count(), hostile_count + 1)
	var threat: ThreatUnit = training.registry.get_hostile_active().back()
	assert_gt(threat.global_position.x, training.objective.global_position.x + training.scenario.battlefield_size * 0.55)
	assert_lte(training.battlefield.terrain_height(threat.global_position.x, threat.global_position.z), training.battlefield.generator.sea_level)
	assert_eq(training.session.simulation_speed, 1.0)
	var observation := SensorObservation.new()
	observation.setup((radar_result.unit as DefenseUnit).runtime_id, 0.0, threat.global_position, 0.95, 4.0, 0.4, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.8)
	var track: PlayerTrack = training.player_knowledge.call("submit_observation", observation)
	training._refresh_tactical_ui()
	assert_eq(training.training_step, AirscainMain.TrainingStep.SELECT_TRACK)
	assert_eq(training.session.simulation_speed, 0.0)
	assert_false(bool(training.tactical_screen_overlay.get("training_approach_visible")))
	training._on_world_selected(track.estimated_position)
	assert_eq(training.training_step, AirscainMain.TrainingStep.SELECT_ASSET)
	training._on_asset_selected(battery)
	assert_eq(training.training_step, AirscainMain.TrainingStep.DOCTRINE)
	assert_true(training.hud.hold_fire_button.button_pressed)
	training._on_hold_fire_requested(false)
	assert_false(battery.doctrine.hold_fire)
	assert_eq(training.training_step, AirscainMain.TrainingStep.ENGAGE)
	assert_eq(training.session.simulation_speed, 1.0)
	training._on_threat_resolved(threat, true, threat.definition.neutralization_reward)
	assert_eq(training.training_step, AirscainMain.TrainingStep.SUPPORT)
	assert_eq(training.session.simulation_speed, 0.0)
	assert_true(_place_for(training, training.scenario.available_defenses[5]).success)
	assert_eq(training.training_step, AirscainMain.TrainingStep.RESUPPLY)
	assert_eq(battery.magazine.reserve, 0)
	assert_null(training.selected_asset)
	training._on_asset_selected(battery)
	assert_false(training.hud.resupply_button.disabled)
	training._on_resupply_requested()
	assert_eq(training.training_step, AirscainMain.TrainingStep.OVERLAY)
	assert_eq(training.support_manager.tasks.size(), 1)
	training._on_overlay_requested(&"sensor")
	assert_eq(training.training_step, AirscainMain.TrainingStep.COMPLETE)
	assert_string_contains(training.hud.training_title.text, "훈련 완료")
	assert_eq(training.session.simulation_speed, 1.0)
	training._on_save_requested()
	assert_string_contains(training.hud.feedback_label.text, "지속 작전")

func test_sandbox_mode_has_free_assets_and_places_selected_threats() -> void:
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	var sandbox := add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	await get_tree().process_frame
	assert_true(sandbox.session.unlimited_budget)
	assert_eq(sandbox.session.current_pressure, 999)
	assert_true(sandbox.hud.sandbox_threat_option.visible)
	assert_true(sandbox.hud.save_button.disabled)
	var starting_budget := sandbox.session.budget
	var defense_definition := sandbox.scenario.available_defenses[10]
	var defense_positions: Array[Vector3] = []
	for z: int in range(-420, 421, 30):
		for x: int in range(-420, 421, 30):
			var position := Vector3(float(x), sandbox.battlefield.terrain_height(float(x), float(z)), float(z))
			if sandbox.battlefield.placement_result(position, defense_definition.placement_profile).valid:
				defense_positions.append(position)
				if defense_positions.size() == 2:
					break
		if defense_positions.size() == 2:
			break
	assert_eq(defense_positions.size(), 2)
	sandbox.placement.select(defense_definition)
	sandbox.placement.candidate_position = defense_positions[0]
	assert_true(sandbox.placement.request_selected_defense_placement())
	assert_same(sandbox.placement.selected, defense_definition)
	assert_not_null(sandbox.placement.preview)
	sandbox.placement.candidate_position = defense_positions[1]
	assert_true(sandbox.placement.request_selected_defense_placement())
	assert_same(sandbox.placement.selected, defense_definition)
	assert_not_null(sandbox.placement.preview)
	assert_eq(sandbox.session.budget, starting_budget)
	var definition: ThreatDefinition = sandbox.scenario.threat_entries[0].threat_definition
	var hostile_count := sandbox.registry.hostile_count()
	sandbox.placement.select_sandbox_threat(definition)
	sandbox.placement.candidate_position = Vector3(420.0, 0.0, -180.0)
	assert_true(sandbox.placement.request_selected_sandbox_threat_placement())
	assert_eq(sandbox.registry.hostile_count(), hostile_count + 1)
	var threat: ThreatUnit = sandbox.registry.get_hostile_active().back()
	assert_almost_eq(threat.global_position.x, 420.0, 0.001)
	assert_almost_eq(threat.global_position.z, -180.0, 0.001)
	assert_same(sandbox.placement.selected_threat, definition)
	assert_not_null(sandbox.placement.preview)
	sandbox.placement.candidate_position = Vector3(520.0, 0.0, -80.0)
	assert_true(sandbox.placement.request_selected_sandbox_threat_placement())
	assert_eq(sandbox.registry.hostile_count(), hostile_count + 2)
	var second_threat: ThreatUnit = sandbox.registry.get_hostile_active().back()
	assert_almost_eq(second_threat.global_position.x, 520.0, 0.001)
	assert_almost_eq(second_threat.global_position.z, -80.0, 0.001)
	assert_same(sandbox.placement.selected_threat, definition)
	var replacement_definition: ThreatDefinition = sandbox.scenario.threat_entries[1].threat_definition
	var replacement_index := sandbox.hud.threat_definitions.find(replacement_definition)
	sandbox.hud.sandbox_threat_option.select(replacement_index)
	sandbox.hud.sandbox_threat_option.item_selected.emit(replacement_index)
	assert_same(sandbox.placement.selected_threat, replacement_definition)
	assert_not_null(sandbox.placement.preview)
	sandbox.placement.candidate_position = Vector3(610.0, 0.0, 40.0)
	assert_true(sandbox.placement.request_selected_sandbox_threat_placement())
	assert_same(sandbox.registry.get_hostile_active().back().definition, replacement_definition)
	sandbox._on_start_requested()
	assert_false(sandbox.director.enabled)

func test_combat_audio_is_disabled_until_production_sources_exist() -> void:
	var streams: Dictionary = main.combat_audio.get("streams")
	assert_false(main.combat_audio.get("enabled"))
	assert_true(streams.is_empty())
	assert_true((main.combat_audio.get("players") as Array).is_empty())
	assert_false(main.combat_audio.call("play_event", &"contact", 0.5))
	main._on_pressure_changed(3)
	assert_eq(int(main.combat_audio.call("played_count", &"pressure")), 0)
	var result: Dictionary = main.session.request_placement(main.scenario.available_defenses[0], _find_valid_position_for(main.scenario.available_defenses[0].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var unit := result.unit as DefenseUnit
	unit.weapon_fired.emit(unit, true)
	assert_eq(int(main.combat_audio.call("played_count", &"launch")), 0)
	assert_eq(int(main.combat_audio.call("played_count", &"low_ammo")), 0)
	unit.receive_damage(50.0)
	assert_eq(int(main.combat_audio.call("played_count", &"damage")), 0)

func test_search_radar_can_be_purchased_and_rotates_during_gameplay() -> void:
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var placement_position := _find_valid_position_for(radar_definition.placement_profile)
	var result: Dictionary = main.session.request_placement(radar_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	assert_eq(main.session.budget, main.scenario.starting_budget - radar_definition.price)
	var radar := result.unit as DefenseUnit
	assert_not_null(radar)
	var antenna := radar.get_node("Antenna") as Node3D
	var starting_rotation: float = antenna.rotation.y
	radar.gameplay_tick(1.0)
	assert_ne(antenna.rotation.y, starting_rotation)
	assert_eq(main.enemy_knowledge.best_estimate_for_role(&"sensor").asset_id, radar.runtime_id)

func test_long_range_launcher_exposes_munition_mode_control() -> void:
	var definition := main.scenario.available_defenses[7]
	main._on_pressure_changed(definition.unlock_pressure_level)
	var position := _find_valid_position_for(definition.placement_profile)
	var result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var battery := result.unit as MissileBattery
	main._on_asset_selected(battery)
	assert_true(main.hud.munition_mode_button.visible)
	assert_eq(battery.munition_mode, &"auto")
	main.hud._on_munition_mode_pressed()
	assert_eq(battery.munition_mode, &"area_defense")
	assert_string_contains(main.hud.munition_mode_button.text, "광역방공탄")

func test_search_radar_observes_only_threats_inside_its_coverage() -> void:
	main.registry.clear()
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var placement_position := _find_valid_position_for(radar_definition.placement_profile)
	var result: Dictionary = main.session.request_placement(radar_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := result.unit as DefenseUnit
	var visible_threat: ThreatUnit = main.director.spawn_one()
	visible_threat.global_position = placement_position + Vector3(0.0, 80.0, 180.0)
	var hidden_threat: ThreatUnit = main.director.spawn_one()
	hidden_threat.global_position = placement_position + Vector3(0.0, 80.0, 700.0)
	radar.gameplay_tick(0.8)
	var tracks: Array = main.player_knowledge.call("get_active_tracks")
	assert_eq(tracks.size(), 1)
	assert_ne(tracks[0] as Variant, visible_threat as Variant)
	assert_almost_eq((tracks[0].get("estimated_position") as Vector3).z, visible_threat.global_position.z, 0.01)
	assert_eq(main.track_display.markers.size(), 1)
	var marker := main.track_display.markers.values()[0] as Node3D
	assert_true(marker.visible)
	radar.active = false
	main.player_knowledge.call("gameplay_tick", 0.6)
	assert_true(marker.visible)
	main.player_knowledge.call("gameplay_tick", 1.4)
	assert_false(marker.visible)

func test_high_altitude_radar_tracks_targets_above_search_radar_ceiling() -> void:
	main.registry.clear()
	main.player_knowledge.call("reset")
	main._on_pressure_changed(2)
	var search_definition := main.scenario.available_defenses[1]
	var high_definition := main.scenario.available_defenses[3]
	var search_result: Dictionary = main.session.request_placement(search_definition, _find_valid_position_for(search_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var high_result: Dictionary = main.session.request_placement(high_definition, _find_valid_position_for(high_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var search_radar := search_result.unit as SearchRadar
	var high_radar := high_result.unit as SearchRadar
	var threat := main.director.spawn_one()
	var target_ground := main.battlefield.terrain_height(high_radar.global_position.x, high_radar.global_position.z + 220.0)
	threat.global_position = Vector3(high_radar.global_position.x, target_ground + 700.0, high_radar.global_position.z + 220.0)
	assert_false(search_radar.altitude_in_envelope(threat.global_position))
	assert_true(high_radar.altitude_in_envelope(threat.global_position))
	search_radar.gameplay_tick(0.8)
	high_radar.gameplay_tick(0.8)
	var tracks: Array = main.player_knowledge.call("get_active_tracks")
	assert_eq(tracks.size(), 1)
	assert_eq(tracks[0].contributing_sensor_ids, [high_radar.runtime_id])
	assert_string_contains(high_radar.resource_status_text(), "감시 고도 120–1500m")

func test_altitude_profile_shows_public_tracks_and_friendly_projectiles_by_layer() -> void:
	main.player_knowledge.call("reset")
	var track := PlayerTrack.new()
	track.track_id = 501
	track.estimated_position = main.objective.global_position + Vector3(120.0, 920.0, 0.0)
	track.state = PlayerTrack.State.CONFIRMED
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 0.9
	main.player_knowledge.tracks.append(track)
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = main.objective.global_position + Vector3(-80.0, 320.0, 0.0)
	main.altitude_profile.call("refresh_snapshot")
	assert_true(main.altitude_profile.visible)
	assert_lte(main.altitude_profile.size.x, 150.0)
	assert_eq((main.altitude_profile.get("track_markers") as Array).size(), 1)
	assert_eq((main.altitude_profile.get("projectile_markers") as Array).size(), 1)
	var low_y := float(main.altitude_profile.call("altitude_to_plot_y", 100.0))
	var medium_y := float(main.altitude_profile.call("altitude_to_plot_y", 300.0))
	var high_y := float(main.altitude_profile.call("altitude_to_plot_y", 1000.0))
	assert_gt(low_y, medium_y)
	assert_gt(medium_y, high_y)
	assert_true(interceptor.is_in_group("friendly_altitude_projectiles"))
	interceptor.queue_free()

func test_defense_catalog_is_grouped_by_role_and_does_not_overlap_altitude_profile() -> void:
	var headings: Array[String] = []
	for child: Node in main.hud.defense_list.get_children():
		if child is Label:
			headings.append((child as Label).text)
	assert_eq(headings, ["감시·추적", "지휘·지원", "미사일 방어", "근접·특수 요격"])
	assert_eq(main.hud.defense_buttons.size(), main.scenario.available_defenses.size())
	for index: int in main.hud.defense_buttons.size():
		assert_true(is_instance_valid(main.hud.defense_buttons[index]))
	var catalog := main.hud.get_node("Catalog") as Control
	assert_false(catalog.get_global_rect().intersects(main.altitude_profile.get_global_rect()))
	assert_gte(catalog.position.y, main.altitude_profile.position.y + main.altitude_profile.size.y + 20.0)
	assert_gte(catalog.size.y, 480.0)
	var defense_scroll := main.hud.get_node("Catalog/VBox/DefenseScroll") as ScrollContainer
	assert_gte(defense_scroll.size.y, 360.0)
	assert_eq(catalog.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(catalog.mouse_force_pass_scroll_events)
	assert_true(defense_scroll.mouse_force_pass_scroll_events)
	main.hud.set_catalog_expanded(false)
	assert_false(defense_scroll.visible)
	assert_false(main.hud.start_button.visible)
	assert_eq(catalog.anchor_top, 1.0)
	assert_eq(catalog.offset_top, -66.0)
	main.hud.set_catalog_expanded(true)
	assert_true(defense_scroll.visible)
	defense_scroll.scroll_vertical = int(defense_scroll.get_v_scroll_bar().max_value)
	var initial_zoom := main.camera_rig.zoom_distance
	var wheel_at_bottom := InputEventMouseButton.new()
	wheel_at_bottom.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_at_bottom.pressed = true
	wheel_at_bottom.position = defense_scroll.get_global_rect().get_center()
	wheel_at_bottom.global_position = wheel_at_bottom.position
	assert_true(main.camera_rig.wheel_input_exclusions.has(catalog))
	main.camera_rig._unhandled_input(wheel_at_bottom)
	assert_eq(main.camera_rig.zoom_distance, initial_zoom)

func test_selected_track_exposes_public_tactical_relations_and_focus() -> void:
	main.registry.clear()
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var radar_result: Dictionary = main.session.request_placement(radar_definition, _find_valid_position_for(radar_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := radar_result.unit as SearchRadar
	var threat := main.director.spawn_one()
	threat.global_position = radar.global_position + Vector3(180.0, 70.0, 0.0)
	radar.gameplay_tick(0.8)
	var track: PlayerTrack = main.player_knowledge.call("get_active_tracks")[0]
	assert_true(main.engagement_coordinator.try_reserve(track.track_id, radar.runtime_id, 2.0))
	main._on_asset_selected(radar)
	assert_false(main.hud.selected_track_label.visible)
	var marker_screen_position := main.camera_rig.camera.unproject_position(track.estimated_position + Vector3.UP * 12.0)
	main._on_world_selected(Vector3(900.0, 0.0, 900.0), marker_screen_position)
	main.track_display._process(0.0)
	var marker := main.track_display.markers[track.track_id] as TrackMarker
	assert_true(marker.selected)
	assert_false(marker.icon.text.contains("T-"))
	assert_not_null(main.track_display.selection_lines.mesh)
	assert_eq(main.track_display.selection_details(), {"sensor_count": 1, "engagement_count": 1})
	assert_true(main.hud.selected_asset_panel.visible)
	assert_string_contains(main.hud.selected_track_label.text, "무인기")
	assert_string_contains(main.hud.selected_track_label.text, "센서 1 · 교전 자산 1")
	var stable_panel_width := main.hud.selected_asset_panel.size.x
	track.classification_confidence = 0.09
	main.hud.set_selected_track(track, false, 1, 1)
	assert_eq(main.hud.selected_asset_panel.size.x, stable_panel_width)
	assert_eq(int(main.tactical_screen_overlay.get("selected_track_id")), track.track_id)
	main._on_focus_requested()
	assert_almost_eq(main.camera_rig.global_position.x, track.estimated_position.x, 0.01)
	assert_almost_eq(main.camera_rig.global_position.z, track.estimated_position.z, 0.01)
	main._on_world_selected(Vector3(900.0, 0.0, 900.0), Vector2(4.0, 4.0))
	assert_null(main.selected_track)
	assert_null(main.selected_asset)
	assert_false(main.hud.selected_asset_panel.visible)

func test_reconnaissance_threat_orbits_while_applying_its_effect() -> void:
	main.registry.clear()
	var threat := main.director._spawn_entry(main.scenario.threat_entries[7], 0.0, 0.0) as AttackUav
	var mission_target := threat.mission_runtime.navigation_target()
	var expected_orbit_radius := (threat.definition as AttackUavDefinition).mission.action_distance * 0.82
	threat.global_position = mission_target + Vector3(expected_orbit_radius, 115.0, 0.0)
	threat.mission_runtime.phase = ThreatMissionRuntime.Phase.ACTING
	var starting_position := threat.global_position
	var minimum_agl := INF
	var minimum_city_distance := INF
	for frame: int in 80:
		threat.gameplay_tick(0.1)
		minimum_agl = minf(minimum_agl, threat.global_position.y - main.battlefield.terrain_height(threat.global_position.x, threat.global_position.z))
		minimum_city_distance = minf(minimum_city_distance, Vector2(threat.global_position.x - main.objective.global_position.x, threat.global_position.z - main.objective.global_position.z).length())
	assert_gt(threat.global_position.distance_to(starting_position), 0.1)
	assert_eq(threat.mission_runtime.phase, ThreatMissionRuntime.Phase.ACTING)
	assert_gt(minimum_agl, 100.0)
	assert_gt(minimum_city_distance, main.objective.exclusion_radius)

func test_tactical_overlay_cycles_one_public_information_layer_at_a_time() -> void:
	var radar_definition := main.scenario.available_defenses[1]
	var weapon_definition := main.scenario.available_defenses[0]
	var support_definition := main.scenario.available_defenses[5]
	var radar_result: Dictionary = main.session.request_placement(radar_definition, _find_valid_position_for(radar_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(radar_result.success)
	assert_true(main.session.request_placement(weapon_definition, _find_valid_position_for(weapon_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent).success)
	assert_true(main.session.request_placement(support_definition, _find_valid_position_for(support_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent).success)
	main.hud._on_c2_overlay_pressed()
	assert_eq(main.tactical_range_overlay.get("mode"), &"sensor")
	assert_not_null((main.tactical_range_overlay.get("line_mesh") as MeshInstance3D).mesh)
	main.hud._on_c2_overlay_pressed()
	assert_eq(main.tactical_range_overlay.get("mode"), &"weapon")
	assert_not_null((main.tactical_range_overlay.get("line_mesh") as MeshInstance3D).mesh)
	main.hud._on_c2_overlay_pressed()
	assert_eq(main.tactical_range_overlay.get("mode"), &"support")
	assert_not_null((main.tactical_range_overlay.get("line_mesh") as MeshInstance3D).mesh)
	var jammer_definition := main.scenario.threat_entries[7].threat_definition
	var jammer := jammer_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(jammer)
	jammer.setup(800, jammer_definition)
	jammer.global_position = (radar_result.unit as DefenseUnit).global_position + Vector3(30.0, 70.0, 0.0)
	main.registry.add(jammer)
	main.hud._on_c2_overlay_pressed()
	assert_eq(main.tactical_range_overlay.get("mode"), &"electronic")
	assert_not_null((main.tactical_range_overlay.get("line_mesh") as MeshInstance3D).mesh)
	main.hud._on_c2_overlay_pressed()
	assert_eq(main.tactical_range_overlay.get("mode"), &"none")
	assert_true(main.c2_overlay.show_all_links)
	main.hud._on_c2_overlay_pressed()
	assert_false(main.c2_overlay.show_all_links)
	assert_eq(main.hud.overlay_button.text, "범위 없음")

func test_physical_decoy_creates_plausible_tracks_without_matching_objects() -> void:
	main.registry.clear()
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var radar_result: Dictionary = main.session.request_placement(radar_definition, _find_valid_position_for(radar_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := radar_result.unit as SearchRadar
	var decoy_entry: ThreatSpawnEntry = main.scenario.threat_entries[6]
	main.scenario.threat_entries = [decoy_entry]
	main.director.pressure_level = 2
	var decoy := main.director.spawn_one()
	decoy.global_position = radar.global_position + Vector3(0.0, 80.0, 180.0)
	radar.gameplay_tick(0.8)
	var tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	assert_eq(main.registry.hostile_count(), 1)
	assert_eq(tracks.size(), 3)
	for track: PlayerTrack in tracks:
		assert_eq(track.classification, &"uav")
		assert_eq(track.affiliation, PlayerTrack.Affiliation.HOSTILE)
	var unmatched_tracks := 0
	for track: PlayerTrack in tracks:
		if track.estimated_position.distance_to(decoy.global_position) > 90.0:
			unmatched_tracks += 1
	assert_eq(unmatched_tracks, 2)

func test_electronic_warfare_uav_reduces_radar_quality() -> void:
	main.registry.clear()
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var radar_result: Dictionary = main.session.request_placement(radar_definition, _find_valid_position_for(radar_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := radar_result.unit as SearchRadar
	var baseline_quality := radar.signal_quality_for(200.0)
	var jammer_definition := main.scenario.threat_entries[7].threat_definition
	var jammer := jammer_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(jammer)
	jammer.setup(400, jammer_definition)
	jammer.global_position = radar.global_position + Vector3(80.0, 70.0, 0.0)
	main.registry.add(jammer)
	assert_lt(radar.signal_quality_for(200.0), baseline_quality * 0.6)

func test_radar_emission_enables_anti_radiation_targeting_and_sead_package() -> void:
	var radar_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[1], _find_valid_position_for(main.scenario.available_defenses[1].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := radar_result.unit as SearchRadar
	var anti_radiation_entry: ThreatSpawnEntry = main.scenario.threat_entries[8]
	assert_eq(main.director.adaptive_entry_weight(anti_radiation_entry), 0.0)
	main.enemy_knowledge.record_emission(radar)
	assert_gt(main.director.adaptive_entry_weight(anti_radiation_entry), anti_radiation_entry.selection_weight)
	assert_same(main.director._known_target_for_role(&"sensor"), radar)
	main.director.pending_waves.clear()
	main.director.schedule_archetype(main.scenario.raid_archetypes[1], 0.75)
	assert_eq(main.director.pending_waves.size(), 4)
	assert_eq(main.director.pending_waves[0].definition_id, "decoy_uav")
	assert_eq(main.director.pending_waves[1].definition_id, "electronic_warfare_uav")
	assert_eq(main.director.pending_waves[2].definition_id, "anti_radiation_missile")
	assert_eq(main.director.pending_waves[3].definition_id, "attack_uav")

func test_purchase_start_intercept_and_reward_flow() -> void:
	main.registry.clear()
	var placement_position := _find_valid_position()
	var result: Dictionary = main.session.request_placement(main.scenario.available_defenses[0], placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	assert_true(main.session.start_defense())
	main.session.set_simulation_speed(0.0)
	var threat: ThreatUnit = main.director.spawn_one()
	threat.global_position = placement_position + Vector3(0.0, 70.0, 130.0)
	var battery := result.unit as MissileBattery
	var launcher := battery.get_node("Turret/Elevation/Launcher") as MeshInstance3D
	assert_gt(battery.elevation.rotation.x, 0.0)
	assert_same(battery.launch_point.get_parent(), launcher)
	assert_lt(battery.launch_point.position.z, 0.0)
	for frame: int in 100:
		battery.gameplay_tick(0.02)
	assert_gt(battery.elevation.rotation.x, 0.0)
	assert_false(threat.resolved_state, "레이더 항적 없이 실제 위협을 직접 교전하면 안 됩니다")
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var radar_result: Dictionary = main.session.request_placement(radar_definition, _find_valid_position_for(radar_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(radar_result.success)
	var radar := radar_result.unit as DefenseUnit
	radar.gameplay_tick(0.4)
	var known_tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	main.placement.pick_asset_at(battery.global_position)
	main._on_world_selected(known_tracks[0].estimated_position)
	main.hud.priority_target_requested.emit()
	assert_eq(battery.doctrine.priority_track_id, known_tracks[0].track_id)
	main.hud.hold_fire_requested.emit(true)
	assert_true(battery.doctrine.hold_fire)
	main.hud.hold_fire_requested.emit(false)
	for frame: int in 100:
		battery.gameplay_tick(0.02)
	assert_false(threat.resolved_state, "지휘통제 경로 없이 센서 항적을 공유받으면 안 됩니다")
	var command_definition: DefenseDefinition = main.scenario.available_defenses[2]
	var command_result: Dictionary = main.session.request_placement(command_definition, _find_valid_position_for(command_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(command_result.success)
	assert_same(main.placement.pick_asset_at(battery.global_position), battery)
	assert_string_contains(main.hud.selected_asset_label.text, "탄약")
	assert_gt(int(main.c2_overlay.get("visible_link_count")), 0)
	for frame: int in 300:
		main.player_knowledge.call("gameplay_tick", 0.02)
		radar.gameplay_tick(0.02)
		battery.gameplay_tick(0.02)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	var falling_wreck := main.effects_parent.get_node_or_null("FallingWreck")
	var explosion := main.effects_parent.get_node_or_null("Explosion")
	assert_not_null(falling_wreck)
	assert_not_null(explosion)
	assert_true((explosion.get_node("Smoke") as GPUParticles3D).emitting)
	assert_true((explosion.get_node("Sparks") as GPUParticles3D).emitting)
	assert_gt((explosion.get_node("BlastLight") as OmniLight3D).omni_range, 30.0)
	assert_not_null(explosion.get_node("Shockwave"))
	assert_eq(int(main.combat_audio.call("played_count", &"launch")), 0)
	assert_eq(int(main.combat_audio.call("played_count", &"explosion")), 0)
	assert_eq(main.session.neutralized_count, 1)
	assert_eq(main.session.neutralized_by_type.get(String(threat.definition.id), 0), 1)
	assert_eq(main.session.neutralized_reward_total, threat.definition.neutralization_reward)
	assert_eq(main.session.defense_spending, main.scenario.available_defenses[0].price + radar_definition.price + command_definition.price)
	assert_gt(main.session.weapon_fire_count, 0)
	assert_eq(main.enemy_knowledge.best_estimate_for_role(&"weapon").asset_id, battery.runtime_id)
	assert_true(main.enemy_knowledge.recent_outcomes.back().neutralized)
	var expected_budget := main.scenario.starting_budget - main.scenario.available_defenses[0].price - radar_definition.price - command_definition.price + threat.definition.neutralization_reward
	assert_eq(main.session.budget, expected_budget)
	assert_false(threat.receive_damage(100.0))
	assert_eq(main.session.neutralized_count, 1)
	assert_eq(main.session.budget, expected_budget)

func test_uav_mission_applies_damage_once_and_game_over_stops_combat() -> void:
	main.session.defense_count = 1
	assert_true(main.session.start_defense())
	main.session.set_simulation_speed(0.0)
	for index: int in 10:
		var threat: ThreatUnit = main.director.spawn_one()
		var target: Vector3 = main.objective.global_position
		threat.global_position = target + Vector3(0.0, 2.0, 1.0)
		threat.configure_mission(main.objective, main.battlefield, target, 1.0)
		threat.gameplay_tick(0.1)
		threat.gameplay_tick(0.1)
	assert_eq(main.objective.current_integrity, 0)
	assert_eq(main.session.phase, GameSession.Phase.GAME_OVER)
	assert_false(main.director.enabled)
	assert_eq(main.registry.hostile_count(), 0)
	assert_string_contains(main.hud.final_stats.text, "방어 구간")
	assert_string_contains(main.hud.final_stats.text, "도시 피해")
	assert_string_contains(main.hud.final_combat_stats.text, "무력화")
	assert_string_contains(main.hud.final_network_stats.text, "가동 자산")
	assert_lt(main.hud.final_stats.text.length(), 100)

func test_swarm_entry_spawns_a_close_formation_package() -> void:
	main.registry.clear()
	main.scenario.threat_entries = [main.scenario.threat_entries[1]]
	main.director.elapsed = 120.0
	main.director.pressure_level = 2
	main.director.enabled = true
	main.director.until_spawn = 0.0
	main.director.gameplay_tick(0.1)
	assert_eq(main.director.pending_waves.size(), 1)
	main.director.gameplay_tick(2.1)
	assert_eq(main.registry.hostile_count(), 4)
	var shared_target: Vector3
	var has_target := false
	for threat: ThreatUnit in main.registry.get_active():
		assert_eq(threat.definition.id, &"swarm_uav")
		var attack_uav := threat as AttackUav
		if not has_target:
			shared_target = attack_uav.target_point
			has_target = true
		else:
			assert_eq(attack_uav.target_point, shared_target)

func test_mission_roles_choose_matching_deployed_assets() -> void:
	var radar_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[1], _find_valid_position_for(main.scenario.available_defenses[1].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var command_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[2], _find_valid_position_for(main.scenario.available_defenses[2].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var support_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[5], _find_valid_position_for(main.scenario.available_defenses[5].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(radar_result.success)
	assert_true(command_result.success)
	assert_true(support_result.success)
	var recon := main.scenario.threat_entries[2].threat_definition as AttackUavDefinition
	var support_strike := main.scenario.threat_entries[3].threat_definition as AttackUavDefinition
	var command_strike := main.scenario.threat_entries[4].threat_definition as AttackUavDefinition
	assert_same(main.director.choose_target_for(recon.mission), radar_result.unit)
	assert_same(main.director.choose_target_for(support_strike.mission), support_result.unit)
	assert_same(main.director.choose_target_for(command_strike.mission), command_result.unit)

func test_recon_mission_upgrades_enemy_sensor_estimate() -> void:
	var radar_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[1], _find_valid_position_for(main.scenario.available_defenses[1].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := radar_result.unit as SearchRadar
	var recon_definition := main.scenario.threat_entries[2].threat_definition as AttackUavDefinition
	main.scenario.threat_entries = [main.scenario.threat_entries[2]]
	main.director.pressure_level = 2
	var recon := main.director.spawn_one() as AttackUav
	assert_same(recon.mission_runtime.target_asset, radar)
	recon.global_position = radar.global_position + Vector3(10.0, 2.0, 0.0)
	recon.mover.setup(recon_definition.movement, main.battlefield, recon.global_position.direction_to(radar.global_position))
	for frame: int in 90:
		recon.gameplay_tick(0.1)
		if recon.mission_runtime.phase == ThreatMissionRuntime.Phase.EGRESS:
			break
	var estimate := main.enemy_knowledge.best_estimate_for_role(&"sensor")
	assert_false(estimate.is_empty())
	if estimate.is_empty():
		return
	assert_eq(estimate.asset_id, radar.runtime_id)
	assert_eq(estimate.source, "reconnaissance")
	assert_eq(recon.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)

func test_facility_strike_releases_weapon_then_egresses() -> void:
	var support_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[5], _find_valid_position_for(main.scenario.available_defenses[5].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(support_result.success)
	var support := support_result.unit as SupportFacility
	main.scenario.threat_entries = [main.scenario.threat_entries[3]]
	main.director.pressure_level = 3
	var threat := main.director.spawn_one() as AttackUav
	assert_not_null(threat)
	assert_same(threat.mission_runtime.target_asset, support)
	threat.global_position = support.global_position + Vector3(20.0, 2.0, 0.0)
	threat.gameplay_tick(0.1)
	assert_eq(support.integrity, 65.0)
	assert_eq(threat.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_false(threat.resolved_state)
	threat.gameplay_tick(0.1)
	assert_eq(support.integrity, 65.0, "투발 피해는 한 번만 적용됩니다")

func test_cruise_missile_spawns_low_and_follows_terrain() -> void:
	var entry := main.scenario.threat_entries[5]
	var definition := entry.threat_definition as AttackUavDefinition
	assert_eq(definition.movement.mode, ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING)
	var threat := main.director._spawn_entry(entry, 0.4, 0.0) as AttackUav
	assert_not_null(threat)
	var initial_agl := threat.global_position.y - main.battlefield.flight_surface_height(threat.global_position.x, threat.global_position.z)
	assert_almost_eq(initial_agl, definition.movement.cruise_altitude, 0.001)
	for frame: int in 30:
		threat.gameplay_tick(0.1)
	var agl := threat.global_position.y - main.battlefield.flight_surface_height(threat.global_position.x, threat.global_position.z)
	assert_gt(agl, 5.0)
	assert_lt(agl, 45.0)
	assert_eq(threat.get_sensor_signature().classification_hint, &"cruise_missile")
	var exhaust := threat.get_node("Body/ExhaustTrail") as GPUParticles3D
	assert_true(exhaust.emitting)
	assert_gt(int(exhaust.get("emitted_sample_count")), 20)
	assert_gte(exhaust.lifetime, 9.0)
	assert_gte(exhaust.amount, 700)
	assert_lt((exhaust.process_material as ParticleProcessMaterial).gravity.length(), 0.3)
	assert_lte((exhaust.process_material as ParticleProcessMaterial).initial_velocity_max, 0.8)
	assert_true((exhaust.process_material as ParticleProcessMaterial).turbulence_enabled)
	assert_eq((exhaust.process_material as ParticleProcessMaterial).lifetime_randomness, 0.0)
	assert_not_null((exhaust.process_material as ParticleProcessMaterial).color_ramp)
	assert_gte((threat.get_node("Body/EngineLight") as OmniLight3D).light_energy, 8.0)
	var integrity_before := main.objective.current_integrity
	var impact_target := threat.mission_runtime.fixed_target
	for frame: int in 500:
		threat.gameplay_tick(0.05)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_eq(main.objective.current_integrity, integrity_before - roundi(definition.mission.damage))
	var explosion := main.effects_parent.get_node_or_null("Explosion") as ExplosionEffect
	assert_not_null(explosion)
	assert_gt(explosion.global_position.distance_to(impact_target), 0.01)
	assert_false(main.objective.damage_smoke_effects.is_empty())
	assert_almost_eq(main.objective.damage_smoke_effects.back().global_position, explosion.global_position, Vector3.ONE * 0.001)

func test_cruise_missile_commits_to_terminal_impact_without_climbing_out() -> void:
	var entry := main.scenario.threat_entries[5]
	var definition := entry.threat_definition as AttackUavDefinition
	var threat := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	var target := threat.mission_runtime.fixed_target
	threat.global_position = target + Vector3(definition.movement.terminal_distance * 0.8, definition.movement.cruise_altitude, 0.0)
	threat.mover.velocity = Vector3(0.0, 0.0, definition.movement.speed)
	var maximum_height := threat.global_position.y
	for frame: int in 80:
		threat.gameplay_tick(0.25)
		maximum_height = maxf(maximum_height, threat.global_position.y)
		if threat.resolved_state:
			break
	assert_true(threat.terminal_committed)
	assert_true(threat.resolved_state)
	assert_lte(maximum_height, target.y + definition.movement.cruise_altitude + 1.0)
	assert_false(main.objective.damage_smoke_effects.is_empty())
	assert_almost_eq(main.objective.damage_smoke_effects.back().global_position, threat.global_position, Vector3.ONE * 0.001)

func test_threats_spawn_over_the_ocean_and_ballistic_missiles_launch_much_farther_away() -> void:
	var cruise_entry := main.scenario.threat_entries[5]
	var ballistic_entry := main.scenario.threat_entries[9]
	var cruise := main.director._spawn_entry(cruise_entry, 0.0, 0.0) as AttackUav
	var ballistic := main.director._spawn_entry(ballistic_entry, 0.0, 0.0) as AttackUav
	assert_not_null(cruise)
	assert_not_null(ballistic)
	var cruise_radius := Vector2(cruise.global_position.x, cruise.global_position.z).length()
	var ballistic_radius := Vector2(ballistic.global_position.x, ballistic.global_position.z).length()
	assert_gt(cruise_radius, main.scenario.battlefield_size * 0.6)
	assert_gt(ballistic_radius, main.scenario.battlefield_size)
	assert_gt(ballistic_radius, cruise_radius * 2.0)
	assert_gte(cruise.global_position.y, main.battlefield.generator.sea_level + (cruise_entry.threat_definition as AttackUavDefinition).movement.cruise_altitude)

func test_strike_aircraft_visibly_releases_a_powered_munition() -> void:
	var definition := main.scenario.threat_entries[11].threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	var target := main.objective.global_position
	threat.global_position = target + Vector3(0.0, definition.movement.terminal_altitude, 80.0)
	threat.setup(811, definition)
	threat.configure_mission(main.objective, main.battlefield, target, 1.0, null, threat.global_position + Vector3(600.0, 0.0, 0.0))
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var integrity_before := main.objective.current_integrity
	threat.gameplay_tick(0.1)
	assert_true(threat.mission_runtime.effect_applied)
	assert_eq(threat.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_eq(main.objective.current_integrity, integrity_before, "도시 피해는 투하가 아니라 실제 탄착 때 적용됩니다")
	var munition := main.threat_parent.get_node_or_null("StrikeMunition") as Node3D
	assert_not_null(munition)
	assert_gte((munition.get_node("FlameLight") as OmniLight3D).light_energy, 9.0)
	assert_eq(threat.get_node("Body").find_children("*ExhaustTrail", "GPUParticles3D").size(), 2)
	assert_gte((threat.get_node("Body/LeftEngineLight") as OmniLight3D).light_energy, 9.0)
	munition.call("_process", 1.0)
	assert_eq(main.objective.current_integrity, integrity_before - roundi(definition.mission.damage))
	assert_false(main.objective.damage_smoke_effects.is_empty())
	assert_almost_eq(main.objective.damage_smoke_effects.back().global_position, target, Vector3.ONE * 0.001)

func test_strike_aircraft_releases_above_the_city_and_climbs_out_over_the_sea() -> void:
	var definition := main.scenario.threat_entries[11].threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	var target := main.objective.global_position
	var exit_point := Vector3(main.scenario.battlefield_size, main.battlefield.generator.sea_level + definition.movement.cruise_altitude, 0.0)
	threat.global_position = target + Vector3(-90.0, definition.movement.terminal_altitude, 0.0)
	threat.setup(812, definition)
	threat.configure_mission(main.objective, main.battlefield, target, 1.0, null, exit_point)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var explosion_count := main.effects_parent.find_children("Explosion", "ExplosionEffect").size()
	threat.gameplay_tick(0.1)
	assert_true(threat.mission_runtime.effect_applied)
	assert_eq(threat.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_gt(threat.global_position.y, main.battlefield.generator.sea_level + 90.0)
	var minimum_egress_altitude := threat.global_position.y
	for frame: int in 320:
		threat.gameplay_tick(0.1)
		minimum_egress_altitude = minf(minimum_egress_altitude, threat.global_position.y)
		if threat.resolved_state:
			break
	assert_gte(minimum_egress_altitude, main.battlefield.generator.sea_level + definition.movement.terminal_altitude - 0.1)
	assert_gt(threat.global_position.y, definition.movement.terminal_altitude + 20.0)
	assert_true(threat.resolved_state)
	assert_false(main.registry.get_active().has(threat))
	assert_eq(main.effects_parent.find_children("Explosion", "ExplosionEffect").size(), explosion_count)

func test_ballistic_missile_climbs_through_arc_then_impacts_once() -> void:
	var definition := main.scenario.threat_entries[9].threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	threat.global_position = Vector3(900.0, 20.0, 0.0)
	threat.setup(720, definition)
	threat.configure_mission(main.objective, main.battlefield, main.objective.global_position, 1.0, null, threat.global_position)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var starting_integrity := main.objective.current_integrity
	var phases: Dictionary[StringName, bool] = {}
	var maximum_altitude := threat.global_position.y
	for step: int in 90:
		if threat.resolved_state:
			break
		threat.gameplay_tick(0.1)
		phases[threat.mover.ballistic_phase()] = true
		maximum_altitude = maxf(maximum_altitude, threat.global_position.y)
		if step == 7:
			assert_lt(Vector2(threat.global_position.x - 900.0, threat.global_position.z).length(), 100.0)
			assert_gt(threat.global_position.y, 500.0)
	assert_true(threat.resolved_state)
	assert_true(phases.has(&"boost"))
	assert_true(phases.has(&"midcourse"))
	assert_true(phases.has(&"reentry"))
	assert_gt(maximum_altitude, 900.0)
	assert_eq(main.objective.current_integrity, starting_integrity - roundi(definition.mission.damage))

func test_long_range_layer_intercepts_a_live_ballistic_attack_with_specialized_salvo() -> void:
	main.registry.clear()
	main._on_pressure_changed(4)
	var radar_result := _place_for(main, main.scenario.available_defenses[3])
	var command_result := _place_for(main, main.scenario.available_defenses[2])
	var battery_result := _place_for(main, main.scenario.available_defenses[7])
	assert_true(radar_result.success)
	assert_true(command_result.success)
	assert_true(battery_result.success)
	var battery := battery_result.unit as MissileBattery
	assert_true(main.session.start_defense())
	main.director.enabled = false
	var approach_angle := atan2(battery.global_position.z, battery.global_position.x)
	var ballistic := main.director._spawn_entry(main.scenario.threat_entries[9], approach_angle, 0.0) as AttackUav
	for frame: int in 280:
		main._process(0.1)
		if ballistic.resolved_state:
			break
	assert_true(ballistic.resolved_state)
	assert_eq(int(main.session.neutralized_by_type.get("ballistic_missile", 0)), 1)
	assert_lt(battery.magazines[&"high_speed_interceptor"].rounds, 3)
	assert_gte(main.session.weapon_fire_count, 2)

func test_raid_archetype_sequences_recon_saturation_and_facility_strike() -> void:
	main.registry.clear()
	var archetype := main.scenario.raid_archetypes[0]
	main.director.schedule_archetype(archetype, 0.75)
	assert_eq(main.director.pending_waves.size(), 3)
	main.director._tick_pending_waves(0.1)
	assert_eq(_active_definition_count(&"recon_uav"), 1)
	main.director._tick_pending_waves(3.9)
	assert_eq(_active_definition_count(&"swarm_uav"), 4)
	main.director._tick_pending_waves(4.0)
	assert_eq(_active_definition_count(&"support_strike_uav"), 1)
	assert_eq(main.director.pending_waves.size(), 0)

func test_raid_planning_uses_budget_knowledge_outcomes_and_coverage_gap() -> void:
	var radar_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[1], _find_valid_position_for(main.scenario.available_defenses[1].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var support_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[5], _find_valid_position_for(main.scenario.available_defenses[5].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar := radar_result.unit as SearchRadar
	var support := support_result.unit as SupportFacility
	var support_entry := main.scenario.threat_entries[3]
	var swarm_entry := main.scenario.threat_entries[1]
	var base_support_weight := main.director.adaptive_entry_weight(support_entry)
	main.enemy_knowledge.record_recon(support)
	assert_gt(main.director.adaptive_entry_weight(support_entry), base_support_weight * 2.0)
	var base_budget := main.director.threat_budget_at(90.0)
	for index: int in 8:
		main.enemy_knowledge.record_outcome(true, Vector3.ZERO, &"attack_uav")
	assert_gt(main.director.adaptive_entry_weight(swarm_entry), swarm_entry.selection_weight)
	assert_gt(main.director.threat_budget_at(90.0), base_budget)
	main.enemy_knowledge.estimates.clear()
	main.enemy_knowledge.record_recon(radar)
	var radar_angle := fposmod(atan2(radar.global_position.z - main.objective.global_position.z, radar.global_position.x - main.objective.global_position.x), TAU)
	assert_almost_eq(main.director.adaptive_approach_angle(), fposmod(radar_angle + PI, TAU), 0.2)
	main.director.elapsed = 90.0
	main.director.pressure_level = 3
	main.director.pending_waves.clear()
	main.director.launch_budgeted_raid()
	var planned_cost := 0.0
	for wave: Dictionary in main.director.pending_waves:
		for entry: ThreatSpawnEntry in main.scenario.threat_entries:
			if String(entry.threat_definition.id) == String(wave.definition_id):
				planned_cost += entry.threat_cost * float(entry.group_size)
	assert_lte(planned_cost, main.director.threat_budget_at(main.director.elapsed) + 0.001)
	assert_gt(planned_cost, 0.0)

func test_close_in_gun_restores_and_cheaply_finishes_small_uav_engagement() -> void:
	main.registry.clear()
	var gun_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[4], _find_valid_position_for(main.scenario.available_defenses[4].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[1], _find_valid_position_for(main.scenario.available_defenses[1].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var command_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[2], _find_valid_position_for(main.scenario.available_defenses[2].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(gun_result.success)
	assert_true(radar_result.success)
	assert_true(command_result.success)
	var gun := gun_result.unit as CloseInGun
	var radar := radar_result.unit as SearchRadar
	var gun_runtime_id := gun.runtime_id
	assert_true(main.session.start_defense())
	main.director.enabled = false
	var swarm_definition: ThreatDefinition = main.scenario.threat_entries[1].threat_definition
	var threat := swarm_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(threat)
	threat.global_position = gun.global_position + Vector3(120.0, 48.0, 0.0)
	threat.setup(88, swarm_definition)
	threat.configure_mission(main.objective, main.battlefield, main.objective.global_position, 1.0)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var observation := SensorObservation.new()
	observation.setup(radar.runtime_id, 0.0, threat.global_position, 0.98, 2.0, 1.0, &"small_uav", ThreatDefinition.Affiliation.HOSTILE, 5.0)
	var track: PlayerTrack = main.player_knowledge.call("submit_observation", observation)
	assert_gt(gun.weapon_match(track), 0.9)
	var starting_turret_yaw := gun.turret.rotation.y
	gun.gameplay_tick(0.01)
	assert_false(main.engagement_coordinator.has_reservation(track.track_id), "포탑은 정렬되기 전에 발사하면 안 됩니다")
	assert_ne(gun.turret.rotation.y, starting_turret_yaw)
	assert_gt(gun.elevation.rotation.x, 0.0)
	for frame: int in 100:
		gun.gameplay_tick(0.02)
		if main.engagement_coordinator.has_reservation(track.track_id):
			break
	assert_true(main.engagement_coordinator.has_reservation(track.track_id))
	var tracer := main.projectile_parent.get_child(0) as TracerBurst
	assert_gte(tracer.tracers.size(), 48)
	assert_eq(tracer.tracer_glows.size(), tracer.tracers.size())
	assert_lte(tracer.tracer_spacing, 4.0)
	assert_gte(tracer.target_spread_radius, 5.0)
	assert_gt(tracer.target_spread_radius, tracer.muzzle_spread_radius * 12.0)
	assert_lt((tracer.beam.mesh as BoxMesh).size.z, threat.global_position.distance_to(gun.global_position) * 0.1)
	var tracer_material := (tracer.beam.mesh as BoxMesh).material as StandardMaterial3D
	assert_gte(tracer_material.emission_energy_multiplier, 16.0)
	assert_gt((tracer.glow_beam.mesh as BoxMesh).size.x, (tracer.beam.mesh as BoxMesh).size.x * 2.0)
	var saved_rounds := gun.magazine.rounds
	var saved_cooldown := gun.cooldown
	var saved_rng_state := gun.rng.state
	var saved_health := threat.health
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored_gun := _find_defense(gun_runtime_id) as CloseInGun
	var restored_threat := _find_contact(88)
	assert_not_null(restored_gun)
	assert_not_null(restored_threat)
	assert_eq(restored_gun.cooldown, saved_cooldown)
	assert_eq(restored_gun.rng.state, saved_rng_state)
	assert_eq(restored_gun.magazine.rounds, saved_rounds)
	assert_eq(restored_threat.health, saved_health)
	assert_true(main.engagement_coordinator.has_reservation(track.track_id))
	assert_eq(main.projectile_parent.get_child_count(), 0, "일시적인 예광탄 VFX는 저장 대상이 아닙니다")
	var budget_before_kill := main.session.budget
	for frame: int in 80:
		main.engagement_coordinator.gameplay_tick(0.1)
		restored_gun.gameplay_tick(0.1)
		if restored_threat.resolved_state:
			break
	assert_true(restored_threat.resolved_state)
	assert_eq(main.session.neutralized_count, 1)
	assert_eq(main.session.budget, budget_before_kill + swarm_definition.neutralization_reward)

func test_selected_weapon_requests_resupply_from_limited_support_capacity() -> void:
	var gun_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[4], _find_valid_position_for(main.scenario.available_defenses[4].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var support_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[5], _find_valid_position_for(main.scenario.available_defenses[5].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(gun_result.success)
	assert_true(support_result.success)
	var gun := gun_result.unit as CloseInGun
	gun.magazine.reserve = 0
	main.placement.pick_asset_at(gun.global_position)
	assert_false(main.hud.resupply_button.disabled)
	main.hud.resupply_button.pressed.emit()
	assert_eq(main.hud.feedback_label.text, "재보급 작업을 요청했습니다")
	assert_eq(main.support_manager.task_status(gun), "재보급 진행")
	main.support_manager.gameplay_tick(2.9)
	assert_eq(gun.magazine.reserve, 0)
	main.support_manager.gameplay_tick(0.2)
	assert_eq(gun.magazine.reserve, gun.magazine.reserve_capacity)
	assert_eq(main.support_manager.task_status(gun), "")
	assert_true(main.hud.relocation_button.visible)
	assert_false(main.hud.relocation_button.disabled)
	main.hud.relocation_button.pressed.emit()
	assert_same(main.placement.relocating_unit, gun)
	main.placement.cancel()

func test_support_power_capacity_recharges_laser_and_scales_with_damage() -> void:
	main._on_pressure_changed(3)
	var support_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[5], _find_valid_position_for(main.scenario.available_defenses[5].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var laser_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[6], _find_valid_position_for(main.scenario.available_defenses[6].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(support_result.success)
	assert_true(laser_result.success)
	var support := support_result.unit as SupportFacility
	var laser := laser_result.unit as HighEnergyLaser
	laser.energy_state.energy = 0.0
	main.power_manager.begin_tick()
	laser.gameplay_tick(1.0)
	assert_almost_eq(laser.energy_state.energy, 10.0, 0.0001)
	assert_true(support.receive_damage(50.0))
	assert_almost_eq(main.power_manager.generation_capacity(), 10.0, 0.0001)
	laser.energy_state.energy = 0.0
	main.power_manager.begin_tick()
	laser.gameplay_tick(1.0)
	assert_almost_eq(laser.energy_state.energy, 10.0 * 10.0 / 12.0, 0.0001)
	assert_false(laser.uses_ammunition())

func test_laser_uses_energy_and_heat_to_destroy_small_uav() -> void:
	main.registry.clear()
	main._on_pressure_changed(3)
	var laser_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[6], _find_valid_position_for(main.scenario.available_defenses[6].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var support_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[5], _find_valid_position_for(main.scenario.available_defenses[5].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var radar_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[1], _find_valid_position_for(main.scenario.available_defenses[1].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var command_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[2], _find_valid_position_for(main.scenario.available_defenses[2].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(laser_result.success)
	assert_true(support_result.success)
	assert_true(radar_result.success)
	assert_true(command_result.success)
	var laser := laser_result.unit as HighEnergyLaser
	var radar := radar_result.unit as SearchRadar
	var swarm_definition: ThreatDefinition = main.scenario.threat_entries[1].threat_definition
	var threat := swarm_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(threat)
	threat.global_position = laser.global_position + Vector3(140.0, 48.0, 0.0)
	threat.setup(91, swarm_definition)
	threat.configure_mission(main.objective, main.battlefield, main.objective.global_position, 1.0)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var observation := SensorObservation.new()
	observation.setup(radar.runtime_id, 0.0, threat.global_position, 0.98, 2.0, 1.0, &"small_uav", ThreatDefinition.Affiliation.HOSTILE, 5.0)
	main.player_knowledge.call("submit_observation", observation)
	var starting_energy := laser.energy_state.energy
	laser.gameplay_tick(0.01)
	assert_ne(laser.turret.rotation.y, 0.0)
	assert_gt(laser.elevation.rotation.x, 0.0)
	assert_eq(laser.energy_state.energy, starting_energy)
	for frame: int in 80:
		main.power_manager.begin_tick()
		main.engagement_coordinator.gameplay_tick(0.1)
		laser.gameplay_tick(0.1)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_lt(laser.energy_state.energy, starting_energy)
	assert_gt(laser.energy_state.heat, 0.0)
	var pulse := main.projectile_parent.get_node_or_null("LaserPulse") as LaserPulse
	assert_not_null(pulse)
	assert_true((main.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled)
	assert_true((pulse.get_node("Beam") as MeshInstance3D).mesh is CylinderMesh)
	assert_gt(((pulse.get_node("GlowBeam") as MeshInstance3D).mesh as CylinderMesh).top_radius, ((pulse.get_node("Beam") as MeshInstance3D).mesh as CylinderMesh).top_radius)
	assert_gte(((pulse.get_node("Beam") as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier, 20.0)
	assert_gt((pulse.get_node("ImpactLight") as OmniLight3D).light_energy, 0.0)

func test_expired_interceptor_leaves_visible_miss_feedback() -> void:
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.registry = main.registry
	interceptor.target_track = PlayerTrack.new()
	interceptor.target_track.state = PlayerTrack.State.LOST
	interceptor.global_position = Vector3(30.0, 80.0, -20.0)
	var search_start := interceptor.global_position
	interceptor.gameplay_tick(0.1)
	assert_false(interceptor.is_queued_for_deletion())
	assert_gt(interceptor.global_position.distance_to(search_start), 0.0)
	assert_null(main.projectile_parent.get_node_or_null("InterceptorMiss"))
	interceptor.gameplay_tick(HomingInterceptor.REACQUISITION_GRACE_DURATION)
	var miss_effect := main.projectile_parent.get_node_or_null("InterceptorMiss") as Node3D
	assert_not_null(miss_effect)
	assert_true((miss_effect.get_node("Smoke") as GPUParticles3D).emitting)
	assert_eq((miss_effect.get_node("Reason") as Label3D).text, "유도 상실")
	assert_eq(miss_effect.global_position, interceptor.global_position)
	var self_destruct := main.projectile_parent.get_node_or_null("Explosion") as ExplosionEffect
	assert_not_null(self_destruct)
	assert_eq(self_destruct.effect_radius, 7.0)
	assert_true((self_destruct.get_node("Sparks") as GPUParticles3D).emitting)
	var lingering_trail := main.projectile_parent.get_node_or_null("SmokeTrail") as GPUParticles3D
	assert_not_null(lingering_trail)
	assert_false(lingering_trail.emitting)
	assert_gte(lingering_trail.lifetime, 24.0)
	assert_gte(float(lingering_trail.get("release_fade_duration")), 16.0)
	assert_eq(lingering_trail.get_parent(), main.projectile_parent)

func test_fast_interceptor_samples_smoke_between_physics_positions() -> void:
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	var smoke := interceptor.get_node("SmokeTrail") as GPUParticles3D
	smoke.call("sample_world_segment", Vector3.ZERO, Vector3(0.0, 0.0, 26.0))
	assert_gte(int(smoke.get("emitted_sample_count")), 28)
	assert_gt((smoke.get("last_emitted_world_position") as Vector3).z, 24.0)
	assert_true(smoke.emitting)
	assert_gte(smoke.lifetime, 24.0)
	assert_gte(smoke.amount, 1900)
	assert_lt((smoke.process_material as ParticleProcessMaterial).gravity.length(), 0.3)
	assert_lte((smoke.process_material as ParticleProcessMaterial).initial_velocity_max, 0.8)
	assert_true((smoke.process_material as ParticleProcessMaterial).turbulence_enabled)
	assert_between((smoke.process_material as ParticleProcessMaterial).lifetime_randomness, 0.1, 0.3)
	var smoke_gradient := ((smoke.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D).gradient
	assert_lt(smoke_gradient.sample(0.68).a, smoke_gradient.sample(0.45).a)
	assert_eq(smoke_gradient.sample(0.88).a, 0.0)
	assert_eq(smoke_gradient.sample(0.96).a, 0.0)
	assert_gte(smoke.visibility_aabb.size.x, 292.0)
	assert_gte((interceptor.get_node("FlameLight") as OmniLight3D).light_energy, 9.0)
	interceptor.queue_free()

func test_released_smoke_trail_reaches_zero_opacity_before_cleanup() -> void:
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	var initial_alpha := smoke.smoke_material.albedo_color.a
	smoke.release_to(main.effects_parent)
	smoke._process(smoke.release_fade_duration * 0.5)
	assert_between(smoke.smoke_material.albedo_color.a, 0.0, initial_alpha)
	assert_between(smoke.current_shadow_opacity_ratio, 0.0, 1.0)
	assert_almost_eq(smoke.current_opacity_ratio, 0.5, 0.001)
	smoke._process(smoke.release_fade_duration * 0.5)
	assert_eq(smoke.smoke_material.albedo_color.a, 0.0)
	assert_eq(smoke.current_shadow_opacity_ratio, 0.0)
	assert_eq(smoke.current_opacity_ratio, 0.0)
	assert_false(smoke.is_queued_for_deletion())
	smoke._process(smoke.transparent_cleanup_delay + 0.01)
	assert_true(smoke.is_queued_for_deletion())
	interceptor.queue_free()

func test_interceptor_detonation_remains_visible_when_strike_aircraft_survives_hit() -> void:
	main.registry.clear()
	var definition := main.scenario.threat_entries[11].threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	threat.setup(9912, definition)
	threat.global_position = Vector3(80.0, 220.0, 0.0)
	main.registry.add(threat)
	var track := PlayerTrack.new()
	track.track_id = 9912
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = threat.global_position
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = threat.global_position - Vector3.RIGHT * 12.0
	var area_defense := (main.scenario.available_defenses[7] as MissileBatteryDefinition).munitions[0]
	interceptor.configure(track, main.registry, area_defense, Vector3.RIGHT, 77)
	interceptor.gameplay_tick(0.05)
	assert_false(threat.resolved_state)
	assert_eq(threat.health, definition.maximum_health - area_defense.interceptor_damage)
	assert_true(interceptor.is_queued_for_deletion())
	var detonation := main.projectile_parent.get_node_or_null("Explosion") as ExplosionEffect
	assert_not_null(detonation)
	assert_eq(detonation.effect_radius, 6.0)
	var smoke_process := (detonation.get_node("Smoke") as GPUParticles3D).process_material as ParticleProcessMaterial
	assert_eq(smoke_process.spread, 180.0)
	assert_lt(absf(smoke_process.gravity.y), 1.0)

func test_new_explosion_does_not_reactivate_a_faded_shockwave() -> void:
	var explosion_scene := preload("res://effects/explosion/explosion.tscn")
	var first := explosion_scene.instantiate() as ExplosionEffect
	main.effects_parent.add_child(first)
	first.setup(Color(1.0, 0.3, 0.04), 10.0)
	first._process(1.1)
	var first_material := first.get_node("Shockwave").get("material_override") as StandardMaterial3D
	assert_eq(first_material.albedo_color.a, 0.0)
	var second := explosion_scene.instantiate() as ExplosionEffect
	main.effects_parent.add_child(second)
	second.setup(Color(1.0, 0.5, 0.08), 8.0)
	second._process(0.1)
	var second_material := second.get_node("Shockwave").get("material_override") as StandardMaterial3D
	assert_ne(first_material as Variant, second_material as Variant)
	assert_eq(first_material.albedo_color.a, 0.0)
	assert_gt(second_material.albedo_color.a, 0.0)

func test_hpm_pulse_affects_multiple_electronic_targets_in_observed_area() -> void:
	main.registry.clear()
	main._on_pressure_changed(5)
	var hpm_result: Dictionary = main.session.request_placement(main.scenario.available_defenses[9], _find_valid_position_for(main.scenario.available_defenses[9].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(hpm_result.success)
	var hpm := hpm_result.unit as HighPowerMicrowave
	var definition: ThreatDefinition = main.scenario.threat_entries[0].threat_definition
	var center := hpm.global_position + Vector3(120.0, 60.0, 0.0)
	var threats: Array[ThreatUnit] = []
	for index: int in 3:
		var threat := definition.scene.instantiate() as ThreatUnit
		main.threat_parent.add_child(threat)
		threat.setup(500 + index, definition)
		threat.global_position = center + (Vector3(20.0, 0.0, 0.0) if index == 1 else Vector3(180.0, 0.0, 0.0) if index == 2 else Vector3.ZERO)
		main.registry.add(threat)
		threats.append(threat)
	var track := PlayerTrack.new()
	track.track_id = 99
	track.estimated_position = center
	assert_false(hpm._aim_turret(center, 0.01))
	assert_ne(hpm.turret.rotation.y, 0.0)
	assert_gt(hpm.elevation.rotation.x, 0.0)
	assert_eq(hpm._fire_pulse(track), 2)
	assert_lt(threats[0].health, 100.0)
	assert_lt(threats[1].health, 100.0)
	assert_eq(threats[2].health, 100.0)

func test_hpm_weakly_heats_bird_and_bird_falls_without_exploding_when_neutralized() -> void:
	main.registry.clear()
	main._on_pressure_changed(5)
	var hpm_definition := main.scenario.available_defenses[9] as HighPowerMicrowaveDefinition
	var hpm_result: Dictionary = main.session.request_placement(hpm_definition, _find_valid_position_for(hpm_definition.placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(hpm_result.success)
	var hpm := hpm_result.unit as HighPowerMicrowave
	var bird_definition := main.scenario.ambient_contacts[0]
	var bird := bird_definition.scene.instantiate() as BirdContact
	main.threat_parent.add_child(bird)
	bird.setup(570, bird_definition)
	bird.global_position = hpm.global_position + Vector3(100.0, 55.0, 0.0)
	bird.configure_patrol(main.battlefield, Vector3(14.0, 0.0, 3.0))
	main.registry.add(bird)
	main._on_threat_spawned(bird)
	var track := PlayerTrack.new()
	track.track_id = 570
	track.estimated_position = bird.global_position
	var health_before := bird.health
	assert_eq(hpm._fire_pulse(track), 1)
	assert_eq(bird.health, health_before - hpm_definition.electronic_damage * bird_definition.electronic_vulnerability)
	assert_gt(bird.health, 0.0, "한 번의 HPM 펄스가 조류를 전자장비처럼 즉시 무력화하면 안 됩니다")
	var explosion_count_before := main.effects_parent.get_children().filter(func(node: Node) -> bool: return node is ExplosionEffect).size()
	while not bird.resolved_state:
		bird.receive_electronic_damage(hpm_definition.electronic_damage)
	var explosion_count_after := main.effects_parent.get_children().filter(func(node: Node) -> bool: return node is ExplosionEffect).size()
	var falling_bird := main.effects_parent.get_node_or_null("FallingWreck") as FallingWreckEffect
	assert_not_null(falling_bird)
	assert_eq(explosion_count_after, explosion_count_before)
	assert_false((falling_bird.get_node("SmokeTrail") as GPUParticles3D).emitting)
	assert_false(falling_bird.get_node("ImpactFlash").visible)
	assert_eq(falling_bird.get_node("Wreck").scale, Vector3.ONE * 0.42)

func test_interceptor_drone_returns_and_recharges_for_reuse() -> void:
	main.registry.clear()
	main._on_pressure_changed(5)
	var result: Dictionary = main.session.request_placement(main.scenario.available_defenses[10], _find_valid_position_for(main.scenario.available_defenses[10].placement_profile), main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	var base := result.unit as InterceptorDroneDefense
	var definition: ThreatDefinition = main.scenario.threat_entries[0].threat_definition
	var threat := definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(threat)
	threat.setup(610, definition)
	threat.global_position = base.global_position + Vector3(80.0, 30.0, 0.0)
	main.registry.add(threat)
	var track := PlayerTrack.new()
	track.track_id = 610
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = threat.global_position
	track.estimated_velocity = Vector3(-26.0, 0.0, 18.0)
	assert_true(main.engagement_coordinator.try_reserve(track.track_id, base.runtime_id, base.drone_definition().drone_endurance))
	var drone := base._launch(track)
	assert_eq(base.available_drones, base.drone_definition().drone_count - 1)
	for frame: int in 90:
		threat.global_position += track.estimated_velocity * 0.05
		track.estimated_position = threat.global_position
		drone.gameplay_tick(0.05)
		if drone.state == InterceptorDrone.State.RETURNING:
			break
	assert_true(threat.resolved_state)
	assert_eq(drone.state, InterceptorDrone.State.RETURNING)
	assert_false(main.engagement_coordinator.has_reservation(track.track_id))
	drone.global_position = base.global_position + Vector3.UP * 6.0
	drone.gameplay_tick(0.01)
	assert_eq(base.recharge_queue.size(), 1)
	base.gameplay_tick(base.drone_definition().recharge_duration + 0.1)
	assert_eq(base.available_drones, base.drone_definition().drone_count)

func test_interceptor_drone_acquires_and_neutralizes_a_live_moving_uav() -> void:
	main.registry.clear()
	main._on_pressure_changed(5)
	var radar_result := _place_for(main, main.scenario.available_defenses[1])
	var command_result := _place_for(main, main.scenario.available_defenses[2])
	var drone_result := _place_for(main, main.scenario.available_defenses[10])
	assert_true(radar_result.success)
	assert_true(command_result.success)
	assert_true(drone_result.success)
	var base := drone_result.unit as InterceptorDroneDefense
	assert_true(main.session.start_defense())
	main.director.enabled = false
	var threat := main.director._spawn_entry(main.scenario.threat_entries[0], 0.0, 0.0) as AttackUav
	threat.global_position = base.global_position + Vector3(280.0, 70.0, 0.0)
	threat.mover.setup((threat.definition as AttackUavDefinition).movement, main.battlefield, threat.global_position.direction_to(main.objective.global_position))
	for frame: int in 180:
		main._process(0.1)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_eq(int(main.session.neutralized_by_type.get("attack_uav", 0)), 1)
	assert_lt(base.available_drones, base.drone_definition().drone_count)

func _find_valid_position() -> Vector3:
	return _find_valid_position_for(main.scenario.available_defenses[0].placement_profile)

func _find_valid_position_for(profile: PlacementProfile) -> Vector3:
	for z: int in range(-400, 401, 25):
		for x: int in range(-400, 401, 25):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, profile).valid:
				return position
	return Vector3(300.0, 0.0, 300.0)

func _place_for(instance: AirscainMain, definition: DefenseDefinition) -> Dictionary:
	for z: int in range(-420, 421, 30):
		for x: int in range(-420, 421, 30):
			var position := Vector3(float(x), instance.battlefield.terrain_height(float(x), float(z)), float(z))
			if instance.battlefield.placement_result(position, definition.placement_profile).valid:
				return instance.session.request_placement(definition, position, instance.battlefield, instance.defense_parent, instance.registry, instance.projectile_parent)
	return {"success": false, "reason": "테스트 배치 위치 없음"}

func _find_defense(runtime_id: int) -> DefenseUnit:
	for unit: DefenseUnit in main.defenses:
		if unit.runtime_id == runtime_id:
			return unit
	return null

func _active_definition_count(definition_id: StringName) -> int:
	var count := 0
	for threat: ThreatUnit in main.registry.get_active():
		if threat.definition.id == definition_id:
			count += 1
	return count

func _find_contact(runtime_id: int) -> ThreatUnit:
	for contact: ThreatUnit in main.registry.get_active():
		if contact.runtime_id == runtime_id:
			return contact
	return null
