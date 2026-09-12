extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

class ValidatingDefenseDefinition:
	extends DefenseDefinition

	func runtime_state_validation_error(_content_state: Dictionary) -> String:
		return "테스트 방어 상태 오류"

class ValidatingThreatDefinition:
	extends ThreatDefinition

	func runtime_state_validation_error(_content_state: Dictionary, _defense_ids: Dictionary[int, bool]) -> String:
		return "테스트 위협 상태 오류"

class RestoringDefense:
	extends DefenseUnit

	var restored_states: Array[Dictionary] = []
	var restored_target: PlayerTrack

	func restore_projectile(state: Dictionary, target: PlayerTrack, _tracks: Array[PlayerTrack]) -> void:
		restored_states.append(state)
		restored_target = target

var main: AirscainMain
var save_path: String
var original_requested_seed: int
var original_requested_mode: AirscainMain.GameMode

func before_each() -> void:
	original_requested_seed = AirscainMain.requested_seed
	original_requested_mode = AirscainMain.requested_mode
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	main = MAIN_SCENE.instantiate() as AirscainMain
	main.auto_start_sustained = false
	add_child_autofree(main)
	await get_tree().process_frame
	save_path = "user://main_save_restore_test_%d.json" % get_instance_id()
	main.save_path = save_path
	_cleanup_save_files()

func after_each() -> void:
	_cleanup_save_files()
	AirscainMain.requested_seed = original_requested_seed
	AirscainMain.requested_mode = original_requested_mode

func test_projectile_reconstruction_delegates_new_weapon_types_to_the_owner() -> void:
	var owner := RestoringDefense.new()
	add_child_autofree(owner)
	var reconstruction := WorldReconstruction.new(main.battlefield, main.objective, main.registry, main.defense_parent, main.threat_parent, main.projectile_parent)
	reconstruction.defenses_by_id[901] = owner
	var state := {"type": "custom_weapon", "owner_defense_id": 901, "target_track_id": 0}
	reconstruction.restore_projectiles([state], main.player_knowledge)
	assert_eq(owner.restored_states, [state])
	assert_null(owner.restored_target, "Lost tracks remain null instead of being replaced with hidden world targets")

func test_procedural_raid_history_and_rng_restore_the_same_next_attack() -> void:
	main.director.elapsed = 240.0
	main.director.pressure_level = 12
	main.director.launch_budgeted_raid()
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var pending: Array = document.payload.director.pending_waves.duplicate(true)
	main.director.pending_waves.clear()
	main.director.launch_budgeted_raid()
	var expected := main.director.capture_state()
	assert_eq(main.restore_from_document(document), "")
	assert_eq(main.director.pending_waves, pending)
	main.director.pending_waves.clear()
	main.director.launch_budgeted_raid()
	assert_eq(main.director.capture_state(), expected)
	var invalid := document.duplicate(true)
	invalid.payload.director.last_raid_pattern = "missing_pattern"
	assert_ne(main.restore_from_document(invalid), "")
	assert_eq(main.director.capture_state(), expected, "잘못된 이력은 현재 작전을 변경하지 않습니다")
	var legacy := document.duplicate(true)
	legacy.version = 21
	legacy.payload.director.erase("last_raid_pattern")
	assert_eq(main.restore_from_document(legacy), "")
	assert_eq(main.director.raid_planner.last_pattern, &"")
	assert_eq(main.director.pending_waves, pending)
	assert_false(legacy.payload.director.has("last_raid_pattern"))

func test_disabled_battery_and_pending_repair_survive_document_restore() -> void:
	var battery := _place_defense(_defense_definition(&"missile_battery")) as MissileBattery
	var facility := _place_defense(_defense_definition(&"support_facility"))
	facility.global_position = battery.global_position
	battery.set_automatic_resupply(false)
	battery.set_hold_fire(true)
	battery.set_target_kind_allowed(&"uav", false)
	battery.magazine.rounds = 1
	battery.magazine.reserve = 3
	battery.receive_damage(50.0)
	assert_true(battery.request_repair())
	battery.receive_damage(1000.0)
	var id := battery.runtime_id
	var facility_id := facility.runtime_id
	var budget := main.session.budget
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var invalid := document.duplicate(true)
	invalid.payload.world.support.tasks[0].repair_amount = INF
	assert_ne(main.restore_from_document(invalid), "")
	var legacy := document.duplicate(true)
	legacy.version = 24
	legacy.payload.world.support.tasks[0].erase("repair_amount")
	var migrated := SessionSnapshot.migrate_content(legacy.payload, 24, main.scenario)
	assert_eq(float(migrated.world.support.tasks[0].repair_amount), battery.definition.maximum_integrity)
	assert_false(legacy.payload.world.support.tasks[0].has("repair_amount"))
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(id) as MissileBattery
	var restored_facility := _find_defense(facility_id)
	assert_eq(restored.integrity, 0.0)
	assert_false(restored.active)
	assert_eq(main.hud._asset_state_text(restored), "기능 정지")
	assert_eq(main.support_manager.task_status(restored), "수리 진행")
	var remaining := float(main.support_manager.tasks[0].remaining_work)
	restored_facility.receive_damage(1000.0)
	main.support_manager.gameplay_tick(100.0)
	assert_eq(main.support_manager.task_status(restored), "수리 대기")
	assert_eq(float(main.support_manager.tasks[0].remaining_work), remaining)
	assert_false(restored.active)
	restored_facility.complete_repair()
	main.support_manager.gameplay_tick(100.0)
	assert_true(restored.active)
	assert_eq(restored.integrity, 50.0, "수리 요청 뒤 추가 피해는 결제된 복구량에 포함되지 않는다")
	assert_true(restored.can_request_repair())
	assert_eq(restored.magazine.rounds, 1)
	assert_eq(restored.magazine.reserve, 3)
	assert_true(restored.doctrine.hold_fire)
	assert_false(restored.allows_target_kind(&"uav"))
	assert_true(restored.allows_target_kind(&"rocket"))
	assert_false(restored.automatic_resupply_enabled())
	assert_eq(main.session.budget, budget)

