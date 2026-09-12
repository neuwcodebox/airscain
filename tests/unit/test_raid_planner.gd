extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_procedural_raids_obey_budget_unlocks_and_scheduling_limits() -> void:
	var planner := RaidPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73129
	var weights := _weights(SCENARIO)
	var patterns: Dictionary = {}
	var formations: Dictionary = {}
	for level: int in [1, 2, 3, 6, 8, 12, 20]:
		for sample: int in 60:
			var budget := 3.0 + level
			var max_delay := 32.0 if sample % 2 == 0 else 0.5
			var waves := planner.generate(SCENARIO, weights, budget, level, rng.randf_range(0.0, TAU), max_delay, 1.0, rng)
			var case_label := "level %d sample %d" % [level, sample]
			assert_false(waves.is_empty(), case_label)
			assert_lte(waves.size(), RaidPlanner.MAX_GROUPS, case_label)
			var cost := 0.0
			var strikes := 0
			var composition: Array[String] = []
			for wave: Dictionary in waves:
				var entry := _entry(StringName(wave.definition_id))
				cost += entry.threat_cost * entry.group_size
				strikes += int(entry.raid_role == ThreatSpawnEntry.RaidRole.STRIKE)
				composition.append(String(entry.threat_definition.id))
				assert_lte(entry.unlock_level, level, "%s threat %s" % [case_label, entry.threat_definition.id])
				assert_between(float(wave.remaining), 0.0, max_delay, "%s threat %s delay" % [case_label, entry.threat_definition.id])
				assert_between(float(wave.angle), 0.0, TAU, "%s threat %s angle" % [case_label, entry.threat_definition.id])
			assert_lte(cost, budget, case_label)
			assert_gt(strikes, 0, "%s: 공습이 보조 기체만으로 예산을 소모하지 않습니다" % case_label)
			patterns[planner.last_pattern] = true
			formations["/".join(composition)] = true
	assert_eq(patterns.size(), RaidPlanner.PATTERNS.size())
	for pattern: StringName in RaidPlanner.PATTERNS:
		assert_true(patterns.has(pattern), "missing pattern %s" % pattern)
	assert_gt(formations.size(), 20)

func test_pair_timing_and_directions_follow_the_selected_intent() -> void:
	var scenario := SCENARIO.duplicate() as ScenarioDefinition
	scenario.threat_entries = []
	for id: StringName in [&"attack_uav", &"decoy_uav", &"anti_radiation_missile", &"strike_aircraft"]:
		var entry := _entry(id).duplicate(true) as ThreatSpawnEntry
		entry.threat_cost = 2.0
		entry.group_size = 1
		entry.unlock_level = 1
		scenario.threat_entries.append(entry)
	var planner := RaidPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 125
	var patterns: Dictionary = {}
	var repeated := 0
	var previous: StringName
	for sample: int in 240:
		var waves := planner.generate(scenario, _weights(scenario), 4.0, 1, 0.8, 300.0, 1.0, rng)
		var case_label := "seed 125 sample %d pattern %s" % [sample, planner.last_pattern]
		patterns[planner.last_pattern] = true
		repeated += int(planner.last_pattern == previous)
		previous = planner.last_pattern
		if planner.last_pattern == &"concentration":
			continue
		assert_eq(waves.size(), 2, case_label)
		var arrivals: Array[float] = []
		var roles: Array[int] = []
		for wave: Dictionary in waves:
			var entry := _entry_in(scenario, StringName(wave.definition_id))
			var distance := scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier() - (scenario.city_size * 0.5 + 260.0)
			arrivals.append(float(wave.remaining) + entry.threat_definition.estimated_approach_seconds(distance, 1.0))
			roles.append(entry.raid_role)
		if planner.last_pattern == &"layered":
			assert_lte(absf(arrivals[0] - arrivals[1]), 2.001, case_label)
		elif planner.last_pattern == &"diversion":
			var decoy_index := roles.find(ThreatSpawnEntry.RaidRole.DECEPTION)
			assert_ne(decoy_index, -1, "%s deception role" % case_label)
			if decoy_index == -1:
				continue
			assert_between(arrivals[1 - decoy_index] - arrivals[decoy_index], 5.999, 12.001, case_label)
			assert_gte(absf(angle_difference(float(waves[0].angle), float(waves[1].angle))), PI * 0.5, case_label)
		elif planner.last_pattern == &"suppression":
			var lead_index := roles.find(ThreatSpawnEntry.RaidRole.SUPPRESSION)
			assert_ne(lead_index, -1, "%s suppression role" % case_label)
			if lead_index == -1:
				continue
			assert_between(arrivals[1 - lead_index] - arrivals[lead_index], 9.999, 18.001, case_label)
	assert_eq(patterns.size(), RaidPlanner.PATTERNS.size())
	for pattern: StringName in RaidPlanner.PATTERNS:
		assert_true(patterns.has(pattern), "missing pattern %s" % pattern)
	assert_lt(repeated, 40, "같은 전개의 연속 선택을 낮추되 금지하지 않습니다")

