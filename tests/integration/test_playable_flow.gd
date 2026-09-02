extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func before_each() -> void:
	main = add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	await get_tree().process_frame

func test_scenario_starts_with_generated_world_and_preparation_state() -> void:
	assert_not_null(main.objective)
	assert_gt(main.battlefield.terrain.mesh.get_surface_count(), 0)
	assert_eq(main.battlefield.battlefield_size, 2400.0)
	assert_eq((main.battlefield.ocean.mesh as PlaneMesh).size.x, 19200.0)
	assert_eq(main.camera_rig.camera.far, 14400.0)
	assert_gt(main.battlefield.city_visuals.get_child_count(), 30)
	assert_eq(main.registry.count(), 4)
	assert_eq(main.registry.hostile_count(), 0)
	assert_eq(main.session.phase, GameSession.Phase.PREPARATION)
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
	main._on_world_selected(track.estimated_position)
	main.track_display._process(0.0)
	var marker := main.track_display.markers[track.track_id] as TrackMarker
	assert_true(marker.selected)
	assert_string_contains(marker.icon.text, "T-%03d" % track.track_id)
	assert_not_null(main.track_display.selection_lines.mesh)
	assert_eq(main.track_display.selection_details(), {"sensor_count": 1, "engagement_count": 1})
	assert_true(main.hud.selected_asset_panel.visible)
	assert_string_contains(main.hud.selected_track_label.text, "센서 1 · 교전 자산 1")
	assert_eq(int(main.tactical_screen_overlay.get("selected_track_id")), track.track_id)
	main._on_focus_requested()
	assert_almost_eq(main.camera_rig.global_position.x, track.estimated_position.x, 0.01)
	assert_almost_eq(main.camera_rig.global_position.z, track.estimated_position.z, 0.01)

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
	for frame: int in 100:
		battery.gameplay_tick(0.02)
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
	assert_eq(main.session.neutralized_count, 1)
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

func test_swarm_entry_spawns_a_close_formation_package() -> void:
	main.registry.clear()
	main.scenario.threat_entries = [main.scenario.threat_entries[1]]
	main.director.elapsed = 45.0
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
	main.scenario.threat_entries = [main.scenario.threat_entries[2]]
	main.director.pressure_level = 2
	var recon := main.director.spawn_one() as AttackUav
	assert_same(recon.mission_runtime.target_asset, radar)
	recon.global_position = radar.global_position + Vector3(10.0, 2.0, 0.0)
	for frame: int in 52:
		recon.gameplay_tick(0.1)
	var estimate := main.enemy_knowledge.best_estimate_for_role(&"sensor")
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
	var initial_agl := threat.global_position.y - main.battlefield.terrain_height(threat.global_position.x, threat.global_position.z)
	assert_almost_eq(initial_agl, definition.movement.cruise_altitude, 0.001)
	for frame: int in 30:
		threat.gameplay_tick(0.1)
	var agl := threat.global_position.y - main.battlefield.terrain_height(threat.global_position.x, threat.global_position.z)
	assert_gt(agl, 5.0)
	assert_lt(agl, 45.0)
	assert_eq(threat.get_sensor_signature().classification_hint, &"cruise_missile")

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
	for step: int in 28:
		threat.gameplay_tick(0.1)
	assert_gt(threat.global_position.y, 300.0)
	for step: int in 40:
		if threat.resolved_state:
			break
		threat.gameplay_tick(0.1)
	assert_true(threat.resolved_state)
	assert_eq(main.objective.current_integrity, starting_integrity - roundi(definition.mission.damage))

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
	gun.gameplay_tick(0.01)
	assert_true(main.engagement_coordinator.has_reservation(track.track_id))
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
	for frame: int in 80:
		main.power_manager.begin_tick()
		main.engagement_coordinator.gameplay_tick(0.1)
		laser.gameplay_tick(0.1)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_lt(laser.energy_state.energy, starting_energy)
	assert_gt(laser.energy_state.heat, 0.0)

func test_hpm_pulse_affects_multiple_electronic_targets_in_observed_area() -> void:
	main.registry.clear()
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
	assert_eq(hpm._fire_pulse(track), 2)
	assert_lt(threats[0].health, 100.0)
	assert_lt(threats[1].health, 100.0)
	assert_eq(threats[2].health, 100.0)

func test_interceptor_drone_returns_and_recharges_for_reuse() -> void:
	main.registry.clear()
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
	var drone := base._launch(track)
	assert_eq(base.available_drones, base.drone_definition().drone_count - 1)
	drone.global_position = threat.global_position - Vector3.RIGHT
	drone.gameplay_tick(0.02)
	assert_lt(threat.health, 100.0)
	assert_eq(drone.state, InterceptorDrone.State.RETURNING)
	drone.global_position = base.global_position + Vector3.UP * 6.0
	drone.gameplay_tick(0.01)
	assert_eq(base.recharge_queue.size(), 1)
	base.gameplay_tick(base.drone_definition().recharge_duration + 0.1)
	assert_eq(base.available_drones, base.drone_definition().drone_count)

func _find_valid_position() -> Vector3:
	return _find_valid_position_for(main.scenario.available_defenses[0].placement_profile)

func _find_valid_position_for(profile: PlacementProfile) -> Vector3:
	for z: int in range(-400, 401, 25):
		for x: int in range(-400, 401, 25):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, profile).valid:
				return position
	return Vector3(300.0, 0.0, 300.0)

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
