extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_phase_briefings_match_the_spec_unlock_table() -> void:
	var expected_levels := {&"operation_start": 1, &"recon_and_swarms": 2, &"cruise_and_jamming": 4, &"defense_suppression": 6, &"high_altitude_strikes": 8, &"air_strikes_and_saturation": 10, &"ballistic_threat": 12}
	var expected := {
		&"operation_start": [[&"attack_uav"], [&"missile_battery", &"search_radar", &"command_post", &"close_in_gun", &"support_facility", &"radar_decoy", &"weapon_decoy"]],
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
		assert_eq(briefing.unlock_level, expected_levels[briefing.id], String(briefing.id))
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
	assert_eq(delivered, [&"operation_start", &"recon_and_swarms"] as Array[StringName])
	controller.pressure_reached(5)
	assert_eq(delivered, [&"operation_start", &"recon_and_swarms", &"cruise_and_jamming"] as Array[StringName])
	controller.pressure_reached(6)
	assert_eq(delivered.size(), 4, "6단계에서 다음 묶음 브리핑을 전달합니다")

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
	assert_eq(OperationBriefingController.legacy_state(SCENARIO, 3).delivered, ["operation_start", "recon_and_swarms"])

func test_briefed_threats_first_fly_one_level_after_their_briefing() -> void:
	for briefing: OperationBriefingDefinition in SCENARIO.operation_briefings:
		for definition: ThreatDefinition in SCENARIO.briefing_threats(briefing):
			var entry := _entry(definition.id)
			var case_label := "%s %s" % [briefing.id, definition.id]
			assert_eq(entry.unlock_level, briefing.unlock_level, "%s: 국면의 위협은 함께 예고됩니다" % case_label)
			if briefing.unlock_level == 1:
				assert_true(SCENARIO.is_threat_available(entry, 1), "%s: 작전 개시 위협은 첫 공습에 바로 출격합니다" % case_label)
				continue
			assert_false(SCENARIO.is_threat_available(entry, briefing.unlock_level), "%s: 브리핑 단계에는 출격하지 않습니다" % case_label)
			assert_true(SCENARIO.is_threat_available(entry, entry.unlock_level + SCENARIO.threat_intel_lead_levels), case_label)

func test_counter_assets_unlock_before_their_phase_threats_fly() -> void:
	for briefing: OperationBriefingDefinition in SCENARIO.operation_briefings:
		var earliest_flight := 1000000
		for definition: ThreatDefinition in SCENARIO.briefing_threats(briefing):
			earliest_flight = mini(earliest_flight, SCENARIO.threat_flight_level(_entry(definition.id)))
		for definition: DefenseDefinition in SCENARIO.briefing_defenses(briefing):
			assert_eq(definition.unlock_pressure_level, briefing.unlock_level, "%s %s: 대응 자산도 국면과 함께 해금됩니다" % [briefing.id, definition.id])
			if briefing.unlock_level > 1:
				assert_lt(definition.unlock_pressure_level, earliest_flight, "%s %s" % [briefing.id, definition.id])

func test_korean_briefing_text_breaks_only_between_words() -> void:
	var joined := KoreanLineBreak.keep_words("적 무인기 부대가\n출격")
	assert_eq(joined.replace(KoreanLineBreak.WORD_JOINER, ""), "적 무인기 부대가\n출격")
	for word: String in ["적", "무인기", "부대가", "출격"]:
		assert_string_contains(joined, KoreanLineBreak.WORD_JOINER.join(word.split("")), word)
	assert_false(joined.contains(" " + KoreanLineBreak.WORD_JOINER), "공백 뒤는 줄바꿈 가능 지점입니다")
	assert_eq(KoreanLineBreak.keep_words("Enemy drones launch"), "Enemy drones launch")

func _entry(id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	fail_test("missing threat entry %s" % id)
	return null
