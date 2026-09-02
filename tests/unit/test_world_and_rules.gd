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

func test_scenario_seed_selects_reproducible_distinct_battlefield_layouts() -> void:
	assert_eq(SCENARIO.battlefield_layout().id, &"island_city")
	var alternate := SCENARIO.duplicate(true) as ScenarioDefinition
	alternate.world_seed = SCENARIO.world_seed - 1
	assert_eq(alternate.battlefield_layout().id, &"rugged_harbor")
	assert_gt(alternate.battlefield_layout().starting_budget_bonus, SCENARIO.battlefield_layout().starting_budget_bonus)
	var island := WorldGenerator.new()
	var rugged := WorldGenerator.new()
	island.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	rugged.generate(alternate.world_seed, alternate.battlefield_size, alternate.terrain_resolution, alternate.city_size, alternate.battlefield_layout())
	assert_ne(island.building_transforms().size(), rugged.building_transforms().size())
	assert_ne(island.heights, rugged.heights)

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
	assert_eq(objective.damage_smoke_effects.size(), 1)
	assert_true(objective.apply_mission_damage(100))
	assert_eq(objective.current_integrity, 0)
	assert_eq(objective.damage_smoke_effects.size(), 4)
	assert_signal_emit_count(objective, "depleted", 1)
	assert_false(objective.apply_mission_damage(10))
	assert_signal_emit_count(objective, "depleted", 1)
	objective.restore_integrity(75)
	assert_eq(objective.damage_smoke_effects.size(), 1)

func test_threat_resolution_can_only_happen_once() -> void:
	var threat: ThreatUnit = autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.neutralization_reward = 30
	threat.setup(7, definition)
	watch_signals(threat)
	assert_true(threat.resolve_once(true))
	assert_false(threat.resolve_once(false))
	assert_signal_emit_count(threat, "resolved", 1)

func test_flare_and_chaff_can_defeat_matching_seekers_with_finite_charges() -> void:
	var threat: ThreatUnit = autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.flare_effectiveness = 0.8
	definition.chaff_effectiveness = 0.4
	definition.countermeasure_charges = 2
	threat.setup(8, definition)
	assert_true(threat.try_defeat_seeker(1.0, 0.0, 0.5))
	assert_false(threat.try_defeat_seeker(0.0, 1.0, 0.5))
	assert_true(threat.try_defeat_seeker(0.0, 1.0, 0.3))
	assert_eq(threat.countermeasure_charges_remaining, 0)
	assert_false(threat.try_defeat_seeker(1.0, 1.0, 0.0))

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
	assert_gt(director.threat_budget_at(240.0), director.threat_budget_at(0.0))
	assert_lte(director.speed_multiplier_at(10000.0), 2.0)
	assert_eq(SCENARIO.raid_archetypes[0].id, &"recon_saturation_strike")
	assert_eq(SCENARIO.raid_archetypes[0].phase_entries.size(), 3)
	assert_eq(SCENARIO.raid_archetypes[0].phase_delays, [0.0, 4.0, 8.0])
	assert_eq(SCENARIO.raid_archetypes[0].total_cost(), 9.0)

func test_running_session_receives_timed_and_attack_window_support() -> void:
	var session := autofree(GameSession.new()) as GameSession
	session.reset(100, 10.0, 25)
	session.defense_count = 1
	assert_true(session.start_defense())
	assert_eq(session.gameplay_delta(9.0), 9.0)
	assert_eq(session.budget, 100)
	session.gameplay_delta(1.0)
	assert_eq(session.budget, 125)
	assert_eq(session.support_payment_count, 1)
	session.grant_attack_window_reward(40)
	assert_eq(session.budget, 165)
	assert_eq(session.completed_attack_windows, 1)
	assert_eq(session.total_support_received, 65)

func test_director_enters_recovery_once_per_attack_window() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	director.enabled = true
	director.until_spawn = 1000.0
	var recovery_count: Array[int] = [0]
	director.recovery_started.connect(func(_window: int) -> void: recovery_count[0] += 1)
	director.gameplay_tick(SCENARIO.attack_window_duration)
	assert_true(director.in_recovery)
	assert_eq(recovery_count[0], 1)
	var paused_spawn_time := director.until_spawn
	director.gameplay_tick(SCENARIO.recovery_duration - 0.1)
	assert_eq(director.until_spawn, paused_spawn_time)
	director.gameplay_tick(0.1)
	assert_false(director.in_recovery)
	assert_eq(recovery_count[0], 1)

func test_advanced_defenses_require_matching_pressure_level() -> void:
	assert_eq(SCENARIO.available_defenses[0].unlock_pressure_level, 1)
	assert_eq(SCENARIO.available_defenses[3].unlock_pressure_level, 2)
	assert_eq(SCENARIO.available_defenses[6].unlock_pressure_level, 3)
	assert_eq(SCENARIO.available_defenses[7].unlock_pressure_level, 4)
	assert_eq(SCENARIO.available_defenses[9].unlock_pressure_level, 5)

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