func test_resupply_order_and_fractional_credit_survive_document_restore() -> void:
	var gun := _place_defense(_defense_definition(&"close_in_gun")) as CloseInGun
	var facility := _place_defense(_defense_definition(&"support_facility"))
	facility.global_position = gun.global_position
	gun.magazine.reserve -= 1
	var budget := main.session.budget
	assert_true(gun.request_resupply())
	assert_eq(main.session.budget, budget - 1)
	gun.magazine.reserve -= 1
	var id := gun.runtime_id
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored := main.support_manager.consumers[id] as CloseInGun
	assert_eq(restored.magazine.ordered_reserve, 1)
	assert_eq(restored.magazine.resupply_credit, restored.magazine.reserve_capacity - restored.magazine.resupply_pack_cost)
	main.support_manager.gameplay_tick(4.0)
	assert_eq(restored.magazine.reserve, 79)
	assert_eq(main.session.budget, budget - 1)

func test_restore_clears_old_airburst_audio_and_reconnects_restored_guns() -> void:
	var gun := _place_defense(_defense_definition(&"close_in_gun")) as CloseInGun
	var id := gun.runtime_id
	var document := main.capture_save_document()
	main.combat_audio.simulation_paused = false
	gun.gunfire.round_detonated.emit(Vector3.ZERO, &"timeout")
	assert_true(main.combat_audio.gun_airbursts.playing)
	var invalid := document.duplicate(true)
	invalid.version = -1
	assert_ne(main.restore_from_document(invalid), "")
	assert_true(main.combat_audio.gun_airbursts.playing, "실패한 로드는 재생 중인 작전을 변경하지 않습니다")
	assert_eq(main.restore_from_document(document), "")
	assert_false(main.combat_audio.gun_airbursts.playing)
	for unit: DefenseUnit in main.defenses:
		if unit.runtime_id == id:
			(unit as CloseInGun).gunfire.round_detonated.emit(Vector3.ZERO, &"timeout")
	assert_true(main.combat_audio.gun_airbursts.playing, "복원된 포대도 공통 자폭음에 연결됩니다")

func test_partial_city_repair_progress_round_trips_and_migrates_version_19() -> void:
	for index: int in 4:
		main.objective.apply_building_impact(10, Vector3(index * 10, 20, 0), 20)
	main.objective.restore_integrity(75)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	assert_eq(main.objective.damage_smoke_effects.size(), 3)
	main.objective.restore_integrity(80)
	assert_eq(main.objective.damage_smoke_effects.size(), 2, "복원해도 다음 수리 단계가 뒤로 밀리지 않습니다")
	var invalid := document.duplicate(true)
	invalid.payload.world.objective_damage_smoke.back().repair_at = 99
	assert_ne(main.restore_from_document(invalid), "")
	assert_eq(main.objective.current_integrity, 80)
	var legacy := document.duplicate(true)
	legacy.version = 19
	for site: Dictionary in legacy.payload.world.objective_damage_smoke:
		site.erase("repair_at")
	assert_eq(main.restore_from_document(legacy), "")
	main.objective.restore_integrity(99)
	assert_eq(main.objective.damage_smoke_effects.size(), 1)
	assert_false(legacy.payload.world.objective_damage_smoke[0].has("repair_at"))
	legacy.payload.world.objective_integrity = 100
	assert_eq(main.restore_from_document(legacy), "")
	assert_true(main.objective.capture_damage_smoke_state().is_empty(), "구버전의 완전 복구 후 잔류 기록은 제거합니다")