func test_missing_knowledge_zero_weights_and_tight_deadline_fall_back_safely() -> void:
	var planner := RaidPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var weights := _weights(SCENARIO)
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		if entry.raid_role != ThreatSpawnEntry.RaidRole.STRIKE:
			weights[entry.threat_definition.id] = 0.0
	for sample: int in 50:
		var waves := planner.generate(SCENARIO, weights, 6.0, 20, 0.0, 0.0, 1.0, rng)
		var case_label := "seed 23 sample %d" % sample
		assert_eq(planner.last_pattern, &"concentration", case_label)
		for wave: Dictionary in waves:
			assert_eq(float(wave.remaining), 0.0, case_label)
			assert_gt(weights[StringName(wave.definition_id)], 0.0, "%s threat %s" % [case_label, wave.definition_id])
	assert_true(planner.generate(SCENARIO, {}, 100.0, 20, 0.0, 32.0, 1.0, rng).is_empty())
	assert_true(planner.generate(SCENARIO, weights, 0.1, 20, 0.0, 32.0, 1.0, rng).is_empty())

func test_same_rng_and_history_reproduce_the_next_plan() -> void:
	var planner := RaidPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 553
	var weights := _weights(SCENARIO)
	planner.generate(SCENARIO, weights, 18.0, 20, 0.2, 32.0, 1.4, rng)
	var saved_rng := rng.state
	var saved_pattern := planner.last_pattern
	var expected := planner.generate(SCENARIO, weights, 18.0, 20, 0.2, 32.0, 1.4, rng)
	var restored := RaidPlanner.new()
	restored.last_pattern = saved_pattern
	rng.state = saved_rng
	assert_eq(restored.generate(SCENARIO, weights, 18.0, 20, 0.2, 32.0, 1.4, rng), expected)
	assert_eq(restored.last_pattern, planner.last_pattern)

func _weights(scenario: ScenarioDefinition) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		result[entry.threat_definition.id] = entry.selection_weight
	return result

func _entry(id: StringName) -> ThreatSpawnEntry:
	return _entry_in(SCENARIO, id)

