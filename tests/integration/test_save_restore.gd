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

var main: AirscainMain
var save_path: String

func before_each() -> void:
	AirscainMain.requested_seed = 73129
	main = add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	await get_tree().process_frame
	save_path = "user://main_save_restore_test_%d.json" % get_instance_id()
	main.save_path = save_path
	_cleanup_save_files()

func after_each() -> void:
	_cleanup_save_files()

func test_restore_clears_old_airburst_audio_and_reconnects_restored_guns() -> void:
	var gun := _place_defense(main.scenario.available_defenses[4]) as CloseInGun
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
	var battery_definition := main.scenario.available_defenses[0]
	var placement_position := _find_valid_position(battery_definition.placement_profile)
	var placement_result: Dictionary = main.session.request_placement(battery_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var battery := placement_result.unit as MissileBattery
	var battery_runtime_id := battery.runtime_id
	var support := _place_defense(main.scenario.available_defenses[5]) as SupportFacility
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
	assert_eq(main.defenses.size(), 2)
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
	var munition := preload("res://effects/air_strike_munition/air_strike_munition.tscn").instantiate() as Node3D
	main.threat_parent.add_child(munition)
	munition.global_position = target + Vector3.UP * 90.0
	munition.call("setup", target, main.objective, 18)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	assert_eq(main.restore_from_document(document), "")
	var restored := main.threat_parent.get_node_or_null("StrikeMunition") as Node3D
	assert_not_null(restored)
	var integrity_before := main.objective.current_integrity
	restored.call("_process", 1.0)
	assert_eq(main.objective.current_integrity, integrity_before - 18)
	assert_eq(main.objective.damage_smoke_effects.size(), 1)
	assert_almost_eq(main.objective.damage_smoke_effects[0].global_position, target, Vector3.ONE * 0.001)

func test_invalid_ballistic_flight_state_is_rejected_before_restore() -> void:
	var entry := main.scenario.threat_entries[9]
	var threat := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	threat.gameplay_tick(0.1)
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	document.payload.world.contacts.back().content_state.movement.ballistic_duration = 0.0
	assert_ne(main.restore_from_document(document), "")
	assert_same(_find_contact(threat.runtime_id), threat)

func test_multi_munition_inventory_mode_and_validation_restore() -> void:
	var battery := _place_defense(main.scenario.available_defenses[7]) as MissileBattery
	var battery_id := battery.runtime_id
	battery.set_munition_mode(&"high_speed_interceptor")
	battery.magazines[&"area_defense"].reserve = 4
	battery.magazines[&"high_speed_interceptor"].rounds = 1
	battery.magazines[&"high_speed_interceptor"].reserve = 0
	var document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var invalid_document := document.duplicate(true)
	invalid_document.payload.world.defenses[0].content_state.munition_magazines.erase("high_speed_interceptor")
	assert_ne(main.restore_from_document(invalid_document), "")
	assert_same(_find_defense(battery_id), battery)
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(battery_id) as MissileBattery
	assert_eq(restored.munition_mode, &"high_speed_interceptor")
	assert_eq(restored.magazines[&"area_defense"].reserve, 4)
	assert_eq(restored.magazines[&"high_speed_interceptor"].rounds, 1)
	assert_eq(restored.magazines[&"high_speed_interceptor"].reserve, 0)

func test_active_engagement_restores_tracks_sensor_c2_and_interceptor_flight() -> void:
	var battery := _place_defense(main.scenario.available_defenses[0]) as MissileBattery
	var radar := _place_defense(main.scenario.available_defenses[1]) as SearchRadar
	_place_defense(main.scenario.available_defenses[2])
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
	main.player_knowledge.set("simulation_time", 2.5)
	var observation := SensorObservation.new()
	observation.setup(radar.runtime_id, 2.5, threat.global_position, 0.95, 6.0, 1.0, &"attack_uav", ThreatDefinition.Affiliation.HOSTILE, 1.2)
	var track: PlayerTrack = main.player_knowledge.call("submit_observation", observation)
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
	assert_same(main.projectile_parent.get_child(0), interceptor)
	assert_eq(interceptor.age, saved_interceptor_age)
	assert_eq(main.restore_from_document(saved_document), "")
	var restored_battery := _find_defense(battery_runtime_id) as MissileBattery
	var restored_radar := _find_defense(radar_runtime_id) as SearchRadar
	var restored_track: PlayerTrack = main.player_knowledge.call("find_track", track_id)
	assert_not_null(restored_battery)
	assert_not_null(restored_radar)
	assert_not_null(restored_track)
	assert_eq(restored_track.estimated_position, tracked_position)
	assert_eq(restored_track.contributing_sensor_ids, [radar_runtime_id])
	assert_eq(restored_track.classification, &"attack_uav")
	assert_eq(restored_track.affiliation, PlayerTrack.Affiliation.HOSTILE)
	assert_eq(restored_radar.scan_cooldown, 0.23)
	assert_true(bool(main.c2_network.call("has_command_path", restored_battery, restored_radar.runtime_id)))
	assert_eq(main.projectile_parent.get_child_count(), 1)
	var restored_interceptor := main.projectile_parent.get_child(0) as HomingInterceptor
	assert_eq(restored_interceptor.global_position, saved_interceptor_position)
	assert_eq(restored_interceptor.age, saved_interceptor_age)
	assert_same(restored_interceptor.target_track, restored_track)
	assert_eq(restored_interceptor.owner_defense_id, restored_battery.runtime_id)
	assert_same(restored_battery.interceptors[0], restored_interceptor)
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

func test_energy_and_power_providers_restore_with_runtime_assets() -> void:
	var support := _place_defense(main.scenario.available_defenses[5]) as SupportFacility
	var laser := _place_defense(main.scenario.available_defenses[6]) as HighEnergyLaser
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

func test_mobile_asset_relocation_finishes_after_save_restore() -> void:
	var gun := _place_defense(main.scenario.available_defenses[4]) as CloseInGun
	var origin := gun.global_position
	var destination := _find_valid_position(gun.definition.placement_profile)
	var budget_before := main.session.budget
	assert_true(main.relocation_manager.request_relocation(gun, destination))
	assert_false(gun.active)
	assert_eq(main.session.budget, budget_before)
	assert_eq(main.battlefield.occupied_positions.size(), 2)
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
	assert_eq(main.battlefield.occupied_positions.size(), 1)
	assert_eq(main.relocation_manager.task_status(restored), "")

func test_facility_target_and_egress_mission_restore_runtime_references() -> void:
	var support := _place_defense(main.scenario.available_defenses[5]) as SupportFacility
	var definition := main.scenario.threat_entries[3].threat_definition as AttackUavDefinition
	var threat := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(threat)
	threat.global_position = Vector3(900.0, 80.0, 0.0)
	threat.setup(301, definition)
	threat.configure_mission(main.objective, main.battlefield, support.global_position, 1.0, support, threat.global_position)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
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
	var radar := _place_defense(main.scenario.available_defenses[1]) as SearchRadar
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
	var base := _place_defense(main.scenario.available_defenses[10]) as InterceptorDroneDefense
	var radar := _place_defense(main.scenario.available_defenses[1]) as SearchRadar
	var threat := main.director.spawn_one()
	threat.global_position = base.global_position + Vector3(180.0, 70.0, 0.0)
	var observation := SensorObservation.new()
	observation.setup(radar.runtime_id, 0.0, threat.global_position, 0.95, 3.0, 1.0, &"uav", ThreatDefinition.Affiliation.HOSTILE, 4.0)
	var track: PlayerTrack = main.player_knowledge.call("submit_observation", observation)
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

func _find_contact(runtime_id: int) -> ThreatUnit:
	for contact: ThreatUnit in main.registry.get_active():
		if contact.runtime_id == runtime_id:
			return contact
	return null

func test_automatic_resupply_save_rejects_invalid_targets_before_changing_runtime() -> void:
	var battery := _place_defense(main.scenario.available_defenses[0])
	var facility := _place_defense(main.scenario.available_defenses[5])
	battery.set_automatic_resupply(true)
	var original := main.capture_save_document()
	for invalid: Variant in [null, "bad", [999999], [facility.runtime_id], [battery.runtime_id, battery.runtime_id], [1.5], ["1"]]:
		var document := original.duplicate(true)
		document.payload.world.support.automatic_resupply_ids = invalid
		assert_ne(main.restore_from_document(document), "")
		assert_true(battery.automatic_resupply_enabled())
		assert_eq(main.defenses.size(), 2)
	var missing := original.duplicate(true)
	missing.payload.world.support.erase("automatic_resupply_ids")
	assert_ne(main.restore_from_document(missing), "")

func test_version_16_operation_restores_with_automatic_resupply_disabled() -> void:
	var battery := _place_defense(main.scenario.available_defenses[0])
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
	var gun := _place_defense(main.scenario.available_defenses[4]) as CloseInGun
	var id := gun.runtime_id
	gun.magazine.rounds = 23
	var document := main.capture_save_document()
	document.payload.world.defenses[0].content_state.erase("gunfire")
	assert_ne(main.restore_from_document(document), "", "현재 버전은 비행탄 필드를 생략할 수 없습니다")
	document.version = 17
	assert_eq(main.restore_from_document(document), "")
	var restored := _find_defense(id) as CloseInGun
	assert_eq(restored.magazine.rounds, 23)
	assert_eq(restored.gunfire.rounds.size(), 0)
	assert_false(document.payload.world.defenses[0].content_state.has("gunfire"))

func _find_defense(runtime_id: int) -> DefenseUnit:
	for unit: DefenseUnit in main.defenses:
		if unit.runtime_id == runtime_id:
			return unit
	return null

func _place_defense(definition: DefenseDefinition) -> DefenseUnit:
	main._on_pressure_changed(definition.unlock_pressure_level)
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
