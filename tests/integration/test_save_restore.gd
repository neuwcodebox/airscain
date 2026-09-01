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

func _find_contact(runtime_id: int) -> ThreatUnit:
	for contact: ThreatUnit in main.registry.get_active():
		if contact.runtime_id == runtime_id:
			return contact
	return null

func _find_valid_position(profile: PlacementProfile) -> Vector3:
	for z: int in range(-420, 421, 30):
		for x: int in range(-420, 421, 30):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, profile).valid:
				return position
	return Vector3(300.0, 0.0, 300.0)
