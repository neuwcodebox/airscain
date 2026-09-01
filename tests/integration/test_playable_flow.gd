extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func before_each() -> void:
	main = add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	await get_tree().process_frame

func test_scenario_starts_with_generated_world_and_preparation_state() -> void:
	assert_not_null(main.objective)
	assert_gt(main.battlefield.terrain.mesh.get_surface_count(), 0)
	assert_gt(main.battlefield.city_visuals.get_child_count(), 30)
	assert_eq(main.session.phase, GameSession.Phase.PREPARATION)
	assert_eq(main.session.budget, 400)
	assert_false(main.session.start_defense())

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
	var profile: PlacementProfile = main.scenario.available_defenses[0].placement_profile
	for z: int in range(-400, 401, 25):
		for x: int in range(-400, 401, 25):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, profile).valid:
				return position
	return Vector3(300.0, 0.0, 300.0)
