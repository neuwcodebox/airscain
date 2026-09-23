extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_phase_briefings_match_the_spec_unlock_table() -> void:
	var expected := {
		&"operation_start": [[&"attack_uav"], [&"missile_battery", &"search_radar", &"command_post", &"close_in_gun", &"support_facility"]],
		&"recon_and_swarms": [[&"swarm_uav", &"recon_uav", &"decoy_uav"], [&"high_energy_laser"]],
		&"cruise_and_jamming": [[&"support_strike_uav", &"defense_strike_uav", &"cruise_missile", &"electronic_warfare_uav", &"anti_radiation_missile"], [&"short_range_missile", &"interceptor_drone_defense"]],
		&"defense_suppression": [[&"battery_strike_uav", &"battery_strike_cruise", &"support_strike_cruise", &"small_defense_strike_uav"], [&"high_power_microwave"]],
		&"high_altitude_strikes": [[&"rocket", &"battery_strike_aircraft", &"radar_strike_aircraft"], [&"tracking_radar"]],
		&"air_strikes_and_saturation": [[&"strike_aircraft", &"weapon_saturation_uav", &"radar_saturation_uav"], [&"long_range_missile"]],
		&"ballistic_threat": [[&"ballistic_missile"], []],
	}
	assert_eq(SCENARIO.operation_briefings.size(), expected.size())
	for briefing: OperationBriefingDefinition in SCENARIO.operation_briefings:
		assert_true(expected.has(briefing.id), String(briefing.id))
		var threat_ids: Array = []
		for definition: ThreatDefinition in SCENARIO.briefing_threats(briefing):
			threat_ids.append(definition.id)
		var defense_ids: Array = []
		for definition: DefenseDefinition in SCENARIO.briefing_defenses(briefing):
			defense_ids.append(definition.id)
		threat_ids.sort()
		defense_ids.sort()
		var expected_threats: Array = expected[briefing.id][0].duplicate()
		var expected_defenses: Array = expected[briefing.id][1].duplicate()
		expected_threats.sort()
		expected_defenses.sort()
		assert_eq(threat_ids, expected_threats, "%s threats" % briefing.id)
		assert_eq(defense_ids, expected_defenses, "%s defenses" % briefing.id)

func test_every_unlocked_threat_and_asset_is_introduced_by_exactly_one_phase() -> void:
	var introduced_threats: Dictionary[StringName, int] = {}
	var introduced_defenses: Dictionary[StringName, int] = {}
	for briefing: OperationBriefingDefinition in SCENARIO.operation_briefings:
		for definition: ThreatDefinition in SCENARIO.briefing_threats(briefing):
			introduced_threats[definition.id] = introduced_threats.get(definition.id, 0) + 1
		for definition: DefenseDefinition in SCENARIO.briefing_defenses(briefing):
			introduced_defenses[definition.id] = introduced_defenses.get(definition.id, 0) + 1
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		assert_eq(introduced_threats.get(entry.threat_definition.id, 0), 1, String(entry.threat_definition.id))
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		assert_eq(introduced_defenses.get(definition.id, 0), 1, String(definition.id))

func test_briefings_must_start_at_level_one_and_ascend() -> void:
	var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	assert_eq(scenario.validation_error(), "")
	var reordered := scenario.operation_briefings.duplicate()
	reordered.reverse()
	scenario.operation_briefings.assign(reordered)
	assert_ne(scenario.validation_error(), "")

func test_controller_delivers_each_reached_phase_once_in_phase_order() -> void:
	var controller := autofree(OperationBriefingController.new()) as OperationBriefingController
	controller.configure(SCENARIO, true)
	var delivered: Array[StringName] = []
	controller.briefing_delivered.connect(func(briefing: OperationBriefingDefinition) -> void: delivered.append(briefing.id))
	controller.pressure_reached(1)
	controller.pressure_reached(1)
	controller.pressure_reached(3)
	assert_eq(delivered, [&"operation_start", &"recon_and_swarms", &"cruise_and_jamming"] as Array[StringName])
	controller.pressure_reached(5)
	assert_eq(delivered.size(), 4, "5단계는 4단계 국면 범위 안이므로 새 브리핑이 없습니다")

func test_disabled_controller_never_delivers() -> void:
	var controller := autofree(OperationBriefingController.new()) as OperationBriefingController
	controller.configure(SCENARIO, false)
	controller.pressure_reached(20)
	assert_true(controller.delivered_ids.is_empty())

func test_delivered_state_round_trips_and_rejects_unknown_or_duplicate_ids() -> void:
	var controller := autofree(OperationBriefingController.new()) as OperationBriefingController
	controller.configure(SCENARIO, true)
	controller.pressure_reached(4)
	var state := controller.capture_state()
	assert_eq(OperationBriefingController.validation_error(state, SCENARIO), "")
	var restored := autofree(OperationBriefingController.new()) as OperationBriefingController
	restored.configure(SCENARIO, true)
	restored.restore_state(state)
	assert_eq(restored.delivered_ids, controller.delivered_ids)
	assert_ne(OperationBriefingController.validation_error({"delivered": ["missing"]}, SCENARIO), "")
	assert_ne(OperationBriefingController.validation_error({"delivered": ["operation_start", "operation_start"]}, SCENARIO), "")
	assert_ne(OperationBriefingController.validation_error(null, SCENARIO), "")

func test_legacy_state_marks_phases_up_to_the_reached_level() -> void:
	assert_eq(OperationBriefingController.legacy_state(SCENARIO, 3).delivered, ["operation_start", "recon_and_swarms", "cruise_and_jamming"])

func test_korean_briefing_text_breaks_only_between_words() -> void:
	var joined := OperationBriefingPanel.keep_words("적 무인기 부대가 출격")
	assert_eq(joined.replace(OperationBriefingPanel.WORD_JOINER, ""), "적 무인기 부대가 출격")
	assert_eq(joined.split(" ").size(), 4)
	for word: String in joined.split(" "):
		assert_eq(word.replace(OperationBriefingPanel.WORD_JOINER, "").length() * 2 - 1, maxi(1, word.length()), word)
	assert_eq(OperationBriefingPanel.keep_words("Enemy drones launch"), "Enemy drones launch")
