extends GutTest

const IDS: Array[StringName] = [&"battery_strike_cruise", &"support_strike_cruise", &"battery_strike_aircraft", &"radar_strike_aircraft", &"command_strike_aircraft"]
var main: AirscainMain
var original_requested_seed: int
var original_requested_mode: AirscainMain.GameMode

class RetiringThreat:
	extends ThreatUnit

	func exits_without_impact() -> bool:
		return true

func before_each() -> void:
	original_requested_seed = AirscainMain.requested_seed
	original_requested_mode = AirscainMain.requested_mode
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	main = add_child_autofree(load("res://main/main.tscn").instantiate()) as AirscainMain
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	main.set_process(false)
	main.session.budget = 10000
	await get_tree().process_frame

func after_each() -> void:
	AirscainMain.requested_seed = original_requested_seed
	AirscainMain.requested_mode = original_requested_mode

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
	var bird := ambient_definition_for(&"bird_contact").duplicate(true) as ThreatDefinition
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
	main.director.threat_spawned.emit(threat)
	var effects_before := main.effects_parent.get_child_count()
	threat.resolve_once(false)
	assert_false(main.registry.get_active().has(threat))
	assert_eq(main.effects_parent.get_child_count(), effects_before)

func entry_for(id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	fail_test("위협 생성 항목을 찾지 못했습니다: %s" % id)
	return null

func _spawn_entry_for(id: StringName, angle: float = 0.0, edge_offset: float = 0.0) -> ThreatUnit:
	var entry := entry_for(id)
	if entry == null:
		return null
	return main.director._spawn_entry(entry, angle, edge_offset)

func ambient_definition_for(id: StringName) -> ThreatDefinition:
	for definition: ThreatDefinition in main.scenario.ambient_contacts:
		if definition.id == id:
			return definition
	fail_test("주변 접촉 정의를 찾지 못했습니다: %s" % id)
	return null

func defense_definition_for(id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id == id:
			return definition
	fail_test("방어 자산 정의를 찾지 못했습니다: %s" % id)
	return null

func launch_at(target: DefenseUnit) -> Array[ThreatUnit]:
	main.enemy_knowledge.record_recon(target)
	var aircraft := _spawn_entry_for(&"battery_strike_aircraft", 0.5) as AttackUav
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
	var release_offset := missile.global_position - aircraft.mission_runtime.fixed_target
	var release_distance := Vector2(release_offset.x, release_offset.z).length()
	assert_lte(release_distance, aircraft.mission_runtime.profile.action_distance, "설정된 수평 발사 거리 안에서 투발합니다")
	assert_gt(release_distance, target.definition.placement_profile.footprint_radius, "표적에 닿기 전에 무장을 분리합니다")
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
	var tracks_before := main.player_knowledge.get_active_tracks()
	radar._scan()
	var tracks_after := main.player_knowledge.get_active_tracks()
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
	var aircraft := _spawn_entry_for(&"battery_strike_uav", 0.5) as AttackUav
	for tick: int in 4500:
		aircraft.gameplay_tick(1.0 / 30.0)
		if aircraft.mission_runtime.effect_applied:
			break
	var bomb: AirStrikeMunition
	for child: Node in main.threat_parent.get_children():
		if child is AirStrikeMunition:
			bomb = child as AirStrikeMunition
	assert_not_null(bomb)
	if bomb == null:
		return
	assert_false(main.registry.get_active().any(func(contact: ThreatUnit) -> bool: return contact.get_instance_id() == bomb.get_instance_id()), "폭탄은 요격 목록에 등록하지 않습니다")
	assert_false(bomb.get_node("Flame").visible)
	assert_false(bomb.get_node("FlameLight").visible)
	assert_false(aircraft.body.get_node("ReleasedStore").visible)
	var initial_velocity := bomb.motion.velocity
	var initial_position := bomb.global_position
	aircraft.receive_damage(10000.0)
	await get_tree().process_frame
	assert_eq(bomb.global_position, initial_position, "정지한 시뮬레이션에서 폭탄만 진행하지 않습니다")
	bomb.gameplay_tick(0.3)
	var velocity := bomb.motion.velocity
	assert_almost_eq(velocity.x, initial_velocity.x, 0.001)
	assert_almost_eq(velocity.z, initial_velocity.z, 0.001)
	assert_almost_eq(velocity.y, initial_velocity.y - 9.8 * 0.3, 0.001)
	var before := bomb.capture_state()
	var target_id := target.runtime_id
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	for child: Node in main.threat_parent.get_children():
		if child is AirStrikeMunition and not child.is_queued_for_deletion():
			bomb = child as AirStrikeMunition
	for asset: DefenseUnit in main.defenses:
		if asset.runtime_id == target_id:
			target = asset
	assert_eq(bomb.capture_state(), before)
	assert_false(bomb.get_node("Flame").visible)
	bomb.gameplay_tick(10.0)
	assert_eq(target.integrity, 60.0)

func test_uav_bombs_hit_small_assets_from_multiple_approach_directions() -> void:
	for definition_id: StringName in [&"missile_battery", &"close_in_gun", &"high_energy_laser"]:
		var target := target_for_definition(definition_id)
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
			assert_not_null(bomb, "Bomb release: %s / %.1f" % [definition_id, angle])
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
	var aircraft := _spawn_entry_for(&"battery_strike_aircraft") as AttackUav
	aircraft.global_position = target.global_position + Vector3(300, 100, 0)
	aircraft.mover.velocity = Vector3(100, 0, 0)
	assert_false(AircraftStrikeRelease.ready(aircraft.mission_runtime.profile, aircraft.body.global_transform, target.global_position, aircraft.mover.velocity, 0.03))
	aircraft.mover.velocity = Vector3(0, 0, 100)
	assert_false(AircraftStrikeRelease.ready(aircraft.mission_runtime.profile, aircraft.body.global_transform, target.global_position, aircraft.mover.velocity, 0.03))
	aircraft.mover.velocity = Vector3(-100, 0, 0)
	assert_true(AircraftStrikeRelease.ready(aircraft.mission_runtime.profile, aircraft.body.global_transform, target.global_position, aircraft.mover.velocity, 0.03))

func target_for(role: StringName) -> DefenseUnit:
	var definition_ids: Dictionary[StringName, StringName] = {
		&"weapon": &"missile_battery",
		&"sensor": &"search_radar",
		&"command": &"command_post",
		&"support": &"support_facility",
	}
	assert_true(definition_ids.has(role), "알 수 없는 시설 역할: %s" % role)
	return target_for_definition(definition_ids.get(role, &""))

func target_for_definition(definition_id: StringName) -> DefenseUnit:
	var definition := defense_definition_for(definition_id)
	main.director.pressure_changed.emit(definition.unlock_pressure_level)
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
		var case_context := "시설 공격 변형 %s" % id
		main.enemy_knowledge.reset()
		var entry := entry_for(id)
		assert_not_null(entry, case_context)
		assert_eq(entry.validation_error(), "", case_context)
		assert_eq(main.director.adaptive_entry_weight(entry), 0.0, "%s: 사전 정찰 전" % case_context)
		var target := target_for(entry.threat_definition.adaptive_knowledge_role)
		main.enemy_knowledge.record_recon(target)
		assert_gt(main.director.adaptive_entry_weight(entry), 0.0, "%s: 사전 정찰 후" % case_context)
		assert_has(main._sandbox_threat_definitions(), entry.threat_definition, case_context)
		var city := entry_for(&"strike_aircraft")
		var weights: Dictionary[StringName, float] = {id: 1.0, city.threat_definition.id: 1.0}
		var planner := RaidPlanner.new()
		var included := false
		for sample: int in 32:
			var waves := planner.generate(main.scenario, weights, entry.threat_cost + city.threat_cost, maxi(entry.unlock_level, city.unlock_level), 0.0, 32.0, 1.0, rng)
			var has_city := false
			for wave: Dictionary in waves:
				included = included or StringName(wave.definition_id) == id
				has_city = has_city or StringName(wave.definition_id) == city.threat_definition.id
			assert_true(has_city, "%s sample=%d: 시설 제압만으로 도시 공격을 대체하지 않습니다" % [case_context, sample])
		assert_true(included, "%s: 32회 표본 안에 변형이 포함됩니다" % case_context)

func test_each_variant_flies_to_its_role_and_applies_only_one_asset_hit() -> void:
	for id: StringName in IDS:
		var case_context := "시설 공격 변형 %s" % id
		main.enemy_knowledge.reset()
		var entry := entry_for(id)
		var definition := entry.threat_definition as AttackUavDefinition
		var target := target_for(definition.adaptive_knowledge_role)
		main.enemy_knowledge.record_recon(target)
		var city_before := main.objective.current_integrity
		var threat := _spawn_entry_for(id, 0.5) as AttackUav
		for tick: int in 4500:
			threat.gameplay_tick(1.0 / 30.0)
			if threat.mission_runtime.effect_applied or threat.resolved_state:
				break
		assert_true(threat.mission_runtime.effect_applied, "%s impact=%s target=%s mission=%s" % [id, threat.global_position, target.global_position, threat.mission_runtime.capture_state()])
		if definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
			assert_eq(target.integrity, target.definition.maximum_integrity, "%s: 투발 전에는 시설 피해가 없습니다" % case_context)
			var count := 0
			for child: Node in main.threat_parent.get_children():
				if child is ThreatUnit and (child as ThreatUnit).definition == definition.mission.released_missile and not child.is_queued_for_deletion():
					count += 1
					(child as ThreatUnit).gameplay_tick(10.0)
			assert_eq(count, 1, "%s: 투사체를 한 발만 방출합니다" % case_context)
			for tick: int in 4500:
				threat.gameplay_tick(1.0 / 30.0)
				if threat.resolved_state:
					break
		assert_true(threat.resolved_state, "%s: 미사일은 충돌 종료, 항공기는 이탈 종료" % case_context)
		assert_eq(target.integrity, target.definition.maximum_integrity - definition.mission.damage, case_context)
		assert_eq(main.objective.current_integrity, city_before, "%s: 시설 공격은 도시에 피해를 주지 않습니다" % case_context)

func test_lost_cruise_target_keeps_last_site_and_cannot_remote_damage_or_egress() -> void:
	var entry := entry_for(&"battery_strike_cruise")
	var target := target_for(&"weapon")
	main.enemy_knowledge.record_recon(target)
	var threat := _spawn_entry_for(entry.threat_definition.id) as AttackUav
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
	var threat := _spawn_entry_for(entry.threat_definition.id, 0.5) as AttackUav
	for tick: int in 4500:
		threat.gameplay_tick(1.0 / 30.0)
		if threat.resolved_state:
			break
	assert_true(threat.resolved_state)
	assert_eq(target.integrity, target.definition.maximum_integrity - 55.0)
	target.receive_damage(30.0)
	var before := target.integrity
	main.enemy_knowledge.record_recon(target)
	var other := _spawn_entry_for(entry.threat_definition.id, 0.5) as AttackUav
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
		var threat := _spawn_entry_for(id, 0.5) as AttackUav
		var runtime_id := threat.runtime_id
		if threat.mission_runtime.profile.type == ThreatMissionDefinition.Type.IMPACT:
			var site := threat.mission_runtime.fixed_target
			target.global_position += Vector3(900, 0, 0)
			threat.global_position = site + Vector3.UP * 60.0
			threat.gameplay_tick(0.01)
		var state := threat.capture_content_state()
		var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
		assert_eq(main.restore_from_document(document), "", "%s: 저장 문서를 복원합니다" % id)
		var restored: AttackUav
		for child: Node in main.threat_parent.get_children():
			if child is AttackUav and child.runtime_id == runtime_id:
				restored = child as AttackUav
		assert_not_null(restored, "%s: 같은 runtime ID의 위협을 복원합니다" % id)
		if restored != null:
			assert_eq(restored.capture_content_state().mission, state.mission, "%s: 임무 상태를 보존합니다" % id)

func test_jet_approach_cue_tracks_actual_release_and_restore() -> void:
	main.combat_audio.enabled = true
	main.combat_audio.set_process(false)
	var aircraft := _spawn_entry_for(&"strike_aircraft") as AttackUav
	assert_not_null(aircraft)
	var audio := main.combat_audio.approaches
	var start_time := -1.0
	var start_position := 0.0
	var released_at := -1.0
	for tick: int in 7200:
		var time := float(tick) / 60.0
		aircraft.gameplay_tick(1.0 / 60.0)
		audio.update_audio(1.0 / 60.0, false, 1.0, true)
		if start_time < 0.0 and audio.played_count > 0:
			start_time = time
			start_position = audio.voices[0].player.get_playback_position()
			assert_lt(start_position, 0.1, "자동 생성한 타격기는 접근음 첫 부분부터 재생합니다")
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

func test_all_automatic_threat_groups_start_beyond_haze() -> void:
	main.director.elapsed = 3600.0
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var case_context := "id=%s angle=%.2f" % [entry.threat_definition.id, angle]
			var threat := _spawn_entry_for(entry.threat_definition.id, angle, float(entry.group_size - 1) * 3.0)
			assert_gt(Vector2(threat.global_position.x, threat.global_position.z).length(), main.scenario.battlefield_size * DistantContactHaze.END_RATIO, case_context)
			assert_eq(DistantContactHaze.opacity_at(threat.global_position, main.scenario.battlefield_size), 0.0, case_context)
			var eta := threat.presentation_action_seconds()
			if is_finite(eta):
				assert_gt(eta, ThreatApproachAudio.PEAK_SECONDS, case_context)
			main.registry.remove(threat)
			threat.free()

func test_cruise_approach_precedes_actual_collision() -> void:
	var entry: ThreatSpawnEntry
	for candidate: ThreatSpawnEntry in main.scenario.threat_entries:
		if candidate.threat_definition.id == &"cruise_missile":
			entry = candidate
	var missile := _spawn_entry_for(entry.threat_definition.id) as AttackUav
	var audio := ThreatApproachAudio.new()
	audio.configure_cruise()
	add_child_autofree(audio)
	audio.register(missile)
	var started_at := -1.0
	var ended_at := -1.0
	for tick: int in 2500:
		missile.gameplay_tick(0.05)
		audio.update_audio(0.05, false, 1.0, true)
		if audio.played_count > 0 and started_at < 0.0:
			started_at = tick * 0.05
		if missile.resolved_state:
			ended_at = tick * 0.05
			break
	assert_gt(started_at, 0.0)
	assert_gt(ended_at, started_at)
	assert_almost_eq(ended_at - started_at, 5.0, 0.75, "현재 경로의 예상 충돌 약 5초 전 접근음을 시작합니다")
	assert_true(audio.voices[0].retiring)
	audio.update_audio(0.2, false, 1.0, true)
	assert_false(audio.voices[0].player.playing)

func test_uav_loop_content_roles_and_live_release_envelope() -> void:
	for id: StringName in [&"recon_uav", &"electronic_warfare_uav", &"decoy_uav"]:
		assert_eq(entry_for(id).threat_definition.loop_audio_event, &"")
	for id: StringName in [&"attack_uav", &"swarm_uav", &"battery_strike_uav", &"command_strike_uav", &"support_strike_uav"]:
		var definition := entry_for(id).threat_definition as AttackUavDefinition
		var aircraft := definition.scene.instantiate() as AttackUav
		main.threat_parent.add_child(aircraft)
		aircraft.setup(9100, definition)
		var target := target_for(&"weapon")
		aircraft.global_position = target.global_position + Vector3(1600, 120, 0)
		aircraft.configure_mission(main.objective, main.battlefield, target.global_position, 1.0, target, aircraft.global_position)
		var audio := UavLoopAudio.new()
		add_child_autofree(audio)
		audio.register(aircraft)
		var started := -1.0
		var finished := -1.0
		var maximum := 0.0
		for tick: int in 1800:
			aircraft.gameplay_tick(0.05)
			audio.update_audio(0.05, false, 1.0, true)
			for voice: UavLoopAudio.Voice in audio.voices:
				maximum = maxf(maximum, voice.envelope)
				if voice.player.playing and started < 0.0:
					started = tick * 0.05
			if aircraft.resolved_state or aircraft.mission_runtime.effect_applied:
				finished = tick * 0.05
				break
		assert_gt(started, 0.0, String(id))
		assert_gt(finished, started, String(id))
		assert_gt(maximum, 0.65, "접근 중 볼륨이 충분히 상승: " + String(id))
		if definition.mission.type == ThreatMissionDefinition.Type.IMPACT:
			assert_almost_eq(finished - started, float(UavLoopAudio.LEAD_SECONDS[definition.loop_audio_event]), 2.0, "충돌 예상시간 기반 시작: " + String(id))
		if definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
			assert_almost_eq(finished - started, 16.0, 2.0, "투하 예상시간 기반 시작: " + String(id))
			assert_true(audio.voices[0].player.playing, "투하 후 이탈 꼬리")
		for tick: int in 50:
			audio.update_audio(0.05, false, 1.0, true)
		for voice: UavLoopAudio.Voice in audio.voices:
			assert_false(voice.player.playing, String(id))
		aircraft.free()

func test_cruise_audio_does_not_predict_terrain_collision_during_safe_cruise() -> void:
	for content: String in ["anti_radiation_missile/anti_radiation_missile", "cruise_missile/cruise_missile", "cruise_missile/battery_strike_cruise", "cruise_missile/support_strike_cruise"]:
		var definition := load("res://enemy/%s.tres" % content) as AttackUavDefinition
		var missile := definition.scene.instantiate() as AttackUav
		main.add_child(missile)
		missile.setup(9001, definition)
		var position := Vector3(1200.0, 0.0, 0.0)
		position.y = main.battlefield.flight_surface_height(position.x, position.z) + definition.movement.cruise_altitude
		missile.global_position = position
		missile.configure_mission(main.objective, main.battlefield, Vector3.ZERO, 1.0)
		# A descent over terrain is corrected by the cruise clearance controller.
		missile.mover.velocity = Vector3(-definition.movement.speed, -20.0, 0.0)
		var audio := ThreatApproachAudio.new()
		audio.configure_cruise()
		add_child_autofree(audio)
		audio.register(missile)
		audio.update_audio(0.05, false, 1.0, true)
		assert_eq(audio.played_count, 0, content + " must not consume its approach cue far away")
		assert_gt(missile.presentation_action_seconds(), 5.0, content)
		for tick: int in 120:
			missile.gameplay_tick(0.05)
		assert_false(missile.resolved_state, content + " remains in flight after the false projected collision")
		var started_at := -1.0
		var ended_at := -1.0
		for tick: int in 1000:
			missile.gameplay_tick(0.05)
			audio.update_audio(0.05, false, 1.0, true)
			if started_at < 0.0 and audio.played_count > 0:
				started_at = tick * 0.05
			if missile.resolved_state:
				ended_at = tick * 0.05
				break
		assert_gte(started_at, 0.0, content)
		assert_gt(ended_at, started_at, content)
		assert_almost_eq(ended_at - started_at, 5.0, 1.0, content + " cue precedes real impact")
		missile.free()

func test_uav_bombs_confirm_offset_reports_before_release() -> void:
	var target := target_for_definition(&"missile_battery")
	for case: int in 12:
		var angle := float(case % 4) * 1.5
		var time_step := 1.0 / 30.0 if case < 4 else 0.1
		target.complete_repair()
		var definition := entry_for(&"battery_strike_uav").threat_definition
		var aircraft := definition.scene.instantiate() as AttackUav
		main.threat_parent.add_child(aircraft)
		aircraft.setup(9000, definition)
		aircraft.global_position = target.global_position + Vector3(cos(angle) * 450.0, 180.0, sin(angle) * 450.0)
		aircraft.configure_mission(main.objective, main.battlefield, target.global_position + Vector3(26.0, 0.0, 0.0), [1.0, 1.35, 2.0][case / 4], target, aircraft.global_position)
		for tick: int in 4500:
			aircraft.gameplay_tick(time_step)
			if aircraft.mission_runtime.effect_applied:
				break
		var bomb: AirStrikeMunition
		for child: Node in main.threat_parent.get_children():
			if child is AirStrikeMunition and not child.is_queued_for_deletion():
				bomb = child as AirStrikeMunition
		assert_not_null(bomb, "Bomb release: %s / %.1f" % [target.definition.id, angle])
		if bomb != null:
			bomb.managed = true
			bomb.gameplay_tick(15.0)
			assert_lt(target.integrity, target.definition.maximum_integrity, "asset=%s angle=%.1f miss=%.3f impact=%s target=%s" % [target.definition.id, angle, bomb.global_position.distance_to(target.global_position), bomb.global_position, target.global_position])
			bomb.free()
		aircraft.free()

func test_recon_search_routes_ignore_live_asset_layout_and_partition_work() -> void:
	var radar := target_for(&"sensor")
	var battery := target_for(&"weapon")
	var entry := entry_for(&"recon_uav")
	main.enemy_knowledge.reset()
	var first := _spawn_entry_for(entry.threat_definition.id) as AttackUav
	var route := first.mission_runtime.fixed_target
	assert_null(first.mission_runtime.target_asset)
	var second := _spawn_entry_for(entry.threat_definition.id) as AttackUav
	assert_ne(second.mission_runtime.fixed_target, route)
	first.resolve_once(true)
	second.resolve_once(true)
	radar.global_position += Vector3(900, 0, 0)
	battery.global_position += Vector3(-700, 0, 0)
	main.enemy_knowledge.reset()
	var moved := _spawn_entry_for(entry.threat_definition.id) as AttackUav
	assert_eq(moved.mission_runtime.fixed_target, route, "미관측 자산 이동은 정찰 경로를 바꾸지 않습니다")

func test_search_flight_changes_sectors_then_releases_its_reservation() -> void:
	var recon := _spawn_entry_for(&"recon_uav") as AttackUav
	recon.global_position = Vector3(900, 145, 180)
	var visited: Dictionary[int, bool] = {}
	for tick: int in 7000:
		main.enemy_knowledge.gameplay_tick(0.05)
		recon.gameplay_tick(0.05)
		if main.enemy_knowledge.search.assignments.has(recon.runtime_id):
			visited[main.enemy_knowledge.search.assignments[recon.runtime_id]] = true
		if recon.mission_runtime.phase == ThreatMissionRuntime.Phase.EGRESS:
			break
	assert_eq(recon.reconnaissance.completed_sectors, ReconnaissanceFlight.MAX_SECTORS)
	assert_gte(visited.size(), 4, "구역을 바꾸며 탐색하고 같은 위치만 반복하지 않습니다")
	assert_gt(main.enemy_knowledge.search.seen.size(), 0)
	assert_false(main.enemy_knowledge.search.assignments.has(recon.runtime_id))
	assert_true(recon.mission_runtime.effect_applied)
