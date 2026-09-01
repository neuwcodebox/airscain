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
	assert_eq(main.session.budget, 620)
	assert_eq(main.scenario.available_defenses.size(), 5)
	assert_eq(main.scenario.available_defenses[1].id, &"search_radar")
	assert_eq(main.scenario.available_defenses[2].id, &"command_post")
	assert_eq(main.scenario.available_defenses[3].id, &"tracking_radar")
	assert_eq(main.scenario.available_defenses[4].id, &"close_in_gun")
	assert_eq(main.scenario.threat_entries[1].threat_definition.id, &"swarm_uav")
	assert_eq(main.scenario.threat_entries[1].group_size, 4)
	assert_false(main.session.start_defense())

func test_search_radar_can_be_purchased_and_rotates_during_gameplay() -> void:
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var placement_position := _find_valid_position_for(radar_definition.placement_profile)
	var result: Dictionary = main.session.request_placement(radar_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	assert_eq(main.session.budget, 500)
	var radar := result.unit as DefenseUnit
	assert_not_null(radar)
	var antenna := radar.get_node("Antenna") as Node3D
	var starting_rotation: float = antenna.rotation.y
	radar.gameplay_tick(1.0)
	assert_ne(antenna.rotation.y, starting_rotation)

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
	assert_eq(main.track_display.get_child_count(), 1)
	var marker := main.track_display.get_child(0) as Node3D
	assert_true(marker.visible)
	radar.active = false
	main.player_knowledge.call("gameplay_tick", 0.6)
	assert_true(marker.visible)
	main.player_knowledge.call("gameplay_tick", 1.4)
	assert_false(marker.visible)

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
	assert_gt(int(main.c2_overlay.get("visible_link_count")), 0)
	for frame: int in 300:
		main.player_knowledge.call("gameplay_tick", 0.02)
		radar.gameplay_tick(0.02)
		battery.gameplay_tick(0.02)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_eq(main.session.neutralized_count, 1)
	assert_eq(main.session.budget, 230)
	assert_false(threat.receive_damage(100.0))
	assert_eq(main.session.neutralized_count, 1)
	assert_eq(main.session.budget, 230)

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
	assert_eq(restored_threat.health, saved_health)
	assert_eq(main.projectile_parent.get_child_count(), 0, "일시적인 예광탄 VFX는 저장 대상이 아닙니다")
	var budget_before_kill := main.session.budget
	for frame: int in 80:
		restored_gun.gameplay_tick(0.1)
		if restored_threat.resolved_state:
			break
	assert_true(restored_threat.resolved_state)
	assert_eq(main.session.neutralized_count, 1)
	assert_eq(main.session.budget, budget_before_kill + swarm_definition.neutralization_reward)

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

func _find_contact(runtime_id: int) -> ThreatUnit:
	for contact: ThreatUnit in main.registry.get_active():
		if contact.runtime_id == runtime_id:
			return contact
	return null
