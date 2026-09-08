extends GutTest

const IDS: Array[StringName] = [&"battery_strike_cruise", &"support_strike_cruise", &"battery_strike_aircraft", &"radar_strike_aircraft", &"command_strike_aircraft"]
var main: AirscainMain

class RetiringThreat:
	extends ThreatUnit

	func exits_without_impact() -> bool:
		return true

func before_each() -> void:
	AirscainMain.requested_seed = 73129
	main = add_child_autofree(load("res://main/main.tscn").instantiate()) as AirscainMain
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	main.set_process(false)
	main.session.budget = 10000
	await get_tree().process_frame

func test_flight_rules_run_without_scene_visuals_and_restore_continuously() -> void:
	var original := StrikeFlight.new()
	original.mode = StrikeFlight.Mode.BOMB
	original.velocity = Vector3(40, 0, 0)
	var position := Vector3(0, 100, 0)
	var target := Vector3(180, 0, 0)
	position = original.advance(position, target, null, 0.25)
	var restored := StrikeFlight.new()
	restored.restore_state(original.capture_state())
	for tick: int in 60:
		var expected := original.advance(position, target, null, StrikeFlight.MAXIMUM_STEP)
		var actual := restored.advance(position, target, null, StrikeFlight.MAXIMUM_STEP)
		assert_eq(actual, expected)
		assert_eq(restored.velocity, original.velocity)
		position = expected
	assert_false(original.powered())
	assert_lt(original.velocity.y, 0.0)

func test_payload_damage_is_independent_of_visuals_and_idempotent() -> void:
	var target := target_for(&"weapon")
	var payload := StrikePayload.new()
	payload.setup(main.objective, 30, target, false)
	var city_before := main.objective.current_integrity
	payload.apply_impact(target.global_position)
	payload.apply_impact(target.global_position)
	assert_eq(target.integrity, 70.0)
	assert_eq(main.objective.current_integrity, city_before)
	payload.setup(main.objective, 30, target, false)
	payload.apply_impact(target.global_position + Vector3(1000, 0, 0))
	assert_eq(target.integrity, 70.0)

func test_resolution_policy_is_independent_of_sensor_classification() -> void:
	var aircraft := entry_for(&"battery_strike_aircraft").threat_definition.duplicate(true) as ThreatDefinition
	assert_true(aircraft.resolution_profile.leave_wreck)
	assert_true(aircraft.has_resolution_explosion())
	aircraft.signature_class = &"bird"
	assert_true(aircraft.has_resolution_explosion(), "센서 분류 변경은 파괴 연출을 변경하지 않습니다")
	var bird := main.scenario.ambient_contacts[0].duplicate(true) as ThreatDefinition
	bird.signature_class = &"aircraft"
	assert_false(bird.has_resolution_explosion())
	assert_false(bird.resolution_profile.wreck_smoke)
	assert_false(bird.resolution_profile.landing_flash)
	assert_eq(bird.validation_error(), "")
	assert_eq(aircraft.validation_error(), "")

func test_root_accepts_impact_free_retirement_without_concrete_aircraft_type() -> void:
	var threat := RetiringThreat.new()
	main.threat_parent.add_child(threat)
	threat.setup(801, entry_for(&"battery_strike_aircraft").threat_definition)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var effects_before := main.effects_parent.get_child_count()
	threat.resolve_once(false)
	assert_false(main.registry.get_active().has(threat))
	assert_eq(main.effects_parent.get_child_count(), effects_before)

