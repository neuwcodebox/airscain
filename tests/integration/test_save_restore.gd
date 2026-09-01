extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func before_each() -> void:
	main = add_child_autofree(MAIN_SCENE.instantiate()) as AirscainMain
	await get_tree().process_frame

func test_runtime_snapshot_restores_session_world_assets_and_contacts() -> void:
	var battery_definition := main.scenario.available_defenses[0]
	var placement_position := _find_valid_position(battery_definition.placement_profile)
	var placement_result: Dictionary = main.session.request_placement(battery_definition, placement_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	var battery := placement_result.unit as MissileBattery
	var battery_runtime_id := battery.runtime_id
	battery.doctrine.hold_fire = true
	battery.cooldown = 1.25
	assert_true(main.session.start_defense())
	main.session.gameplay_delta(7.5)
	main.objective.apply_mission_damage(10)
	var threat := main.director.spawn_one()
	var threat_runtime_id := threat.runtime_id
	threat.global_position = Vector3(340.0, 85.0, -120.0)
	threat.health = 42.0
	main.director.elapsed = 33.0
	var saved_document := SaveDocument.decode(SaveDocument.encode(main.capture_save_document()))
	var saved_budget := main.session.budget
	var saved_contact_count := main.registry.count()
	main.session.budget = 9999
	main.objective.apply_mission_damage(30)
	main.director.spawn_one()
	assert_eq(main.restore_from_document(saved_document), "")
	assert_eq(main.session.phase, GameSession.Phase.RUNNING)
	assert_eq(main.session.budget, saved_budget)
	assert_eq(main.session.survival_time, 7.5)
	assert_eq(main.objective.current_integrity, 90)
	assert_eq(main.defenses.size(), 1)
	var restored_battery := main.defenses[0] as MissileBattery
	assert_eq(restored_battery.runtime_id, battery_runtime_id)
	assert_eq(restored_battery.global_position, placement_position)
	assert_true(restored_battery.doctrine.hold_fire)
	assert_eq(restored_battery.cooldown, 1.25)
	assert_eq(main.registry.count(), saved_contact_count)
	var restored_threat := _find_contact(threat_runtime_id)
	assert_not_null(restored_threat)
	assert_eq(restored_threat.global_position, Vector3(340.0, 85.0, -120.0))
	assert_eq(restored_threat.health, 42.0)
	assert_eq(main.director.elapsed, 33.0)

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
	battery._launch(track)
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

func _find_contact(runtime_id: int) -> ThreatUnit:
	for contact: ThreatUnit in main.registry.get_active():
		if contact.runtime_id == runtime_id:
			return contact
	return null

func _find_defense(runtime_id: int) -> DefenseUnit:
	for unit: DefenseUnit in main.defenses:
		if unit.runtime_id == runtime_id:
			return unit
	return null

func _place_defense(definition: DefenseDefinition) -> DefenseUnit:
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
