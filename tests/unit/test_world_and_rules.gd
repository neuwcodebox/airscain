extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_world_seed_reproduces_height_and_city_layout() -> void:
	var first := WorldGenerator.new()
	var second := WorldGenerator.new()
	first.generate(91827, 1200.0, 49, 330.0)
	second.generate(91827, 1200.0, 49, 330.0)
	assert_almost_eq(first.height_at(412.5, -277.0), second.height_at(412.5, -277.0), 0.0001)
	assert_eq(first.heights, second.heights)
	assert_eq(first.building_transforms(), second.building_transforms())

func test_different_world_seed_changes_height_field() -> void:
	var first := WorldGenerator.new()
	var second := WorldGenerator.new()
	first.generate(1, 1200.0, 49, 330.0)
	second.generate(2, 1200.0, 49, 330.0)
	assert_ne(first.heights, second.heights)

func test_objective_damage_and_depletion_are_bounded() -> void:
	var objective: ProtectedObjective = autofree(ProtectedObjective.new()) as ProtectedObjective
	var definition := ObjectiveDefinition.new()
	definition.maximum_integrity = 100
	objective.setup(1, definition)
	watch_signals(objective)
	assert_true(objective.apply_mission_damage(10))
	assert_eq(objective.current_integrity, 90)
	assert_true(objective.apply_mission_damage(100))
	assert_eq(objective.current_integrity, 0)
	assert_signal_emit_count(objective, "depleted", 1)
	assert_false(objective.apply_mission_damage(10))
	assert_signal_emit_count(objective, "depleted", 1)

func test_threat_resolution_can_only_happen_once() -> void:
	var threat: ThreatUnit = autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.neutralization_reward = 30
	threat.setup(7, definition)
	watch_signals(threat)
	assert_true(threat.resolve_once(true))
	assert_false(threat.resolve_once(false))
	assert_signal_emit_count(threat, "resolved", 1)

func test_pressure_rises_and_spawn_load_is_bounded() -> void:
	var director: ThreatDirector = autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	assert_eq(director.pressure_level_at(0.0), 1)
	assert_eq(director.pressure_level_at(45.0), 2)
	assert_lt(director.spawn_interval_at(180.0), director.spawn_interval_at(0.0))
	assert_gt(director.spawn_count_at(240.0), director.spawn_count_at(0.0))
	assert_lte(director.speed_multiplier_at(10000.0), 2.0)
