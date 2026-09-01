extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_first_scenario_has_all_required_references_and_valid_ranges() -> void:
	assert_eq(SCENARIO.validation_error(), "")

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

func test_island_center_is_land_and_outer_edge_is_below_sea() -> void:
	var generator := WorldGenerator.new()
	generator.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size)
	assert_gt(generator.height_at(0.0, 0.0), generator.sea_level)
	var guaranteed_land_radius := SCENARIO.battlefield_size * 0.33
	for z: int in range(-750, 751, 125):
		for x: int in range(-750, 751, 125):
			if Vector2(float(x), float(z)).length() <= guaranteed_land_radius:
				assert_gt(generator.height_at(float(x), float(z)), generator.sea_level)
	var submerged_edge := SCENARIO.battlefield_size * 0.495
	assert_lt(generator.height_at(submerged_edge, 0.0), generator.sea_level)
	assert_lt(generator.height_at(0.0, -submerged_edge), generator.sea_level)

func test_objective_damage_and_depletion_are_bounded() -> void:
	var objective: ProtectedObjective = add_child_autofree(ProtectedObjective.new()) as ProtectedObjective
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

func test_neutral_contact_does_not_award_budget_or_hostile_statistics() -> void:
	var session := autofree(GameSession.new()) as GameSession
	session.reset(100)
	var contact := autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.affiliation = ThreatDefinition.Affiliation.NEUTRAL
	definition.neutralization_reward = 50
	contact.setup(-1, definition)
	session.register_threat_resolution(contact, true, definition.neutralization_reward)
	assert_eq(session.budget, 100)
	assert_eq(session.neutralized_count, 0)

func test_pressure_rises_and_spawn_load_is_bounded() -> void:
	var director: ThreatDirector = autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	assert_eq(director.pressure_level_at(0.0), 1)
	assert_eq(director.pressure_level_at(45.0), 2)
	assert_lt(director.spawn_interval_at(180.0), director.spawn_interval_at(0.0))
	assert_gt(director.spawn_count_at(240.0), director.spawn_count_at(0.0))
	assert_lte(director.speed_multiplier_at(10000.0), 2.0)

func test_close_in_gun_has_distinct_small_target_match_and_short_range() -> void:
	var definition := SCENARIO.available_defenses[4] as CloseInGunDefinition
	var gun: CloseInGun = autofree(definition.scene.instantiate()) as CloseInGun
	gun.setup(1, definition)
	var missile_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	var battery: MissileBattery = autofree(missile_definition.scene.instantiate()) as MissileBattery
	battery.setup(2, missile_definition)
	var small_track := PlayerTrack.new()
	small_track.classification = &"small_uav"
	var larger_track := PlayerTrack.new()
	larger_track.classification = &"uav"
	assert_lt(definition.attack_range, missile_definition.attack_range)
	assert_gt(gun.weapon_match(small_track), gun.weapon_match(larger_track))
	assert_eq(gun.engagement_limit(small_track), 2)
	assert_eq(gun.engagement_limit(larger_track), 1)
	assert_lt(battery.weapon_match(small_track), battery.weapon_match(larger_track))

func test_threat_definitions_compose_movement_and_mission_profiles() -> void:
	var attack := SCENARIO.threat_entries[0].threat_definition as AttackUavDefinition
	var swarm := SCENARIO.threat_entries[1].threat_definition as AttackUavDefinition
	assert_not_null(attack.movement)
	assert_not_null(attack.mission)
	assert_eq(attack.mission.type, ThreatMissionDefinition.Type.IMPACT)
	assert_eq(attack.mission.target_role, ThreatMissionDefinition.TargetRole.CITY)
	assert_gt(swarm.movement.speed, attack.movement.speed)
	assert_lt(swarm.movement.cruise_altitude, attack.movement.cruise_altitude)
	assert_ne(swarm.movement, attack.movement)

func test_recon_and_strike_missions_act_then_egress() -> void:
	var objective: ProtectedObjective = autofree(ProtectedObjective.new()) as ProtectedObjective
	var objective_definition := load("res://world/objective/city/city_objective.tres") as ObjectiveDefinition
	objective.setup(1, objective_definition)
	var support: SupportFacility = add_child_autofree(SupportFacility.new()) as SupportFacility
	support.setup(2, SCENARIO.available_defenses[5])
	support.global_position = Vector3(10.0, 0.0, 0.0)
	var strike_profile := ThreatMissionDefinition.new()
	strike_profile.type = ThreatMissionDefinition.Type.STRIKE_AND_EXIT
	strike_profile.target_role = ThreatMissionDefinition.TargetRole.SUPPORT
	strike_profile.damage = 25.0
	strike_profile.action_distance = 6.0
	var strike := ThreatMissionRuntime.new()
	strike.setup(strike_profile, objective, support.global_position, support, Vector3(100.0, 0.0, 0.0))
	assert_false(strike.gameplay_tick(support.global_position + Vector3.UP * 2.0, 0.1))
	assert_eq(support.integrity, 75.0)
	assert_eq(strike.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_true(strike.gameplay_tick(Vector3(100.0, 2.0, 0.0), 0.1))
	var recon_profile := ThreatMissionDefinition.new()
	recon_profile.type = ThreatMissionDefinition.Type.RECONNAISSANCE
	recon_profile.damage = 0.0
	recon_profile.action_distance = 6.0
	recon_profile.action_duration = 1.0
	var recon := ThreatMissionRuntime.new()
	recon.setup(recon_profile, objective, Vector3.ZERO, null, Vector3(100.0, 0.0, 0.0))
	assert_false(recon.gameplay_tick(Vector3.UP * 2.0, 0.6))
	assert_false(recon.gameplay_tick(Vector3.UP * 2.0, 0.5))
	assert_eq(recon.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_eq(objective.current_integrity, objective.definition.maximum_integrity)

func test_pause_and_speed_controls_scale_only_running_simulation() -> void:
	var session := autofree(GameSession.new()) as GameSession
	session.reset(400)
	session.defense_count = 1
	assert_true(session.start_defense())
	session.set_simulation_speed(0.0)
	assert_eq(session.gameplay_delta(1.0), 0.0)
	assert_eq(session.survival_time, 0.0)
	session.set_simulation_speed(2.0)
	assert_eq(session.gameplay_delta(1.0), 2.0)
	assert_eq(session.survival_time, 2.0)