func entry_for(id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	return null

func launch_at(target: DefenseUnit) -> Array[ThreatUnit]:
	main.enemy_knowledge.record_recon(target)
	var aircraft := main.director._spawn_entry(entry_for(&"battery_strike_aircraft"), 0.5, 0.0) as AttackUav
	for tick: int in 4500:
		aircraft.gameplay_tick(1.0 / 30.0)
		if aircraft.mission_runtime.effect_applied:
			break
	for threat: ThreatUnit in main.registry.get_active():
		if threat.definition == aircraft.mission_runtime.profile.released_missile:
			return [aircraft, threat]
	fail_test("공대지 미사일이 등록되지 않았습니다")
	return []

func test_missile_separates_accelerates_and_survives_carrier_destruction() -> void:
	var target := target_for(&"weapon")
	var pair := launch_at(target)
	assert_eq(pair.size(), 2)
	if pair.size() != 2:
		return
	var aircraft := pair[0] as AttackUav
	var missile := pair[1]
	assert_false(aircraft.body.get_node("ReleasedStore").visible)
	assert_gt(aircraft.global_position.distance_to(target.global_position), 400.0, "외곽에서 투발합니다")
	assert_gt(missile.global_position.distance_to(aircraft.global_position), 1.0, "기체 중심이 아닌 날개 아래에서 분리합니다")
	assert_almost_eq(missile.presentation_velocity(), aircraft.presentation_velocity(), Vector3.ONE * 0.001)
	assert_false(missile.get_node("Flight/Flame").visible)
	var initial_speed := missile.presentation_velocity().length()
	aircraft.receive_damage(10000.0)
	assert_true(missile.is_targetable())
	missile.gameplay_tick(0.1)
	assert_false(missile.get_node("Flight/Flame").visible)
	missile.gameplay_tick(0.2)
	assert_true(missile.get_node("Flight/Flame").visible)
	assert_gt(missile.presentation_velocity().length(), initial_speed)
	for tick: int in 600:
		missile.gameplay_tick(1.0 / 120.0)
		if missile.resolved_state:
			break
	assert_true(missile.resolved_state, "투발 후 수 초 안에 탄착합니다")
	assert_eq(target.integrity, 50.0, "impact=%s target=%s flight=%s" % [missile.global_position, target.global_position, missile.capture_content_state()])
	missile.gameplay_tick(10.0)
	assert_eq(target.integrity, 50.0)

func test_radar_observes_released_missile_and_gun_round_cancels_impact() -> void:
	var target := target_for(&"weapon")
	var pair := launch_at(target)
	if pair.size() != 2:
		return
	var missile := pair[1]
	missile.gameplay_tick(0.4)
	var radar := target_for(&"sensor") as SearchRadar
	radar.global_position = missile.global_position - Vector3(40, 20, 0)
	var tracks_before: Array = main.player_knowledge.call("get_active_tracks")
	radar._scan()
	var tracks_after: Array = main.player_knowledge.call("get_active_tracks")
	assert_gt(tracks_after.size(), tracks_before.size(), "별도 레이더 관측 대상입니다")
	var gunfire := add_child_autofree(GunfireRuntime.new()) as GunfireRuntime
	gunfire.registry = main.registry
	gunfire.rounds.append({"position": missile.global_position - Vector3(1, 0, 0), "velocity": Vector3(100, 0, 0), "age": 0.05, "lifetime": 1.0, "damage": 30.0, "radius": 4.0, "emitted": true})
	gunfire.gameplay_tick(0.02)
	assert_true(missile.resolved_state, "기관포의 실제 근접신관 충돌 경로로 격추합니다")
	assert_false(main.registry.get_active().has(missile))
	missile.gameplay_tick(10.0)
	assert_eq(target.integrity, target.definition.maximum_integrity, "격추된 탄은 피해를 주지 않습니다")

func test_bomb_is_unpowered_ballistic_unregistered_and_restores_mid_fall() -> void:
	var target := target_for(&"weapon")
	main.enemy_knowledge.record_recon(target)
	var aircraft := main.director._spawn_entry(entry_for(&"battery_strike_uav"), 0.5, 0.0) as AttackUav
	for tick: int in 4500:
		aircraft.gameplay_tick(1.0 / 30.0)
		if aircraft.mission_runtime.effect_applied:
			break
	var bomb: Node3D
	for child: Node in main.threat_parent.get_children():
		if child.get_script() == SessionSnapshot.AIR_STRIKE_MUNITION_SCRIPT:
			bomb = child as Node3D
	assert_not_null(bomb)
	if bomb == null:
		return
	assert_false(bomb is ThreatUnit, "폭탄은 요격 목록에 등록하지 않습니다")
	assert_false(bomb.get_node("Flame").visible)
	assert_false(bomb.get_node("FlameLight").visible)
	assert_false(aircraft.body.get_node("ReleasedStore").visible)
	var initial_velocity := (bomb as AirStrikeMunition).motion.velocity
	var initial_position := bomb.global_position
	aircraft.receive_damage(10000.0)
	await get_tree().process_frame
	assert_eq(bomb.global_position, initial_position, "정지한 시뮬레이션에서 폭탄만 진행하지 않습니다")
	bomb.call("_process", 0.3)
	var velocity := (bomb as AirStrikeMunition).motion.velocity
	assert_almost_eq(velocity.x, initial_velocity.x, 0.001)
	assert_almost_eq(velocity.z, initial_velocity.z, 0.001)
	assert_almost_eq(velocity.y, initial_velocity.y - 9.8 * 0.3, 0.001)
	var before: Dictionary = bomb.call("capture_state")
	var target_id := target.runtime_id
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	for child: Node in main.threat_parent.get_children():
		if child.get_script() == SessionSnapshot.AIR_STRIKE_MUNITION_SCRIPT and not child.is_queued_for_deletion():
			bomb = child as Node3D
	for asset: DefenseUnit in main.defenses:
		if asset.runtime_id == target_id:
			target = asset
	assert_eq(bomb.call("capture_state"), before)
	assert_false(bomb.get_node("Flame").visible)
	bomb.call("_process", 10.0)
	assert_eq(target.integrity, 60.0)

func test_uav_bombs_hit_small_assets_from_multiple_approach_directions() -> void:
	for definition_index: int in [0, 4, 6]:
		var target := target_for_index(definition_index)
		for case: int in 8:
			var angle := float(case % 4) * 1.5
			var time_step := 1.0 / 30.0 if case < 4 else 0.1
			target.complete_repair()
			var definition := entry_for(&"battery_strike_uav").threat_definition
			var aircraft := definition.scene.instantiate() as AttackUav
			main.threat_parent.add_child(aircraft)
			aircraft.setup(9000, definition)
			aircraft.global_position = target.global_position + Vector3(cos(angle) * 450.0, 180.0, sin(angle) * 450.0)
			aircraft.configure_mission(main.objective, main.battlefield, target.global_position, 1.0 if case < 4 else 1.35, target, aircraft.global_position)
			for tick: int in 4500:
				aircraft.gameplay_tick(time_step)
				if aircraft.mission_runtime.effect_applied:
					break
			var bomb: AirStrikeMunition
			for child: Node in main.threat_parent.get_children():
				if child is AirStrikeMunition and not child.is_queued_for_deletion():
					bomb = child as AirStrikeMunition
			assert_not_null(bomb, "Bomb release: %d / %.1f" % [definition_index, angle])
			if bomb != null:
				bomb.managed = true
				bomb.gameplay_tick(15.0)
				assert_lt(target.integrity, target.definition.maximum_integrity, "asset=%s angle=%.1f miss=%.3f impact=%s target=%s" % [target.definition.id, angle, bomb.global_position.distance_to(target.global_position), bomb.global_position, target.global_position])
				bomb.free()
			aircraft.free()

func test_missile_flight_round_trips_before_and_after_ignition() -> void:
	var target := target_for(&"weapon")
	var pair := launch_at(target)
	if pair.size() != 2:
		return
	var missile := pair[1]
	var id := missile.runtime_id
	missile.receive_damage(3.0)
	for advance: float in [0.1, 0.3]:
		missile.gameplay_tick(advance)
		var before := missile.capture_state()
		var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
		assert_eq(main.restore_from_document(document), "")
		for candidate: ThreatUnit in main.registry.get_active():
			if candidate.runtime_id == id:
				missile = candidate
		var after := missile.capture_state()
		for key: String in before:
			if key == "content_state":
				for field: String in before.content_state:
					if field == "elapsed":
						assert_almost_eq(float(after.content_state[field]), float(before.content_state[field]), 0.000001)
					else:
						assert_eq(after.content_state[field], before.content_state[field], field)
			else:
				assert_eq(after[key], before[key], key)
		assert_eq(missile.health, 21.0)
		var invalid := document.duplicate(true)
		for state: Dictionary in invalid.payload.world.contacts:
			if int(state.runtime_id) == id:
				state.content_state.velocity = [NAN, 0, 0]
		assert_ne(main.restore_from_document(invalid), "")

func test_release_alignment_rejects_sideways_and_backward_missile_shots() -> void:
	var target := target_for(&"weapon")
	main.enemy_knowledge.record_recon(target)
	var aircraft := main.director._spawn_entry(entry_for(&"battery_strike_aircraft"), 0.0, 0.0) as AttackUav
	aircraft.global_position = target.global_position + Vector3(300, 100, 0)
	aircraft.mover.velocity = Vector3(100, 0, 0)
	assert_false(AircraftStrikeRelease.ready(aircraft.mission_runtime.profile, aircraft.body.global_transform, target.global_position, aircraft.mover.velocity, 0.03))
	aircraft.mover.velocity = Vector3(0, 0, 100)
	assert_false(AircraftStrikeRelease.ready(aircraft.mission_runtime.profile, aircraft.body.global_transform, target.global_position, aircraft.mover.velocity, 0.03))
	aircraft.mover.velocity = Vector3(-100, 0, 0)
	assert_true(AircraftStrikeRelease.ready(aircraft.mission_runtime.profile, aircraft.body.global_transform, target.global_position, aircraft.mover.velocity, 0.03))

func target_for(role: StringName) -> DefenseUnit:
	var index := {&"weapon": 0, &"sensor": 1, &"command": 2, &"support": 5}[role] as int
	return target_for_index(index)

func target_for_index(index: int) -> DefenseUnit:
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
				if child is ThreatUnit and (child as ThreatUnit).definition == definition.mission.released_missile and not child.is_queued_for_deletion():
					count += 1
					(child as ThreatUnit).gameplay_tick(10.0)
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

func test_jet_approach_cue_tracks_actual_release_and_restore() -> void:
	main.combat_audio.enabled = true
	main.combat_audio.set_process(false)
	var aircraft := main.director._spawn_entry(entry_for(&"strike_aircraft"), 0.0, 0.0) as AttackUav
	assert_not_null(aircraft)
	var audio := main.combat_audio.approaches
	var start_time := -1.0
	var start_position := 0.0
	var released_at := -1.0
	for tick: int in 1800:
		var time := float(tick) / 60.0
		aircraft.gameplay_tick(1.0 / 60.0)
		audio.update_audio(1.0 / 60.0, false, 1.0, true)
		if start_time < 0.0 and audio.played_count > 0:
			start_time = time
			start_position = audio.voices[0].player.get_playback_position()
		if aircraft.mission_runtime.effect_applied:
			released_at = time
			break
	assert_gte(start_time, 0.0)
	assert_gt(released_at, start_time)
	assert_almost_eq(released_at - start_time + start_position, ThreatApproachAudio.PEAK_SECONDS, 0.75, "투발이 음원 최근접 구간에 맞습니다")
	assert_eq(audio.played_count, 1)
	assert_true(audio.voices[0].player.playing)
	var saved := aircraft.capture_state()
	audio.reset()
	aircraft.restore_state(saved, main.objective, main.battlefield)
	audio.register(aircraft)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 1, "투발 후 저장 복원은 접근음을 재시작하지 않습니다")