func test_missile_layers_have_distinct_range_cost_ammunition_and_channels() -> void:
	var medium := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	var long_range := SCENARIO.available_defenses[7] as MissileBatteryDefinition
	var short_range := SCENARIO.available_defenses[8] as MissileBatteryDefinition
	assert_gt(long_range.attack_range, medium.attack_range)
	assert_gt(medium.attack_range, short_range.attack_range)
	assert_gt(long_range.price, medium.price)
	assert_lt(short_range.price, medium.price)
	assert_lt(long_range.munitions[0].magazine_capacity, medium.munitions[0].magazine_capacity)
	assert_gt(short_range.munitions[0].magazine_capacity, medium.munitions[0].magazine_capacity)
	assert_gt(long_range.engagement_channels, medium.engagement_channels)
	assert_gt(long_range.maximum_engagement_altitude, medium.maximum_engagement_altitude)
	assert_gt(medium.maximum_engagement_altitude, short_range.maximum_engagement_altitude)
	assert_gt(long_range.minimum_engagement_altitude, short_range.minimum_engagement_altitude)
	assert_gt(short_range.munitions[0].small_target_match, medium.munitions[0].small_target_match)
	assert_eq(long_range.munitions.size(), 2)
	assert_true(long_range.munitions[1].high_cost)
	assert_eq(long_range.munitions[1].salvo_size, 2)
	assert_eq(long_range.munitions[1].preferred_classes, [&"ballistic_missile", &"rocket", &"strike_aircraft"])
	var hpm := SCENARIO.available_defenses[9] as HighPowerMicrowaveDefinition
	assert_gt(hpm.effect_radius, 0.0)
	assert_gt(hpm.energy_per_pulse, 0.0)
	var drones := SCENARIO.available_defenses[10] as InterceptorDroneDefenseDefinition
	assert_gt(drones.drone_count, drones.engagement_channels)
	assert_gt(drones.recharge_duration, drones.launch_interval)

func test_threat_definitions_compose_movement_and_mission_profiles() -> void:
	var attack := SCENARIO.threat_entries[0].threat_definition as AttackUavDefinition
	var swarm := SCENARIO.threat_entries[1].threat_definition as AttackUavDefinition
	assert_not_null(attack.movement)
	assert_not_null(attack.mission)
	assert_eq(attack.mission.type, ThreatMissionDefinition.Type.IMPACT)
	assert_eq(attack.mission.target_role, ThreatMissionDefinition.TargetRole.CITY)
	assert_gt(swarm.movement.speed, attack.movement.speed)
	var decoy := SCENARIO.threat_entries[6].threat_definition as AttackUavDefinition
	assert_eq(decoy.id, &"decoy_uav")
	assert_eq(decoy.mission.type, ThreatMissionDefinition.Type.RECONNAISSANCE)
	assert_eq(decoy.mission.damage, 0.0)
	assert_eq(decoy.false_echo_count, 2)
	var jammer := SCENARIO.threat_entries[7].threat_definition as AttackUavDefinition
	assert_eq(jammer.id, &"electronic_warfare_uav")
	assert_gt(jammer.jamming_range, 0.0)
	assert_gt(jammer.jamming_strength, 0.0)
	var anti_radiation := SCENARIO.threat_entries[8].threat_definition as AttackUavDefinition
	assert_eq(anti_radiation.id, &"anti_radiation_missile")
	assert_eq(anti_radiation.mission.target_role, ThreatMissionDefinition.TargetRole.SENSOR)
	assert_eq(SCENARIO.raid_archetypes[1].id, &"deception_sead_strike")
	assert_eq(SCENARIO.raid_archetypes[1].total_cost(), 9.0)
	var ballistic := SCENARIO.threat_entries[9].threat_definition as AttackUavDefinition
	var rockets := SCENARIO.threat_entries[10]
	var aircraft := SCENARIO.threat_entries[11].threat_definition as AttackUavDefinition
	assert_eq(ballistic.movement.mode, ThreatMovementDefinition.Mode.BALLISTIC_ARC)
	assert_gt(ballistic.movement.ballistic_apex, 900.0)
	assert_lt(ballistic.movement.ballistic_boost_fraction, ballistic.movement.ballistic_reentry_fraction)
	assert_lte(ballistic.movement.maximum_speed_multiplier, 1.2)
	assert_eq(rockets.group_size, 4)
	assert_lte((rockets.threat_definition as AttackUavDefinition).movement.maximum_speed_multiplier, 1.2)
	assert_eq(aircraft.mission.type, ThreatMissionDefinition.Type.STRIKE_AND_EXIT)
	assert_gt(aircraft.movement.speed, attack.movement.speed * 3.0)
	assert_eq(SCENARIO.raid_archetypes[2].id, &"mixed_ballistic_air_strike")
	assert_lt(swarm.movement.cruise_altitude, attack.movement.cruise_altitude)
	assert_ne(swarm.movement, attack.movement)
	var cruise := SCENARIO.threat_entries[5].threat_definition as AttackUavDefinition
	assert_eq(cruise.movement.mode, ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING)
	assert_lt(cruise.movement.cruise_altitude, swarm.movement.cruise_altitude)
	assert_gt(cruise.movement.speed, swarm.movement.speed)
	assert_gt(aircraft.movement.cruise_altitude, jammer.movement.cruise_altitude)
	var search_radar := SCENARIO.available_defenses[1] as SearchRadarDefinition
	var high_altitude_radar := SCENARIO.available_defenses[3] as SearchRadarDefinition
	assert_lt(search_radar.maximum_detection_altitude, high_altitude_radar.minimum_detection_altitude + 150.0)
	assert_gt(high_altitude_radar.maximum_detection_altitude, ballistic.movement.ballistic_apex)

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
	session.set_simulation_speed(4.0)
	assert_eq(session.gameplay_delta(0.5), 2.0)
	assert_eq(session.survival_time, 4.0)