func _entry_in(scenario: ScenarioDefinition, id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	fail_test("missing threat entry %s" % id)
	return null

func test_asset_suppression_priority_still_requires_eligible_observed_entries() -> void:
	var scenario := SCENARIO.duplicate() as ScenarioDefinition
	scenario.asset_suppression_chance = 1.0
	var planner := RaidPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for sample: int in 20:
		var waves := planner.generate(scenario, _weights(scenario), 25.0, 12, 0.0, 300.0, 1.0, rng)
		var asset_strike := false
		for wave: Dictionary in waves:
			var entry := _entry(StringName(wave.definition_id))
			var mission := entry.threat_definition.mission_definition()
			asset_strike = asset_strike or (entry.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION and mission != null and mission.target_role != ThreatMissionDefinition.TargetRole.CITY)
		assert_true(asset_strike, "seed 41 sample %d" % sample)
	var unknown_weights := _weights(scenario)
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if entry.threat_definition.requires_role_knowledge:
			unknown_weights[entry.threat_definition.id] = 0.0
	for wave: Dictionary in planner.generate(scenario, unknown_weights, 25.0, 12, 0.0, 300.0, 1.0, rng):
		assert_false(_entry(StringName(wave.definition_id)).threat_definition.requires_role_knowledge)

func test_jamming_escort_arrives_with_the_main_effort() -> void:
	var scenario := SCENARIO.duplicate() as ScenarioDefinition
	scenario.asset_suppression_chance = 1.0
	var weights: Dictionary[StringName, float] = {}
	var jammer := _entry_in(scenario, &"electronic_warfare_uav")
	var strike := _entry_in(scenario, &"attack_uav")
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		weights[entry.threat_definition.id] = 0.0
	weights[jammer.threat_definition.id] = 1.0
	weights[strike.threat_definition.id] = 1.0
	var planner := RaidPlanner.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 712
	var checked := 0
	for sample: int in 60:
		var waves := planner.generate(scenario, weights, 5.0, 8, 0.0, 300.0, 1.0, rng)
		if planner.last_pattern != &"suppression":
			continue
		checked += 1
		var arrival: Dictionary = {}
		for wave: Dictionary in waves:
			var entry := _entry_in(scenario, StringName(wave.definition_id))
			assert_true(entry == jammer or entry == strike, "seed 712 sample %d unexpected threat %s" % [sample, wave.definition_id])
			if entry != jammer and entry != strike:
				continue
			var distance := scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier() - (scenario.city_size * 0.5 + 260.0)
			arrival[entry.threat_definition.id] = float(wave.remaining) + entry.threat_definition.estimated_approach_seconds(distance, 1.0)
		assert_between(
			float(arrival[strike.threat_definition.id]) - float(arrival[jammer.threat_definition.id]),
			1.999,
			5.001,
			"seed 712 sample %d" % sample
		)
	assert_gt(checked, 10, "seed 712 should produce enough suppression samples")

func test_suppression_package_combines_jamming_direct_attack_and_city_strike() -> void:
	var scenario := SCENARIO.duplicate() as ScenarioDefinition
	scenario.asset_suppression_chance = 1.0
	var jammer := _entry_in(scenario, &"electronic_warfare_uav")
	var anti_radiation := _entry_in(scenario, &"anti_radiation_missile")
	var strike := _entry_in(scenario, &"attack_uav")
	var weights: Dictionary[StringName, float] = {}
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		weights[entry.threat_definition.id] = 0.0
	weights[jammer.threat_definition.id] = 1.0
	weights[anti_radiation.threat_definition.id] = 1.0
	weights[strike.threat_definition.id] = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var planner := RaidPlanner.new()
	var travel_distances: Dictionary[StringName, float] = {
		jammer.threat_definition.id: 3000.0,
		anti_radiation.threat_definition.id: 4000.0,
	}
	var waves := planner.generate(scenario, weights, 8.0, 8, 0.0, 300.0, 1.0, rng, travel_distances)
	assert_eq(planner.last_pattern, &"suppression")
	assert_eq(waves.size(), 3)
	var arrivals: Dictionary[StringName, float] = {}
	for wave: Dictionary in waves:
		var entry := _entry_in(scenario, StringName(wave.definition_id))
		var distance := float(travel_distances.get(entry.threat_definition.id, scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier() - (scenario.city_size * 0.5 + 260.0)))
		arrivals[entry.threat_definition.id] = float(wave.remaining) + entry.threat_definition.estimated_approach_seconds(distance, 1.0)
	assert_between(arrivals[strike.threat_definition.id] - arrivals[anti_radiation.threat_definition.id], 9.999, 18.001)
	assert_between(arrivals[strike.threat_definition.id] - arrivals[jammer.threat_definition.id], 1.999, 5.001)
