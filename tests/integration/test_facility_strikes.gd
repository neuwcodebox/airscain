extends GutTest

const IDS: Array[StringName] = [&"battery_strike_cruise", &"support_strike_cruise", &"battery_strike_aircraft", &"radar_strike_aircraft", &"command_strike_aircraft"]
var main: AirscainMain

func before_each() -> void:
	AirscainMain.requested_seed = 73129
	main = add_child_autofree(load("res://main/main.tscn").instantiate()) as AirscainMain
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	main.set_process(false)
	main.session.budget = 10000
	await get_tree().process_frame

func entry_for(id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	return null

func target_for(role: StringName) -> DefenseUnit:
	var index := {&"weapon": 0, &"sensor": 1, &"command": 2, &"support": 5}[role] as int
	var definition := main.scenario.available_defenses[index]
	main._on_pressure_changed(definition.unlock_pressure_level)
	for x: int in range(320, 900, 30):
		var point := Vector3(x, main.battlefield.terrain_height(x, 180), 180)
		var result := main.session.request_placement(definition, point, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
		if result.success:
			return result.unit as DefenseUnit
	fail_test("시설 배치 위치가 없습니다")
	return null

func test_variants_require_matching_knowledge_and_join_city_strike_packages() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73129
	for id: StringName in IDS:
		main.enemy_knowledge.reset()
		var entry := entry_for(id)
		assert_not_null(entry)
		assert_eq(entry.validation_error(), "")
		assert_eq(main.director.adaptive_entry_weight(entry), 0.0)
		var target := target_for(entry.threat_definition.adaptive_knowledge_role)
		main.enemy_knowledge.record_recon(target)
		assert_gt(main.director.adaptive_entry_weight(entry), 0.0)
		assert_has(main._sandbox_threat_definitions(), entry.threat_definition)
		var city := main.scenario.threat_entries[0]
		var weights: Dictionary[StringName, float] = {id: 1.0, city.threat_definition.id: 1.0}
		var planner := RaidPlanner.new()
		var included := false
		for sample: int in 32:
			var waves := planner.generate(main.scenario, weights, entry.threat_cost + city.threat_cost, entry.unlock_level, 0.0, 32.0, 1.0, rng)
			var has_city := false
			for wave: Dictionary in waves:
				included = included or StringName(wave.definition_id) == id
				has_city = has_city or StringName(wave.definition_id) == city.threat_definition.id
			assert_true(has_city, "시설 제압만으로 도시 공격을 대체하지 않습니다")
		assert_true(included, String(id))

func test_each_variant_flies_to_its_role_and_applies_only_one_asset_hit() -> void:
	for id: StringName in IDS:
		main.enemy_knowledge.reset()
		var entry := entry_for(id)
		var definition := entry.threat_definition as AttackUavDefinition
		var target := target_for(definition.adaptive_knowledge_role)
		main.enemy_knowledge.record_recon(target)
		var city_before := main.objective.current_integrity
		var threat := main.director._spawn_entry(entry, 0.5, 0.0) as AttackUav
		for tick: int in 4500:
			threat.gameplay_tick(1.0 / 30.0)
			if threat.mission_runtime.effect_applied or threat.resolved_state:
				break
		assert_true(threat.mission_runtime.effect_applied, "%s impact=%s target=%s mission=%s" % [id, threat.global_position, target.global_position, threat.mission_runtime.capture_state()])
		if definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
			assert_eq(target.integrity, target.definition.maximum_integrity)
			var count := 0
			for child: Node in main.threat_parent.get_children():
				if child.get_script() == SessionSnapshot.AIR_STRIKE_MUNITION_SCRIPT and not child.is_queued_for_deletion():
					count += 1
					child.call("_process", 10.0)
			assert_eq(count, 1)
			for tick: int in 4500:
				threat.gameplay_tick(1.0 / 30.0)
				if threat.resolved_state:
					break
		assert_true(threat.resolved_state, "미사일은 충돌 종료, 항공기는 이탈 종료")
		assert_eq(target.integrity, target.definition.maximum_integrity - definition.mission.damage, String(id))
		assert_eq(main.objective.current_integrity, city_before)

func test_lost_cruise_target_keeps_last_site_and_cannot_remote_damage_or_egress() -> void:
	var entry := entry_for(&"battery_strike_cruise")
	var target := target_for(&"weapon")
	main.enemy_knowledge.record_recon(target)
	var threat := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	var old_site := threat.mission_runtime.fixed_target
	target.global_position += Vector3(800, 0, 0)
	assert_eq(threat.mission_runtime.navigation_target(), old_site)
	threat.global_position = old_site + Vector3(100, 35, 0)
	var city_before := main.objective.current_integrity
	for tick: int in 1800:
		threat.gameplay_tick(1.0 / 30.0)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_ne(threat.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_eq(threat.mission_runtime.target_defense_id, 0)
	assert_eq(target.integrity, target.definition.maximum_integrity)
	assert_eq(main.objective.current_integrity, city_before)
	assert_true(main.enemy_knowledge.estimates.is_empty())

func test_missile_can_reach_rooftop_and_skips_a_disabled_asset() -> void:
	var entry := entry_for(&"battery_strike_cruise")
	var target := target_for(&"weapon")
	target.global_position.y += 80.0
	main.enemy_knowledge.record_recon(target)
	var threat := main.director._spawn_entry(entry, 0.5, 0.0) as AttackUav
	for tick: int in 4500:
		threat.gameplay_tick(1.0 / 30.0)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_eq(target.integrity, target.definition.maximum_integrity - 55.0)
	target.receive_damage(30.0)
	var before := target.integrity
	main.enemy_knowledge.record_recon(target)
	var other := main.director._spawn_entry(entry, 0.5, 0.0) as AttackUav
	other.global_position = target.global_position + Vector3(100, 20, 0)
	other.gameplay_tick(0.1)
	assert_eq(other.mission_runtime.target_defense_id, 0)
	assert_eq(target.integrity, before)

func test_lost_missile_reference_and_aircraft_missions_round_trip() -> void:
	for id: StringName in IDS:
		var entry := entry_for(id)
		var target := target_for(entry.threat_definition.adaptive_knowledge_role)
		main.enemy_knowledge.reset()
		main.enemy_knowledge.record_recon(target)
		var threat := main.director._spawn_entry(entry, 0.5, 0.0) as AttackUav
		var runtime_id := threat.runtime_id
		if threat.mission_runtime.profile.type == ThreatMissionDefinition.Type.IMPACT:
			var site := threat.mission_runtime.fixed_target
			target.global_position += Vector3(900, 0, 0)
			threat.global_position = site + Vector3.UP * 60.0
			threat.gameplay_tick(0.01)
		var state := threat.capture_content_state()
		var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
		assert_eq(main.restore_from_document(document), "")
		var restored: AttackUav
		for child: Node in main.threat_parent.get_children():
			if child is AttackUav and child.runtime_id == runtime_id:
				restored = child as AttackUav
		assert_not_null(restored)
		if restored != null:
			assert_eq(restored.capture_content_state().mission, state.mission)
