extends GutTest

const BATTLEFIELD_SCENE := preload("res://world/battlefield.tscn")
const CITY_SCENE := preload("res://world/objective/city/city_objective.tscn")
const BATTERY_SCENE := preload("res://defense/missile_battery/missile_battery.tscn")
const SCENARIO := preload("res://main/first_scenario.tres")

class RoleDefenseDouble:
	extends DefenseUnit

var battlefield: Battlefield
var objective: ProtectedObjective

func before_each() -> void:
	battlefield = add_child_autofree(BATTLEFIELD_SCENE.instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	objective = add_child_autofree(CITY_SCENE.instantiate()) as ProtectedObjective
	objective.setup(1, SCENARIO.objective_definition)
	objective.exclusion_radius = SCENARIO.city_size * 0.5
	battlefield.set_objective(objective)

func test_placement_rejects_city_boundary_slope_and_overlap() -> void:
	var profile := SCENARIO.available_defenses[0].placement_profile
	assert_false(battlefield.placement_result(Vector3.ZERO, profile).valid)
	assert_false(battlefield.placement_result(Vector3(895.0, 0.0, 0.0), profile).valid)
	var sea_position := Vector3(800.0, battlefield.terrain_height(800.0, 0.0), 0.0)
	assert_eq(battlefield.placement_result(sea_position, profile).reason, "바다에는 배치할 수 없습니다")
	var valid_position := _find_valid_position(profile)
	assert_true(battlefield.placement_result(valid_position, profile).valid)
	var strict_slope_profile := profile.duplicate() as PlacementProfile
	strict_slope_profile.maximum_slope_degrees = 0.01
	assert_false(battlefield.placement_result(valid_position, strict_slope_profile).valid)
	battlefield.register_occupancy(valid_position, profile.footprint_radius)
	assert_false(battlefield.placement_result(valid_position, profile).valid)

func test_failed_placement_does_not_change_budget_or_occupancy() -> void:
	var session: GameSession = add_child_autofree(GameSession.new()) as GameSession
	var defenses: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var projectiles: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var registry := ThreatRegistry.new()
	session.reset(400)
	var result: Dictionary = session.request_placement(SCENARIO.available_defenses[0], Vector3.ZERO, battlefield, defenses, registry, projectiles)
	assert_false(result.success)
	assert_eq(session.budget, 400)
	assert_eq(session.defense_count, 0)
	assert_eq(battlefield.occupied_positions.size(), 0)

func test_successful_purchase_is_atomic_and_overlap_failure_costs_nothing() -> void:
	var session: GameSession = add_child_autofree(GameSession.new()) as GameSession
	var defenses: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var projectiles: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var registry := ThreatRegistry.new()
	session.reset(400)
	var position := _find_valid_position(SCENARIO.available_defenses[0].placement_profile)
	var first: Dictionary = session.request_placement(SCENARIO.available_defenses[0], position, battlefield, defenses, registry, projectiles)
	assert_true(first.success)
	assert_eq(session.budget, 200)
	assert_eq(session.defense_count, 1)
	var second: Dictionary = session.request_placement(SCENARIO.available_defenses[0], position, battlefield, defenses, registry, projectiles)
	assert_false(second.success)
	assert_eq(session.budget, 200)
	assert_eq(session.defense_count, 1)

func test_insufficient_budget_does_not_change_world_state() -> void:
	var session: GameSession = add_child_autofree(GameSession.new()) as GameSession
	var defenses: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var projectiles: Node3D = add_child_autofree(Node3D.new()) as Node3D
	session.reset(199)
	var position := _find_valid_position(SCENARIO.available_defenses[0].placement_profile)
	var result: Dictionary = session.request_placement(SCENARIO.available_defenses[0], position, battlefield, defenses, ThreatRegistry.new(), projectiles)
	assert_false(result.success)
	assert_eq(session.budget, 199)
	assert_eq(session.defense_count, 0)
	assert_eq(battlefield.occupied_positions.size(), 0)

func test_battery_prioritizes_tracks_nearest_the_protected_objective() -> void:
	var battery := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	battery.setup(1, SCENARIO.available_defenses[0])
	var near_battery := _confirmed_track(Vector3(50.0, 0.0, 0.0))
	var near_objective := _confirmed_track(Vector3(250.0, 0.0, 0.0))
	var tracks: Array[PlayerTrack] = [near_battery, near_objective]
	assert_same(battery.select_track(tracks, Vector3(300.0, 0.0, 0.0)), near_objective)
	battery.set_priority_track(near_battery.track_id)
	assert_same(battery.select_track(tracks, Vector3(300.0, 0.0, 0.0)), near_battery)

func test_battery_ignores_tentative_and_out_of_range_tracks() -> void:
	var battery := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	battery.setup(1, SCENARIO.available_defenses[0])
	var tentative := _confirmed_track(Vector3(50.0, 0.0, 0.0))
	tentative.state = PlayerTrack.State.TENTATIVE
	var out_of_range := _confirmed_track(Vector3(500.0, 0.0, 0.0))
	var available := _confirmed_track(Vector3(150.0, 0.0, 0.0))
	var tracks: Array[PlayerTrack] = [tentative, out_of_range, available]
	assert_same(battery.select_track(tracks, Vector3.ZERO), available)
	available.state = PlayerTrack.State.LOST
	assert_null(battery.select_track(tracks, Vector3.ZERO))

func test_doctrine_rejects_neutral_low_quality_and_hold_fire_tracks() -> void:
	var doctrine := EngagementDoctrine.new()
	var hostile := _confirmed_track(Vector3.ZERO)
	assert_true(doctrine.allows(hostile))
	hostile.track_quality = 0.1
	assert_false(doctrine.allows(hostile))
	hostile.track_quality = 0.8
	hostile.affiliation = PlayerTrack.Affiliation.NEUTRAL
	assert_false(doctrine.allows(hostile))
	doctrine.engage_neutral = true
	assert_true(doctrine.allows(hostile))
	doctrine.engage_neutral = false
	hostile.affiliation_confidence = 0.0
	doctrine.engage_unknown = true
	assert_true(doctrine.allows(hostile))
	doctrine.hold_fire = true
	assert_false(doctrine.allows(hostile))

func test_common_purchase_flow_accepts_role_test_double() -> void:
	var test_scene := PackedScene.new()
	var test_root := RoleDefenseDouble.new()
	assert_eq(test_scene.pack(test_root), OK)
	test_root.free()
	var definition := DefenseDefinition.new()
	definition.id = &"test_defense"
	definition.display_name = "Test Defense"
	definition.scene = test_scene
	definition.price = 50
	definition.placement_profile = PlacementProfile.new()
	var session: GameSession = add_child_autofree(GameSession.new()) as GameSession
	var defenses: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var projectiles: Node3D = add_child_autofree(Node3D.new()) as Node3D
	session.reset(100)
	var position := _find_valid_position(definition.placement_profile)
	var result: Dictionary = session.request_placement(definition, position, battlefield, defenses, ThreatRegistry.new(), projectiles)
	assert_true(result.success)
	assert_true(result.unit is RoleDefenseDouble)
	assert_eq(session.budget, 50)

func _find_valid_position(profile: PlacementProfile) -> Vector3:
	for z: int in range(-450, 451, 30):
		for x: int in range(-450, 451, 30):
			var candidate := Vector3(float(x), battlefield.terrain_height(float(x), float(z)), float(z))
			if battlefield.placement_result(candidate, profile).valid:
				return candidate
	return Vector3(300.0, 0.0, 300.0)

func _confirmed_track(position: Vector3) -> PlayerTrack:
	var track := PlayerTrack.new()
	track.track_id = int(position.x) + 1
	track.estimated_position = position
	track.track_quality = 0.8
	track.state = PlayerTrack.State.CONFIRMED
	track.classification = &"uav"
	track.classification_confidence = 0.8
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 0.8
	return track
