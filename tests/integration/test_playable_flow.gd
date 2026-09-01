extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func before_each() -> void:
	main = add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	await get_tree().process_frame

func test_scenario_starts_with_generated_world_and_preparation_state() -> void:
	assert_not_null(main.objective)
	assert_gt(main.battlefield.terrain.mesh.get_surface_count(), 0)
	assert_eq((main.battlefield.ocean.mesh as PlaneMesh).size.x, 7200.0)
	assert_gt(main.battlefield.city_visuals.get_child_count(), 30)
	assert_eq(main.session.phase, GameSession.Phase.PREPARATION)
	assert_eq(main.session.budget, 400)
	assert_eq(main.scenario.available_defenses.size(), 2)
	assert_eq(main.scenario.available_defenses[1].id, &"search_radar")
	assert_false(main.session.start_defense())

func test_search_radar_can_be_purchased_and_rotates_during_gameplay() -> void:
	var radar_definition: DefenseDefinition = main.scenario.available_defenses[1]
	var placement_position := _find_valid_position_for(radar_definition.placement_profile)
	var result: Dictionary = main.session.request_placement(radar_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	assert_eq(main.session.budget, 280)
	var radar := result.unit as DefenseUnit
	assert_not_null(radar)
	var antenna := radar.get_node("Antenna") as Node3D
	var starting_rotation: float = antenna.rotation.y
	radar.gameplay_tick(1.0)
	assert_ne(antenna.rotation.y, starting_rotation)

func test_search_radar_observes_only_threats_inside_its_coverage() -> void:
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

func test_purchase_start_intercept_and_reward_flow() -> void:
	var placement_position := _find_valid_position()
	var result: Dictionary = main.session.request_placement(main.scenario.available_defenses[0], placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	assert_true(main.session.start_defense())
	main.session.set_simulation_speed(0.0)
	var threat: ThreatUnit = main.director.spawn_one()
	threat.global_position = placement_position + Vector3(0.0, 70.0, 130.0)
	var battery := result.unit as DefenseUnit
	for frame: int in 300:
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
	assert_eq(main.registry.count(), 0)

func _find_valid_position() -> Vector3:
	return _find_valid_position_for(main.scenario.available_defenses[0].placement_profile)

func _find_valid_position_for(profile: PlacementProfile) -> Vector3:
	for z: int in range(-400, 401, 25):
		for x: int in range(-400, 401, 25):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, profile).valid:
				return position
	return Vector3(300.0, 0.0, 300.0)