func test_runtime_snapshot_restores_session_world_assets_and_contacts() -> void:
	var battery_definition := _defense_definition(&"missile_battery")
	var placement_position := _find_valid_position(battery_definition.placement_profile)
	var placement_result: Dictionary = main.session.request_placement(battery_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var battery := placement_result.unit as MissileBattery
	var battery_runtime_id := battery.runtime_id
	var support := _place_defense(_defense_definition(&"support_facility")) as SupportFacility
	var support_price := support.definition.price
	assert_true(support.supports_position(battery.global_position))
	battery.doctrine.hold_fire = true
	battery.launch_cooldown = 0.125
	battery.receive_damage(20.0)
	battery.magazine.reserve = 0
	battery.set_automatic_resupply(true)
	assert_true(battery.request_resupply())
	assert_true(main.session.start_defense())
	main.session.gameplay_delta(7.5)
	main.session.update_pressure(4)
	main.session.grant_attack_window_reward(120)
	main.director.in_recovery = true
	main.director.completed_attack_windows = 1
	var building_bounds := main.battlefield.city_building_bounds(0)
	var building_impact := Vector3(building_bounds.position.x, building_bounds.get_center().y, building_bounds.get_center().z)
	main.objective.apply_building_impact(10, building_impact, building_bounds.size.y)
	var threat := main.director.spawn_one()
	var threat_runtime_id := threat.runtime_id
	threat.global_position = Vector3(340.0, 85.0, -120.0)
	threat.health = 42.0
	main.director.elapsed = 33.0
	var saved_director_rng_state := main.director.rng.state
	var saved_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var saved_budget := main.session.budget
	var saved_contact_count := main.registry.count()
	main.session.budget = 9999
	main.objective.apply_building_impact(30, Vector3(building_bounds.end.x, building_bounds.get_center().y, building_bounds.get_center().z), building_bounds.size.y)
	main.director.spawn_one()
	assert_eq(main.restore_from_document(saved_document), "")
	assert_eq(main.session.phase, GameSession.Phase.RUNNING)
	assert_eq(main.session.budget, saved_budget)
	assert_eq(main.session.survival_time, 7.5)
	assert_eq(main.session.current_pressure, 4)
	assert_eq(main.session.completed_attack_windows, 1)
	assert_eq(main.session.total_support_received, 120)
	assert_eq(main.session.starting_budget, main.scenario.starting_budget)
	assert_eq(main.session.defense_spending, battery_definition.price + support_price)
	assert_eq(main.objective.current_integrity, 90)
	assert_eq(main.objective.damage_smoke_effects.size(), 1)
	assert_almost_eq(main.objective.damage_smoke_effects[0].global_position, building_impact, Vector3.ONE * 0.001)
	assert_eq(main.defenses.size(), 3)
	var restored_battery := _find_defense(battery_runtime_id) as MissileBattery
	assert_eq(restored_battery.runtime_id, battery_runtime_id)
	assert_eq(restored_battery.global_position, placement_position)
	assert_true(restored_battery.doctrine.hold_fire)
	assert_eq(restored_battery.launch_cooldown, 0.125)
	assert_eq(restored_battery.integrity, 80.0)
	assert_eq(restored_battery.magazine.reserve, 0)
	assert_true(restored_battery.automatic_resupply_enabled())
	assert_eq(main.support_manager.task_status(restored_battery), "재보급 진행")
	assert_eq(main.registry.count(), saved_contact_count)
	var restored_threat := _find_contact(threat_runtime_id)
	assert_not_null(restored_threat)
	assert_eq(restored_threat.global_position, Vector3(340.0, 85.0, -120.0))
	assert_eq(restored_threat.health, 42.0)
	assert_eq(main.director.elapsed, 33.0)
	assert_true(main.director.in_recovery)
	assert_eq(main.director.completed_attack_windows, 1)
	assert_eq(main.director.rng.state, saved_director_rng_state)

func test_invalid_content_id_does_not_mutate_live_session() -> void:
	var document := main.capture_save_document()
	document.payload.world.defenses = [{
		"definition_id": "missing_content",
		"runtime_id": 1,
		"position": [0.0, 0.0, 0.0],
	}]
	var original_budget := main.session.budget
	var error := main.restore_from_document(document)
	assert_ne(error, "")
	assert_eq(main.session.budget, original_budget)
	assert_eq(main.registry.count(), 4)

func test_non_finite_or_non_numeric_world_vectors_do_not_mutate_live_session() -> void:
	var original_budget := main.session.budget
	for invalid_component: Variant in ["높이", INF, NAN]:
		var document := main.capture_save_document()
		document.payload.world.defenses[0].position = [invalid_component, 0.0, 0.0]
		assert_eq(SessionSnapshot.validation_error(document.payload, main.scenario), "방공망 위치가 올바르지 않습니다")
		assert_eq(main.session.budget, original_budget)
		assert_eq(main.defenses[0].global_position.is_finite(), true)

func test_snapshot_delegates_content_state_validation_to_definitions() -> void:
	var defense_definition := ValidatingDefenseDefinition.new()
	defense_definition.id = &"validating_defense"
	main.scenario.available_defenses.append(defense_definition)
	var defense_document := main.capture_save_document()
	defense_document.payload.world.defenses.append({
		"definition_id": "validating_defense",
		"runtime_id": 999,
		"position": [0.0, 0.0, 0.0],
		"integrity": 100.0,
		"content_state": {},
	})
	assert_true(SessionSnapshot.validation_error(defense_document.payload, main.scenario).contains("테스트 방어 상태 오류"))
	main.scenario.available_defenses.pop_back()
	var threat_definition := ValidatingThreatDefinition.new()
	threat_definition.id = &"validating_threat"
	main.scenario.ambient_contacts.append(threat_definition)
	var threat_document := main.capture_save_document()
	threat_document.payload.world.contacts.append({
		"definition_id": "validating_threat",
		"runtime_id": -999,
		"position": [0.0, 40.0, 0.0],
		"countermeasure_charges": 0,
		"content_state": {},
	})
	assert_true(SessionSnapshot.validation_error(threat_document.payload, main.scenario).contains("테스트 위협 상태 오류"))

func test_pending_air_strike_munition_restores_and_damages_at_its_surface_impact() -> void:
	var target := main.objective.global_position + Vector3(32.0, 0.0, -24.0)
	target.y = main.battlefield.terrain_height(target.x, target.z)
	var munition := preload("res://effects/air_strike_munition/air_strike_munition.tscn").instantiate() as AirStrikeMunition
	main.threat_parent.add_child(munition)
	munition.global_position = target + Vector3.UP * 90.0
	munition.setup(target, main.objective, 18)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored := main.threat_parent.get_node_or_null("StrikeMunition") as AirStrikeMunition
	assert_not_null(restored)
	var integrity_before := main.objective.current_integrity
	restored.gameplay_tick(1.0)
	assert_eq(main.objective.current_integrity, integrity_before - 18)
	assert_eq(main.objective.damage_smoke_effects.size(), 1)
	assert_almost_eq(main.objective.damage_smoke_effects[0].global_position, target, Vector3.ONE * 0.001)

func test_battery_strike_restores_observed_target_without_following_hidden_movement() -> void:
	var battery := _place_defense(_defense_definition(&"missile_battery"))
	main.enemy_knowledge.record_engagement(battery, &"missile")
	var entry: ThreatSpawnEntry
	for candidate: ThreatSpawnEntry in main.scenario.threat_entries:
		if candidate.threat_definition.id == &"battery_strike_uav":
			entry = candidate
	var threat := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	var runtime_id := threat.runtime_id
	var observed := threat.mission_runtime.fixed_target
	battery.global_position += Vector3(threat.mission_runtime.profile.acquisition_range + 200.0, 0, 0)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_contact(runtime_id) as AttackUav
	assert_eq(restored.mission_runtime.navigation_target(), observed)
	restored.global_position = observed + Vector3.UP * 100.0
	restored.gameplay_tick(0.1)
	assert_eq(restored.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_false(restored.mission_runtime.effect_applied)

func test_asset_strike_munition_restores_target_and_rejects_invalid_reference() -> void:
	var battery := _place_defense(_defense_definition(&"missile_battery"))
	var battery_id := battery.runtime_id
	var munition := preload("res://effects/air_strike_munition/air_strike_munition.tscn").instantiate() as AirStrikeMunition
	main.threat_parent.add_child(munition)
	munition.global_position = battery.global_position + Vector3.UP * 100.0
	munition.setup(battery.global_position, main.objective, 40, battery, false)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var invalid := document.duplicate(true)
	invalid.payload.world.projectiles.back().target_defense_id = 999999
	assert_ne(main.restore_from_document(invalid), "")
	assert_same(_find_defense(battery_id), battery)
	assert_eq(main.restore_from_document(document), "")
	var restored_battery := _find_defense(battery_id)
	var restored := main.threat_parent.get_node("StrikeMunition") as AirStrikeMunition
	var city_before := main.objective.current_integrity
	restored.gameplay_tick(1.0)
	assert_eq(restored_battery.integrity, restored_battery.definition.maximum_integrity - 40.0)
	assert_eq(main.objective.current_integrity, city_before)

func test_invalid_ballistic_flight_state_is_rejected_before_restore() -> void:
	var entry := _threat_entry(&"ballistic_missile")
	var threat := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	threat.gameplay_tick(0.1)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	document.payload.world.contacts.back().content_state.movement.ballistic_duration = 0.0
	assert_ne(main.restore_from_document(document), "")
	assert_same(_find_contact(threat.runtime_id), threat)

func test_multi_munition_inventory_mode_and_validation_restore() -> void:
	var battery := _place_defense(_defense_definition(&"long_range_missile")) as MissileBattery
	var battery_id := battery.runtime_id
	battery.set_munition_mode(&"high_speed_interceptor")
	battery.magazines[&"area_defense"].reserve = 4
	battery.magazines[&"high_speed_interceptor"].rounds = 1
	battery.magazines[&"high_speed_interceptor"].reserve = 0
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var invalid_document := document.duplicate(true)
	invalid_document.payload.world.defenses.back().content_state.munition_magazines.erase("high_speed_interceptor")
	assert_ne(main.restore_from_document(invalid_document), "")
	assert_same(_find_defense(battery_id), battery)
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(battery_id) as MissileBattery
	assert_eq(restored.munition_mode, &"high_speed_interceptor")
	assert_eq(restored.magazines[&"area_defense"].reserve, 4)
	assert_eq(restored.magazines[&"high_speed_interceptor"].rounds, 1)
	assert_eq(restored.magazines[&"high_speed_interceptor"].reserve, 0)

func test_active_engagement_restores_tracks_sensor_c2_and_interceptor_flight() -> void:
	var battery := _place_defense(_defense_definition(&"missile_battery")) as MissileBattery
	var radar := _place_defense(_defense_definition(&"search_radar")) as SearchRadar
	_place_defense(_defense_definition(&"command_post"))
	assert_not_null(battery)
	assert_not_null(radar)
	assert_true(main.session.start_defense())
	main.director.enabled = false
	var battery_runtime_id := battery.runtime_id
	var radar_runtime_id := radar.runtime_id
	var threat := main.director.spawn_one()
	threat.global_position = battery.global_position + Vector3(210.0, 55.0, 0.0)
	var tracked_position := threat.global_position
	var threat_runtime_id := threat.runtime_id
	main.player_knowledge.simulation_time = 2.5
	var observation := SensorObservation.new()
	observation.setup(radar.runtime_id, 2.5, threat.global_position, 0.95, 6.0, 1.0, &"attack_uav", ThreatDefinition.Affiliation.HOSTILE, 1.2)
	var track := main.player_knowledge.submit_observation(observation)
	assert_eq(track.state, PlayerTrack.State.CONFIRMED)
	var track_id := track.track_id
	radar.scan_cooldown = 0.23
	assert_true(battery._fire_round(track, battery.munition_for_track(track)))
	battery.doctrine.hold_fire = true
	var interceptor := battery.interceptors[0]
	interceptor.gameplay_tick(0.2)
	var saved_interceptor_position := interceptor.global_position
	var saved_interceptor_age := interceptor.age
	var saved_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var invalid_document := saved_document.duplicate(true)
	invalid_document.payload.world.projectiles[0].owner_defense_id = 9999
	assert_ne(main.restore_from_document(invalid_document), "")
	var unchanged_interceptors := _interceptors()
	assert_eq(unchanged_interceptors.size(), 1)
	assert_same(unchanged_interceptors[0], interceptor)
	assert_eq(interceptor.age, saved_interceptor_age)
	assert_eq(main.restore_from_document(saved_document), "")
	var restored_battery := _find_defense(battery_runtime_id) as MissileBattery
	var restored_radar := _find_defense(radar_runtime_id) as SearchRadar
	var restored_track := main.player_knowledge.find_track(track_id)
	assert_not_null(restored_battery)
	assert_not_null(restored_radar)
	assert_not_null(restored_track)
	assert_eq(restored_track.estimated_position, tracked_position)
	assert_eq(restored_track.contributing_sensor_ids, [radar_runtime_id])
	assert_eq(restored_track.classification, &"attack_uav")
	assert_eq(restored_track.affiliation, PlayerTrack.Affiliation.HOSTILE)
	assert_eq(restored_radar.scan_cooldown, 0.23)
	assert_true(main.c2_network.has_command_path(restored_battery, restored_radar.runtime_id))
	var restored_interceptors := _interceptors()
	assert_eq(restored_interceptors.size(), 1)
	var restored_interceptor := restored_interceptors[0]
	assert_eq(restored_interceptor.global_position, saved_interceptor_position)
	assert_eq(restored_interceptor.age, saved_interceptor_age)
	assert_same(restored_interceptor.target_track, restored_track)
	assert_eq(restored_interceptor.owner_defense_id, restored_battery.runtime_id)
	assert_true(restored_battery.interceptors.has(restored_interceptor))
	var restored_threat := _find_contact(threat_runtime_id)
	for frame: int in 100:
		restored_battery.gameplay_tick(0.05)
		if restored_threat.resolved_state:
			break
	assert_true(restored_threat.resolved_state)
	assert_eq(main.session.neutralized_count, 1)

func test_file_save_and_load_rebuilds_saved_seed_without_duplicate_world_nodes() -> void:
	var saved_seed := 48127
	main.scenario.world_seed = saved_seed
	main.battlefield.build(main.scenario)
	main.session.budget = 317
	var expected_height := main.battlefield.terrain_height(417.0, -263.0)
	var expected_building_count := main.battlefield.city_visuals.get_child_count()
	assert_eq(main.save_operation(), "")
	assert_true(FileAccess.file_exists(save_path))
	main.scenario.world_seed = 99241
	main.battlefield.build(main.scenario)
	main.session.budget = 9999
	assert_eq(main.load_operation(), "")
	assert_eq(main.scenario.world_seed, saved_seed)
	assert_eq(main.session.budget, 317)
	assert_almost_eq(main.battlefield.terrain_height(417.0, -263.0), expected_height, 0.0001)
	assert_eq(main.battlefield.terrain.get_child_count(), 1)
	assert_eq(main.battlefield.city_visuals.get_child_count(), expected_building_count)

func test_save_rejects_invalid_runtime_snapshot_without_replacing_previous_file() -> void:
	assert_eq(main.save_operation(), "")
	var saved: Dictionary = SaveStore.read(save_path)
	assert_eq(saved.error, "")
	var contact: ThreatUnit = main.registry.get_active()[0]
	contact.countermeasure_origin = Vector3(INF, 0.0, 0.0)
	assert_eq(main.save_operation(), "대응탄 위치가 올바르지 않습니다")
	var unchanged: Dictionary = SaveStore.read(save_path)
	assert_eq(unchanged.error, "")
	assert_eq(unchanged.document, saved.document)

func test_energy_and_power_providers_restore_with_runtime_assets() -> void:
	var support := _place_defense(_defense_definition(&"support_facility")) as SupportFacility
	var laser := _place_defense(_defense_definition(&"high_energy_laser")) as HighEnergyLaser
	assert_not_null(support)
	assert_not_null(laser)
	var laser_id := laser.runtime_id
	laser.energy_state.energy = 13.0
	laser.energy_state.heat = 21.0
	laser.energy_state.overheated = true
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(laser_id) as HighEnergyLaser
	assert_not_null(restored)
	assert_eq(restored.energy_state.energy, 13.0)
	assert_eq(restored.energy_state.heat, 21.0)
	assert_true(restored.energy_state.overheated)
	assert_eq(main.power_manager.generation_capacity(), 20.0)

func test_all_asset_types_relocate_with_their_duration_including_city_command() -> void:
	main.session.budget = 10000
	main.director.pressure_changed.emit(5)
	var units: Array[DefenseUnit] = [main.defenses[0]]
	for definition: DefenseDefinition in main.scenario.available_defenses:
		assert_true(definition.mobile, definition.display_name)
		assert_gt(definition.relocation_duration, 0.0)
		units.append(_place_defense(definition))
	for unit: DefenseUnit in units:
		var destination := _find_valid_position(unit.definition.placement_profile)
		var origin := unit.global_position
		assert_true(main.relocation_manager.request_relocation(unit, destination), unit.definition.display_name)
		assert_false(unit.active)
		main.relocation_manager.gameplay_tick(unit.definition.relocation_duration - 0.1)
		assert_eq(unit.global_position, origin)
		assert_false(unit.active)
		main.relocation_manager.gameplay_tick(0.2)
		assert_eq(unit.global_position, destination)
		assert_true(unit.active)
	assert_gt(_defense_definition(&"long_range_missile").relocation_duration, _defense_definition(&"short_range_missile").relocation_duration)
	assert_gt(_defense_definition(&"support_facility").relocation_duration, _defense_definition(&"long_range_missile").relocation_duration)

func test_radar_rooftop_relocation_keeps_the_roof_height_after_restore() -> void:
	var radar := _place_defense(_defense_definition(&"search_radar"))
	var destination := Vector3.INF
	for pad: Dictionary in main.battlefield.rooftop_pads:
		if main.battlefield.placement_result(pad.position, radar.definition.placement_profile).valid:
			destination = pad.position
			break
	assert_ne(destination, Vector3.INF)
	assert_true(main.relocation_manager.request_relocation(radar, destination))
	var id := radar.runtime_id
	var duration := radar.definition.relocation_duration
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	main.relocation_manager.gameplay_tick(duration + 0.1)
	assert_eq(_find_defense(id).global_position, destination)

func test_mobile_asset_relocation_finishes_after_save_restore() -> void:
	var gun := _place_defense(_defense_definition(&"close_in_gun")) as CloseInGun
	var origin := gun.global_position
	var destination := _find_valid_position(gun.definition.placement_profile)
	var budget_before := main.session.budget
	assert_true(main.relocation_manager.request_relocation(gun, destination))
	assert_false(gun.active)
	assert_eq(main.session.budget, budget_before)
	assert_eq(main.battlefield.occupied_positions.size(), 3)
	main.relocation_manager.gameplay_tick(gun.definition.relocation_duration - 0.1)
	assert_eq(gun.global_position, origin)
	var gun_id := gun.runtime_id
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(gun_id) as CloseInGun
	assert_false(restored.active)
	assert_string_contains(main.relocation_manager.task_status(restored), "재배치")
	main.relocation_manager.gameplay_tick(0.2)
	assert_eq(restored.global_position, destination)
	assert_true(restored.active)
	assert_eq(main.battlefield.occupied_positions.size(), 2)
	assert_eq(main.relocation_manager.task_status(restored), "")

func test_facility_target_and_egress_mission_restore_runtime_references() -> void:
	var support := _place_defense(_defense_definition(&"support_facility")) as SupportFacility
	var definition := _threat_entry(&"support_strike_uav").threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	threat.global_position = Vector3(900.0, 80.0, 0.0)
	threat.setup(301, definition)
	threat.configure_mission(main.objective, main.battlefield, support.global_position, 1.0, support, threat.global_position)
	main.registry.add(threat)
	main.director.threat_spawned.emit(threat)
	threat.mission_runtime.phase = ThreatMissionRuntime.Phase.EGRESS
	threat.mission_runtime.effect_applied = true
	var support_id := support.runtime_id
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored_threat := _find_contact(301) as AttackUav
	var restored_support := _find_defense(support_id)
	assert_same(restored_threat.mission_runtime.target_asset, restored_support)
	assert_eq(restored_threat.mission_runtime.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_true(restored_threat.mission_runtime.effect_applied)

func test_pending_raid_waves_restore_with_remaining_delays() -> void:
	main.director.schedule_archetype(main.scenario.raid_archetypes[0], 1.25)
	main.director._tick_pending_waves(1.0)
	assert_eq(main.director.pending_waves.size(), 2)
	var saved_waves: Array = main.director.capture_state().pending_waves
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	assert_eq(main.director.pending_waves, saved_waves)
	main.director._tick_pending_waves(3.0)
	assert_eq(main.director.pending_waves.size(), 1)

func test_enemy_knowledge_reports_and_aged_estimates_restore() -> void:
	var radar := _place_defense(_defense_definition(&"search_radar")) as SearchRadar
	main.enemy_knowledge.record_emission(radar)
	main.enemy_knowledge.gameplay_tick(12.0)
	var saved_state := main.enemy_knowledge.capture_state()
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored_state := main.enemy_knowledge.capture_state()
	assert_eq(restored_state.simulation_time, saved_state.simulation_time)
	assert_eq(restored_state.reports.size(), saved_state.reports.size())
	assert_eq(restored_state.reports[0].source, "radar_emission")
	var restored_estimate := main.enemy_knowledge.best_estimate_for_role(&"sensor")
	var saved_estimate: Dictionary = saved_state.estimates[0]
	assert_eq(restored_estimate.asset_id, saved_estimate.asset_id)
	assert_almost_eq(float(restored_estimate.confidence), float(saved_estimate.confidence), 0.000001)
	assert_almost_eq(float(restored_estimate.uncertainty), float(saved_estimate.uncertainty), 0.000001)

func test_active_interceptor_drone_restores_owner_track_and_flight_state() -> void:
	var base := _place_defense(_defense_definition(&"interceptor_drone_defense")) as InterceptorDroneDefense
	var radar := _place_defense(_defense_definition(&"search_radar")) as SearchRadar
	var threat := main.director.spawn_one()
	threat.global_position = base.global_position + Vector3(180.0, 70.0, 0.0)
	var observation := SensorObservation.new()
	observation.setup(radar.runtime_id, 0.0, threat.global_position, 0.95, 3.0, 1.0, &"uav", ThreatDefinition.Affiliation.HOSTILE, 4.0)
	var track := main.player_knowledge.submit_observation(observation)
	var drone := base._launch(track)
	drone.gameplay_tick(0.2)
	var saved_position := drone.global_position
	var base_id := base.runtime_id
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored_base := _find_defense(base_id) as InterceptorDroneDefense
	assert_not_null(restored_base)
	assert_eq(restored_base.active_drones.size(), 1)
	var restored := restored_base.active_drones[0]
	assert_same(restored.base_owner, restored_base)
	assert_eq(restored.target_track.track_id, track.track_id)
	assert_eq(restored.global_position, saved_position)
	assert_eq(main.restore_from_document(document), "")
	var second_base := _find_defense(base_id) as InterceptorDroneDefense
	assert_eq(second_base.active_drones.size(), 1)
	assert_eq(main.projectile_parent.get_child_count(), 1)
	assert_same(second_base.active_drones[0].base_owner, second_base)
	assert_eq(second_base.active_drones[0].global_position, saved_position)

func _find_contact(runtime_id: int) -> ThreatUnit:
	for contact: ThreatUnit in main.registry.get_active():
		if contact.runtime_id == runtime_id:
			return contact
	return null

func test_automatic_resupply_save_rejects_invalid_targets_before_changing_runtime() -> void:
	var battery := _place_defense(_defense_definition(&"missile_battery"))
	var facility := _place_defense(_defense_definition(&"support_facility"))
	battery.set_automatic_resupply(true)
	var original := main.capture_save_document()
	for invalid: Variant in [null, "bad", [999999], [facility.runtime_id], [battery.runtime_id, battery.runtime_id], [1.5], ["1"]]:
		var document := original.duplicate(true)
		document.payload.world.support.automatic_resupply_ids = invalid
		assert_ne(main.restore_from_document(document), "")
		assert_true(battery.automatic_resupply_enabled())
		assert_eq(main.defenses.size(), 3)
	var missing := original.duplicate(true)
	missing.payload.world.support.erase("automatic_resupply_ids")
	assert_ne(main.restore_from_document(missing), "")

func test_version_16_operation_restores_with_automatic_resupply_disabled() -> void:
	var battery := _place_defense(_defense_definition(&"missile_battery"))
	var runtime_id := battery.runtime_id
	var document := main.capture_save_document()
	document.version = 16
	document.payload.world.support.erase("automatic_resupply_ids")
	battery.set_automatic_resupply(true)
	var saved_budget := main.session.budget
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(runtime_id)
	assert_not_null(restored)
	assert_false(restored.automatic_resupply_enabled())
	assert_eq(main.session.budget, saved_budget)
	assert_eq(document.version, 16)
	assert_false(document.payload.world.support.has("automatic_resupply_ids"))

func test_version_17_gun_migrates_without_inventing_rounds_or_changing_ammunition() -> void:
	var gun := _place_defense(_defense_definition(&"close_in_gun")) as CloseInGun
	var id := gun.runtime_id
	gun.magazine.rounds = 23
	var document := main.capture_save_document()
	document.payload.world.defenses.back().content_state.erase("gunfire")
	assert_ne(main.restore_from_document(document), "", "현재 버전은 비행탄 필드를 생략할 수 없습니다")
	document.version = 17
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(id) as CloseInGun
	assert_eq(restored.magazine.rounds, 23)
	assert_eq(restored.gunfire.rounds.size(), 0)
	assert_false(document.payload.world.defenses.back().content_state.has("gunfire"))

func test_initial_city_command_preserves_damage_and_does_not_respawn_on_restore() -> void:
	var command := main.defenses[0]
	var id := command.runtime_id
	command.receive_damage(25.0)
	var position := command.global_position
	var integrity := command.integrity
	var document := main.capture_save_document()
	for iteration: int in 2:
		assert_eq(main.restore_from_document(document), "")
		assert_eq(main.defenses.size(), 1)
		assert_eq(_find_defense(id).integrity, integrity)
		assert_eq(_find_defense(id).global_position, position)
		assert_eq(main.session.defense_spending, 0)
	# Older saves without a rooftop installation retain their authored network.
	var legacy := document.duplicate(true)
	legacy.payload.world.defenses.clear()
	legacy.payload.session.defense_count = 0
	legacy.payload.session.next_defense_id = 1
	assert_eq(main.restore_from_document(legacy), "")
	assert_true(main.defenses.is_empty())

func _find_defense(runtime_id: int) -> DefenseUnit:
	for unit: DefenseUnit in main.defenses:
		if unit.runtime_id == runtime_id:
			return unit
	return null

func _defense_definition(definition_id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id == definition_id:
			return definition
	fail_test("방어 자산 정의를 찾지 못했습니다: %s" % definition_id)
	return null

func _threat_entry(definition_id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id == definition_id:
			return entry
	fail_test("위협 생성 항목을 찾지 못했습니다: %s" % definition_id)
	return null

func _interceptors() -> Array[HomingInterceptor]:
	var result: Array[HomingInterceptor] = []
	for child: Node in main.projectile_parent.get_children():
		if child is HomingInterceptor:
			result.append(child as HomingInterceptor)
	return result

func _place_defense(definition: DefenseDefinition) -> DefenseUnit:
	main.director.pressure_changed.emit(definition.unlock_pressure_level)
	var position := _find_valid_position(definition.placement_profile)
	var result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	assert_true(result.success)
	return result.get("unit") as DefenseUnit

func _find_valid_position(profile: PlacementProfile) -> Vector3:
	for z: int in range(-420, 421, 30):
		for x: int in range(-420, 421, 30):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, profile).valid:
				return position
	return Vector3(300.0, 0.0, 300.0)

func _cleanup_save_files() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_recon_search_and_flight_restore_without_using_asset_waypoints() -> void:
	var entry: ThreatSpawnEntry
	for candidate: ThreatSpawnEntry in main.scenario.threat_entries:
		if candidate.threat_definition.mission_definition() != null and candidate.threat_definition.mission_definition().area_recon:
			entry = candidate
	var recon := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	recon.global_position = Vector3(850, 145, 180)
	for step: int in 20:
		main.enemy_knowledge.gameplay_tick(0.1)
		recon.gameplay_tick(0.1)
	var id := recon.runtime_id
	var state := main.enemy_knowledge.capture_state()
	var flight := recon.reconnaissance.capture_state()
	var route := recon.mission_runtime.fixed_target
	var document := main.capture_save_document()
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_contact(id) as AttackUav
	assert_eq(restored.reconnaissance.capture_state(), flight)
	assert_eq(main.enemy_knowledge.capture_state(), state)
	assert_eq(restored.mission_runtime.fixed_target, route)
	assert_null(restored.mission_runtime.target_asset)
	var invalid := document.duplicate(true)
	invalid.payload.world.enemy_knowledge.recon_search.assignments[0].owner = 9999999
	assert_ne(main.restore_from_document(invalid), "")
	var legacy := document.duplicate(true)
	legacy.payload.world.enemy_knowledge.erase("recon_search")
	legacy.payload.world.enemy_knowledge.erase("recon_sightings")
	for contact: Dictionary in legacy.payload.world.contacts:
		contact.content_state.erase("reconnaissance")
	assert_eq(main.restore_from_document(legacy), "")
	var migrated := _find_contact(id) as AttackUav
	migrated.gameplay_tick(0.1)
	assert_null(migrated.mission_runtime.target_asset)
	assert_true(main.enemy_knowledge.search.assignments.has(id))

func test_opening_raid_members_pending_groups_and_rest_round_trip() -> void:
	main.director.enabled = true
	main.director.launch_budgeted_raid()
	var scheduled := main.director.pending_waves.duplicate(true)
	assert_false(scheduled.is_empty())
	var pending_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(pending_document), "")
	assert_eq(main.director.pending_waves, pending_document.payload.director.pending_waves)
	main.director._tick_pending_waves(32.0)
	var ids := main.director.opening_threat_ids.duplicate()
	assert_false(ids.is_empty())
	main.director.gameplay_tick(240.0)
	assert_eq(main.director.pressure_level, 1)
	assert_true(main.director.pending_waves.is_empty(), "첫 공습이 끝나기 전에 다음 자동 공습을 편성하지 않는다")
	var active_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(active_document), "")
	assert_eq(main.director.opening_threat_ids, ids)
	for threat: ThreatUnit in main.registry.get_hostile_active():
		threat.resolve_once(threat.runtime_id % 2 == 0)
	assert_true(main.director.opening_raid_complete)
	assert_true(main.director.opening_threat_ids.is_empty())
	main.director.gameplay_tick(main.scenario.recovery_duration * 0.5)
	var rest_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var start := main.director.pressure_started_at
	assert_eq(main.restore_from_document(rest_document), "")
	assert_eq(main.director.pressure_started_at, start)
	assert_eq(main.director.pressure_level, 1)
	main.director.gameplay_tick(main.scenario.recovery_duration * 0.5)
	assert_eq(main.director.pressure_level, 2)
	assert_eq(main.session.current_pressure, 2)
	assert_eq(main.hud.pressure_label.text, "위협 단계  2")
	var escalated_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(escalated_document), "")
	main.director.gameplay_tick(main.scenario.pressure_step_duration)
	assert_eq(main.director.pressure_level, 3)

func test_invalid_opening_raid_state_does_not_mutate_operation() -> void:
	main.director.launch_budgeted_raid()
	main.director._tick_pending_waves(32.0)
	var document := main.capture_save_document()
	var expected := main.director.capture_state()
	for invalid_ids: Array in [[999999], [1, 1], [0], [1.5]]:
		var invalid := document.duplicate(true)
		invalid.payload.director.opening_threat_ids = invalid_ids
		assert_ne(main.restore_from_document(invalid), "")
		assert_eq(main.director.capture_state(), expected)
	var invalid := document.duplicate(true)
	invalid.payload.director.pressure_started_at = NAN
	assert_ne(main.restore_from_document(invalid), "")
	assert_eq(main.director.capture_state(), expected)

func test_version_22_preserves_existing_pressure_without_catching_up() -> void:
	var document := main.capture_save_document()
	document.version = 22
	for key: String in ["opening_raid_started", "opening_raid_complete", "opening_threat_ids", "pressure_started_at"]:
		document.payload.director.erase(key)
	document.payload.director.elapsed = 1000.0
	document.payload.director.pressure_level = 5
	document.payload.director.enabled = true
	assert_eq(main.restore_from_document(document), "")
	assert_eq(main.director.pressure_level_at(1000.0), 5)
	main.director.until_spawn = 10000.0
	main.director.gameplay_tick(main.scenario.pressure_step_duration - 0.1)
	assert_eq(main.director.pressure_level, 5)
	main.director.gameplay_tick(0.1)
	assert_eq(main.director.pressure_level, 6)
	assert_false(document.payload.director.has("opening_raid_started"))

func test_version_22_first_stage_waits_for_existing_hostiles() -> void:
	main.director.spawn_one()
	main.director.schedule_archetype(main.scenario.raid_archetypes[0], 0.0)
	var document := main.capture_save_document()
	document.version = 22
	for key: String in ["opening_raid_started", "opening_raid_complete", "opening_threat_ids", "pressure_started_at"]:
		document.payload.director.erase(key)
	assert_eq(main.restore_from_document(document), "")
	assert_false(main.director.opening_threat_ids.is_empty())
	assert_false(main.director.opening_raid_complete)
	assert_eq(main.director.pressure_level_at(10000.0), 1)
	for wave: Dictionary in main.director.pending_waves:
		assert_true(wave.opening_raid)
