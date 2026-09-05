extends GutTest

const BATTLEFIELD_SCENE := preload("res://world/battlefield.tscn")
const CITY_SCENE := preload("res://world/objective/city/city_objective.tscn")
const BATTERY_SCENE := preload("res://defense/missile_battery/missile_battery.tscn")
const SCENARIO := preload("res://main/first_scenario.tres")
const INTERCEPT_GUIDANCE := preload("res://defense/intercept_guidance.gd")

class RoleDefenseDouble:
	extends DefenseUnit

class CapabilityProviderDouble:
	extends DefenseUnit

	func service_range() -> float:
		return 150.0

	func support_capacity() -> float:
		return 5.0

	func support_slots() -> int:
		return 1

	func power_capacity() -> float:
		return 12.0

class CapabilityConsumerDouble:
	extends DefenseUnit

	var replenished: bool = false

	func uses_ammunition() -> bool:
		return true

	func ammunition_needs_resupply() -> bool:
		return not replenished

	func resupply_work() -> float:
		return 5.0

	func complete_resupply() -> void:
		replenished = true

class TrackProviderDouble:
	extends Node

	var tracks: Array[PlayerTrack] = []

	func get_active_tracks() -> Array[PlayerTrack]:
		return tracks

class C2NetworkDouble:
	extends Node

	func available_tracks_for(_defense: DefenseUnit, tracks: Array[PlayerTrack]) -> Array[PlayerTrack]:
		return tracks

var battlefield: Battlefield
var objective: ProtectedObjective

func before_each() -> void:
	battlefield = add_child_autofree(BATTLEFIELD_SCENE.instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	objective = add_child_autofree(CITY_SCENE.instantiate()) as ProtectedObjective
	objective.setup(1, SCENARIO.objective_definition)
	objective.exclusion_radius = SCENARIO.city_size * 0.5
	battlefield.set_objective(objective)

func test_interceptor_seeker_can_be_defeated_by_finite_countermeasure() -> void:
	var registry := ThreatRegistry.new()
	var threat := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var threat_definition := ThreatDefinition.new()
	threat_definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	threat_definition.chaff_effectiveness = 1.0
	threat_definition.countermeasure_charges = 1
	threat.setup(90, threat_definition)
	threat.global_position = Vector3.ZERO
	registry.add(threat)
	var track := PlayerTrack.new()
	track.track_id = 12
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = threat.global_position
	var projectile_parent := add_child_autofree(Node3D.new()) as Node3D
	var interceptor := HomingInterceptor.new()
	projectile_parent.add_child(interceptor)
	interceptor.global_position = Vector3(-100.0, 0.0, 0.0)
	var battery_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(track, registry, battery_definition.munitions[0], Vector3.RIGHT, 1)
	interceptor.gameplay_tick(0.1)
	assert_false(interceptor.is_queued_for_deletion())
	assert_true(interceptor.countermeasure_decoy_active)
	assert_eq(threat.countermeasure_charges_remaining, 0)
	assert_eq(threat.health, 1.0)
	var burst := projectile_parent.get_node_or_null("CountermeasureBurst") as Node3D
	assert_not_null(burst)
	assert_true((burst.get_node("Chaff") as GPUParticles3D).emitting)
	assert_true((burst.get_node("ChaffGlints") as GPUParticles3D).emitting)
	assert_null(burst.get_node_or_null("Reason"))
	var chaff := burst.get_node("Chaff") as GPUParticles3D
	var glints := burst.get_node("ChaffGlints") as GPUParticles3D
	assert_between(chaff.amount, 160, 220)
	assert_gte(chaff.lifetime, 6.5)
	assert_between(glints.amount, 32, 64)
	assert_lt(glints.amount, chaff.amount / 3)
	var chaff_mesh := chaff.draw_pass_1 as BoxMesh
	var chaff_material := chaff_mesh.material as StandardMaterial3D
	var chaff_process := chaff.process_material as ParticleProcessMaterial
	var glint_process := glints.process_material as ParticleProcessMaterial
	assert_lt(chaff_mesh.size.x, 0.5)
	assert_gt(chaff_mesh.size.z, chaff_mesh.size.x * 5.0)
	assert_eq(chaff_material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	assert_true(chaff_material.metallic > 0.8)
	assert_false(chaff_material.emission_enabled)
	assert_gte(chaff_process.emission_sphere_radius, 18.0)
	assert_lte(chaff_process.initial_velocity_max, 0.5)
	assert_lte(chaff_process.gravity.length(), 0.1)
	assert_eq(chaff_process.angle_min, -180.0)
	assert_eq(chaff_process.angle_max, 180.0)
	assert_lt(chaff_process.angular_velocity_min, 0.0)
	assert_gt(chaff_process.angular_velocity_max, 0.0)
	assert_eq(chaff.explosiveness, 1.0)
	assert_eq(glint_process.emission_sphere_radius, chaff_process.emission_sphere_radius)
	assert_lte(glint_process.initial_velocity_max, 0.2)
	assert_true(glints.draw_pass_1 is QuadMesh)
	var glint_material := (glints.draw_pass_1 as QuadMesh).material as ShaderMaterial
	assert_true(glint_material.shader.code.contains("TIME * 11.0"))
	assert_true(glint_material.shader.code.contains("distance(UV"))
	var diverted_state := interceptor.capture_state()
	assert_true(bool(diverted_state.countermeasure_decoy_active))
	assert_eq(SaveDocument.vector3_from_data(diverted_state.countermeasure_decoy_position), interceptor.countermeasure_decoy_position)
	for tick: int in 20:
		if interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.05)
	assert_true(interceptor.is_queued_for_deletion())
	assert_gt(interceptor.global_position.distance_to(threat.global_position), interceptor.proximity_radius)
	assert_eq((projectile_parent.get_node("InterceptorMiss/Reason") as Label3D).text, "유도 이탈")

func test_interceptor_climbs_then_self_destructs_when_its_target_is_destroyed() -> void:
	var registry := ThreatRegistry.new()
	var threat := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var threat_definition := ThreatDefinition.new()
	threat_definition.signature_class = &"aircraft"
	threat.setup(91, threat_definition)
	threat.global_position = Vector3.ZERO
	threat.health = 0.0
	registry.add(threat)
	var track := PlayerTrack.new()
	track.track_id = 13
	track.state = PlayerTrack.State.CONFIRMED
	track.classification = &"aircraft"
	track.estimated_position = threat.global_position
	track.position_uncertainty = 12.0
	var projectile_parent := add_child_autofree(Node3D.new()) as Node3D
	var interceptor := HomingInterceptor.new()
	projectile_parent.add_child(interceptor)
	interceptor.global_position = Vector3(-140.0, 20.0, 0.0)
	var battery_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(track, registry, battery_definition.munitions[0], Vector3.RIGHT, 2)
	var position_before_resolution := interceptor.global_position
	registry.remove(threat)
	interceptor.gameplay_tick(0.1)
	assert_false(interceptor.is_queued_for_deletion())
	assert_gt(interceptor.global_position.x, position_before_resolution.x)
	assert_gt(interceptor.global_position.y, position_before_resolution.y)
	for tick: int in ceili(interceptor.maximum_lifetime / 0.1) + 1:
		if interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.1)
	assert_true(interceptor.is_queued_for_deletion())
	assert_not_null(projectile_parent.get_node_or_null("Explosion"))
	assert_null(projectile_parent.get_node_or_null("InterceptorMiss"))

func test_interceptor_retargets_a_reachable_hostile_track_before_self_destructing() -> void:
	var registry := ThreatRegistry.new()
	var threat_definition := ThreatDefinition.new()
	threat_definition.signature_class = &"aircraft"
	threat_definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	var original := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	original.setup(101, threat_definition)
	original.global_position = Vector3.ZERO
	original.health = 0.0
	registry.add(original)
	var alternate := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	alternate.setup(102, threat_definition)
	alternate.global_position = Vector3(120.0, 20.0, 12.0)
	registry.add(alternate)
	var original_track := _confirmed_track(Vector3.ZERO)
	original_track.track_id = 101
	original_track.classification = &"aircraft"
	original_track.affiliation = PlayerTrack.Affiliation.HOSTILE
	original_track.affiliation_confidence = 1.0
	var alternate_track := _confirmed_track(alternate.global_position)
	alternate_track.track_id = 102
	alternate_track.classification = &"aircraft"
	alternate_track.affiliation = PlayerTrack.Affiliation.HOSTILE
	alternate_track.affiliation_confidence = 1.0
	alternate_track.state = PlayerTrack.State.LOST
	var candidates: Array[PlayerTrack] = [original_track, alternate_track]
	var projectile_parent := add_child_autofree(Node3D.new()) as Node3D
	var interceptor := HomingInterceptor.new()
	projectile_parent.add_child(interceptor)
	interceptor.global_position = Vector3(-100.0, 20.0, 0.0)
	var battery_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(original_track, registry, battery_definition.munitions[0], Vector3.RIGHT, 4, 0, candidates)
	registry.remove(original)
	assert_same(interceptor.target_track, original_track)
	interceptor.gameplay_tick(1.0)
	assert_false(interceptor.is_queued_for_deletion())
	alternate_track.state = PlayerTrack.State.CONFIRMED
	interceptor.gameplay_tick(0.05)
	assert_same(interceptor.target_track, alternate_track)
	interceptor.gameplay_tick(0.1)
	assert_false(interceptor.is_queued_for_deletion())
	assert_gt(interceptor.global_position.x, -100.0)
	for tick: int in 30:
		if interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.05)
	assert_true(interceptor.is_queued_for_deletion())
	assert_true(alternate.resolved_state)

func test_removing_one_close_cruise_missile_does_not_divert_interceptors_from_the_other() -> void:
	var registry := ThreatRegistry.new()
	var threat_definition := ThreatDefinition.new()
	threat_definition.signature_class = &"cruise_missile"
	threat_definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	var removed := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	removed.setup(201, threat_definition)
	removed.global_position = Vector3.ZERO
	removed.health = 0.0
	registry.add(removed)
	var surviving := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	surviving.setup(202, threat_definition)
	surviving.global_position = Vector3(36.0, 0.0, 0.0)
	registry.add(surviving)
	var removed_track := _confirmed_track(removed.global_position)
	removed_track.track_id = 201
	removed_track.classification = &"cruise_missile"
	removed_track.affiliation = PlayerTrack.Affiliation.HOSTILE
	removed_track.affiliation_confidence = 1.0
	removed_track.position_uncertainty = 8.0
	var surviving_track := _confirmed_track(surviving.global_position)
	surviving_track.track_id = 202
	surviving_track.classification = &"cruise_missile"
	surviving_track.affiliation = PlayerTrack.Affiliation.HOSTILE
	surviving_track.affiliation_confidence = 1.0
	surviving_track.position_uncertainty = 8.0
	var candidates: Array[PlayerTrack] = [removed_track, surviving_track]
	var projectile_parent := add_child_autofree(Node3D.new()) as Node3D
	var battery_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	var removed_interceptor := HomingInterceptor.new()
	projectile_parent.add_child(removed_interceptor)
	removed_interceptor.global_position = Vector3(-120.0, 12.0, 0.0)
	removed_interceptor.configure(removed_track, registry, battery_definition.munitions[0], Vector3.RIGHT, 11, 0, candidates)
	var surviving_interceptor := HomingInterceptor.new()
	projectile_parent.add_child(surviving_interceptor)
	surviving_interceptor.global_position = Vector3(-110.0, 12.0, 4.0)
	surviving_interceptor.configure(surviving_track, registry, battery_definition.munitions[0], Vector3.RIGHT, 12, 0, candidates)
	registry.remove(removed)
	assert_same(removed_interceptor.target_track, surviving_track)
	assert_same(surviving_interceptor.target_track, surviving_track)
	assert_eq(surviving_interceptor.reacquisition_remaining, -1.0)
	assert_false(surviving_interceptor.is_queued_for_deletion())

func test_interceptor_self_destructs_after_passing_an_empty_guidance_point() -> void:
	var registry := ThreatRegistry.new()
	var track := PlayerTrack.new()
	track.track_id = 14
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = Vector3.ZERO
	var projectile_parent := add_child_autofree(Node3D.new()) as Node3D
	var interceptor := HomingInterceptor.new()
	projectile_parent.add_child(interceptor)
	interceptor.global_position = Vector3(-50.0, 0.0, 0.0)
	var battery_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(track, registry, battery_definition.munitions[0], Vector3.RIGHT, 3)
	interceptor.gameplay_tick(0.2)
	assert_false(interceptor.is_queued_for_deletion())
	interceptor.gameplay_tick(0.2)
	assert_true(interceptor.is_queued_for_deletion())
	assert_lt(interceptor.global_position.x, 40.0)
	assert_eq((projectile_parent.get_node("InterceptorMiss/Reason") as Label3D).text, "유도 이탈")

func test_friendly_interceptor_resolves_at_the_first_terrain_crossing() -> void:
	var x := -260.0
	var z := 170.0
	var ground_height := battlefield.terrain_height(x, z)
	var from_position := Vector3(x, ground_height + 12.0, z)
	var to_position := Vector3(x, ground_height - 18.0, z)
	var impact := battlefield.terrain_segment_impact(from_position, to_position)
	assert_false(impact.is_empty())
	assert_almost_eq((impact.position as Vector3).y, ground_height, 0.01)
	var registry := ThreatRegistry.new()
	var track := _confirmed_track(Vector3(x, ground_height - 100.0, z))
	track.track_id = 301
	var projectile_parent := add_child_autofree(Node3D.new()) as Node3D
	var interceptor := HomingInterceptor.new()
	projectile_parent.add_child(interceptor)
	interceptor.global_position = from_position
	var battery_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(track, registry, battery_definition.munitions[0], Vector3.DOWN, 21, 0, [], battlefield)
	interceptor.gameplay_tick(0.1)
	assert_true(interceptor.is_queued_for_deletion())
	assert_almost_eq(interceptor.global_position.y, ground_height, 0.05)
	assert_eq((projectile_parent.get_node("InterceptorMiss/Reason") as Label3D).text, "지형 충돌")
	assert_not_null(projectile_parent.get_node_or_null("Explosion"))

func test_placement_rejects_city_boundary_slope_and_overlap() -> void:
	var profile := SCENARIO.available_defenses[0].placement_profile
	assert_false(battlefield.placement_result(Vector3.ZERO, profile).valid)
	var boundary_x := SCENARIO.battlefield_size * 0.5 - 5.0
	assert_false(battlefield.placement_result(Vector3(boundary_x, 0.0, 0.0), profile).valid)
	var sea_x := SCENARIO.battlefield_size * 0.45
	var sea_position := Vector3(sea_x, battlefield.terrain_height(sea_x, 0.0), 0.0)
	assert_eq(battlefield.placement_result(sea_position, profile).reason, "바다에는 배치할 수 없습니다")
	var valid_position := _find_valid_position(profile)
	assert_true(battlefield.placement_result(valid_position, profile).valid)
	var strict_slope_profile := profile.duplicate() as PlacementProfile
	strict_slope_profile.maximum_slope_degrees = 0.01
	assert_false(battlefield.placement_result(valid_position, strict_slope_profile).valid)
	battlefield.register_occupancy(valid_position, profile.footprint_radius)
	assert_false(battlefield.placement_result(valid_position, profile).valid)

func test_ground_placement_uses_actual_buildings_instead_of_a_city_radius() -> void:
	var profile := SCENARIO.available_defenses[0].placement_profile
	var building := battlefield.generator.building_transforms()[0]
	var building_ground := Vector3(building.origin.x, battlefield.terrain_height(building.origin.x, building.origin.z), building.origin.z)
	assert_true(battlefield.overlaps_city_building(building_ground, profile.footprint_radius))
	assert_eq(battlefield.placement_result(building_ground, profile).reason, "건물과 겹칩니다")
	var open_position := Vector3.INF
	for z: int in range(-140, 141, 10):
		for x: int in range(-140, 141, 10):
			var candidate := Vector3(float(x), battlefield.terrain_height(float(x), float(z)), float(z))
			if Vector2(candidate.x, candidate.z).length() >= objective.exclusion_radius:
				continue
			if battlefield.placement_result(candidate, profile).valid:
				open_position = candidate
				break
		if open_position.is_finite():
			break
	assert_true(open_position.is_finite())
	assert_lt(Vector2(open_position.x, open_position.z).length(), objective.exclusion_radius)
	assert_false(battlefield.overlaps_city_building(open_position, profile.footprint_radius))
	assert_true(battlefield.placement_result(open_position, profile).valid)

func test_designated_rooftop_accepts_only_lightweight_compatible_assets() -> void:
	assert_gt(battlefield.rooftop_pads.size(), 0)
	var rooftop_position: Vector3 = battlefield.rooftop_pads[0].position
	var radar_profile := SCENARIO.available_defenses[1].placement_profile
	var missile_profile := SCENARIO.available_defenses[0].placement_profile
	assert_true(radar_profile.rooftop_allowed)
	assert_true(battlefield.placement_result(rooftop_position, radar_profile).valid)
	assert_eq(battlefield.placement_result(rooftop_position, missile_profile).reason, "이 장비는 옥상에 배치할 수 없습니다")
	var session: GameSession = add_child_autofree(GameSession.new()) as GameSession
	var defenses: Node3D = add_child_autofree(Node3D.new()) as Node3D
	var projectiles: Node3D = add_child_autofree(Node3D.new()) as Node3D
	session.reset(400)
	var result := session.request_placement(SCENARIO.available_defenses[1], rooftop_position, battlefield, defenses, ThreatRegistry.new(), projectiles)
	assert_true(result.success)
	assert_eq((result.unit as DefenseUnit).global_position, rooftop_position)
	assert_false(battlefield.placement_result(rooftop_position, radar_profile).valid)

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

func test_fire_support_assignments_do_not_consume_interceptor_slots() -> void:
	var coordinator := add_child_autofree(EngagementCoordinator.new()) as EngagementCoordinator
	for owner: int in [1, 2, 3]:
		assert_true(coordinator.reserve_fire_support(7, owner))
	assert_true(coordinator.try_reserve(7, 4, 2.0, 2))
	assert_true(coordinator.try_reserve(7, 5, 2.0, 2))
	assert_false(coordinator.try_reserve(7, 6, 2.0, 2))
	assert_true(coordinator.reserve_fire_support(7, 6))
	assert_eq(coordinator.reservation_count(7), 6)
	assert_true(coordinator.reserve_fire_support(8, 1))
	assert_eq(coordinator.fire_support_target(1), 8)
	assert_false(coordinator.engagement_owner_ids(7).has(1))
	var saved := coordinator.capture_state()
	coordinator.restore_state(saved)
	assert_eq(coordinator.capture_state(), saved)
	coordinator.release_fire_support(2)
	assert_eq(coordinator.fire_support_target(2), 0)
	coordinator.gameplay_tick(0.6)
	assert_eq(coordinator.reservation_count(7), 2)
	assert_eq(coordinator.reservation_count(8), 0)

func test_three_ciws_fire_together_and_release_assignments_on_hold_fire() -> void:
	var coordinator := add_child_autofree(EngagementCoordinator.new()) as EngagementCoordinator
	var provider := add_child_autofree(TrackProviderDouble.new()) as TrackProviderDouble
	var network := add_child_autofree(C2NetworkDouble.new()) as C2NetworkDouble
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	var track := _confirmed_track(Vector3(600, 90, -150))
	track.classification = &"uav"
	provider.tracks = [track]
	assert_true(coordinator.try_reserve(track.track_id, 90, 10, 2))
	assert_true(coordinator.try_reserve(track.track_id, 91, 10, 2))
	for index: int in 3:
		var gun := add_child_autofree(SCENARIO.available_defenses[4].scene.instantiate()) as CloseInGun
		gun.setup(index + 1, SCENARIO.available_defenses[4])
		gun.global_position = Vector3(580 + index * 20, 50, 0)
		gun.configure_combat(ThreatRegistry.new(), projectiles)
		gun.configure_player_knowledge(battlefield, provider)
		gun.configure_c2(network)
		gun.configure_engagements(coordinator)
		gun._aim_turret(track.estimated_position, 10)
		var initial_rounds := gun.magazine.rounds
		gun.gameplay_tick(0.02)
		assert_eq(gun.magazine.rounds, initial_rounds - 1, "다른 근접포와 미사일이 교전 중이어도 발사해야 합니다")
		assert_false(gun.gunfire.rounds.is_empty())
		assert_eq(coordinator.fire_support_target(gun.runtime_id), track.track_id)
	assert_eq(coordinator.reservation_count(track.track_id, EngagementCoordinator.FIRE_SUPPORT), 3)
	for child: Node in get_children():
		if child is CloseInGun:
			var gun := child as CloseInGun
			gun.doctrine.hold_fire = true
			gun.gameplay_tick(0.02)
			assert_eq(coordinator.fire_support_target(gun.runtime_id), 0)

func test_gun_laser_and_microwave_can_fire_on_the_same_reserved_track() -> void:
	var coordinator := add_child_autofree(EngagementCoordinator.new()) as EngagementCoordinator
	var provider := add_child_autofree(TrackProviderDouble.new()) as TrackProviderDouble
	var network := add_child_autofree(C2NetworkDouble.new()) as C2NetworkDouble
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	var track := _confirmed_track(Vector3(600, 75, -90))
	provider.tracks = [track]
	coordinator.try_reserve(track.track_id, 90, 10, 2)
	coordinator.try_reserve(track.track_id, 91, 10, 2)
	var fired: Array[int] = []
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		if definition.engagement_reservation_kind() != EngagementCoordinator.FIRE_SUPPORT:
			continue
		var unit := add_child_autofree(definition.scene.instantiate()) as ArmedDefenseUnit
		unit.setup(fired.size() + 1, definition)
		unit.global_position = Vector3(600, 50, 0)
		unit.configure_combat(ThreatRegistry.new(), projectiles)
		unit.configure_player_knowledge(battlefield, provider)
		unit.configure_c2(network)
		unit.configure_engagements(coordinator)
		unit.weapon_fired.connect(func(owner: DefenseUnit, _low: bool) -> void: fired.append(owner.runtime_id))
		unit.call("_aim_turret", track.estimated_position, 10.0)
		unit.gameplay_tick(0.02)
	assert_eq(fired.size(), 3, "기관포·레이저·HPM이 서로의 화력을 잠그지 않습니다")
	assert_eq(coordinator.reservation_count(track.track_id, EngagementCoordinator.INTERCEPTOR), 2)
	assert_eq(coordinator.reservation_count(track.track_id, EngagementCoordinator.FIRE_SUPPORT), 3)

func test_ciws_spreads_equal_targets_but_can_concentrate_on_urgent_or_priority_tracks() -> void:
	var gun := add_child_autofree(SCENARIO.available_defenses[4].scene.instantiate()) as CloseInGun
	gun.setup(2, SCENARIO.available_defenses[4])
	var coordinator := add_child_autofree(EngagementCoordinator.new()) as EngagementCoordinator
	gun.configure_engagements(coordinator)
	var first := _confirmed_track(Vector3(100, 50, 0))
	var second := _confirmed_track(Vector3(-100, 50, 0))
	second.track_id = first.track_id + 1
	var tracks: Array[PlayerTrack] = [first, second]
	coordinator.reserve_fire_support(first.track_id, 1)
	assert_same(gun.select_track(tracks, Vector3.ZERO), second)
	coordinator.reserve_fire_support(second.track_id, gun.runtime_id)
	assert_same(gun.select_track(tracks, Vector3.ZERO), second, "현재 배정을 유지해 매 프레임 조준 표적을 바꾸지 않습니다")
	first.estimated_velocity = -first.estimated_position.normalized() * 160
	assert_same(gun.select_track(tracks, Vector3.ZERO), first, "빠르게 접근하는 긴급 표적에는 집중 사격을 허용합니다")
	gun.set_priority_track(second.track_id)
	assert_same(gun.select_track(tracks, Vector3.ZERO), second)

func test_battery_prioritizes_tracks_nearest_the_protected_objective() -> void:
	var battery := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	battery.setup(1, SCENARIO.available_defenses[0])
	var near_battery := _confirmed_track(Vector3(50.0, 0.0, 0.0))
	var near_objective := _confirmed_track(Vector3(250.0, 0.0, 0.0))
	var tracks: Array[PlayerTrack] = [near_battery, near_objective]
	assert_same(battery.select_track(tracks, Vector3(300.0, 0.0, 0.0)), near_objective)
	battery.set_priority_track(near_battery.track_id)
	assert_same(battery.select_track(tracks, Vector3(300.0, 0.0, 0.0)), near_battery)
	var coordinator := EngagementCoordinator.new()
	battery.configure_engagements(coordinator)
	assert_true(coordinator.try_reserve(near_battery.track_id, 9, 1.0))
	assert_same(battery.select_track(tracks, Vector3(300.0, 0.0, 0.0)), near_battery)
	assert_true(coordinator.try_reserve(near_battery.track_id, 10, 1.0, 2))
	assert_same(battery.select_track(tracks, Vector3(300.0, 0.0, 0.0)), near_objective)
	coordinator.free()

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

func test_two_batteries_can_engage_the_same_cruise_track_without_global_single_shot_lockout() -> void:
	var first := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	var second := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	first.setup(31, SCENARIO.available_defenses[0])
	second.setup(32, SCENARIO.available_defenses[0])
	var coordinator := EngagementCoordinator.new()
	first.configure_engagements(coordinator)
	second.configure_engagements(coordinator)
	var cruise := _confirmed_track(Vector3(180.0, 45.0, 0.0))
	cruise.classification = &"cruise_missile"
	var munition := first.munition_for_track(cruise)
	assert_true(coordinator.try_reserve(cruise.track_id, first.runtime_id, munition.interceptor_lifetime, first.engagement_limit()))
	assert_same(second.select_track([cruise], Vector3.ZERO), cruise)
	assert_true(coordinator.try_reserve(cruise.track_id, second.runtime_id, munition.interceptor_lifetime, second.engagement_limit()))
	assert_null(first.select_track([cruise], Vector3.ZERO))
	coordinator.free()

func test_missile_rack_empties_visible_cells_then_shows_reload_and_ammunition() -> void:
	var battery := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	var definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	battery.setup(33, definition)
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	battery.configure_combat(ThreatRegistry.new(), projectiles)
	var track := _confirmed_track(Vector3(220.0, 60.0, 0.0))
	var munition := definition.munitions[0]
	assert_eq(battery._launcher_caps().size(), munition.magazine_capacity)
	for expected_rounds: int in range(munition.magazine_capacity - 1, -1, -1):
		assert_true(battery._fire_round(track, munition))
		assert_eq(battery.magazines[munition.id].rounds, expected_rounds)
		assert_eq(battery._launcher_caps().filter(func(cap: Node3D) -> bool: return cap.visible).size(), expected_rounds)
	battery._process(0.0)
	assert_false(battery.status_marker.visible)
	assert_string_contains(battery.resource_status_text(), "재장전 9.0초")
	assert_eq(definition.launch_interval, 0.56)

func test_missile_rack_launches_one_ready_round_per_interval() -> void:
	var battery := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	var definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	battery.setup(34, definition)
	battery.global_position = Vector3(0.0, battlefield.terrain_height(0.0, 0.0), 0.0)
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	var track_provider := add_child_autofree(TrackProviderDouble.new()) as TrackProviderDouble
	var c2_network := add_child_autofree(C2NetworkDouble.new()) as C2NetworkDouble
	var coordinator := add_child_autofree(EngagementCoordinator.new()) as EngagementCoordinator
	var target_position := battery.launch_point.global_position + battery.launcher_forward() * 220.0 + Vector3.UP * 40.0
	var registry := ThreatRegistry.new()
	var threat := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var threat_definition := ThreatDefinition.new()
	threat_definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	threat.setup(3401, threat_definition)
	threat.global_position = target_position
	registry.add(threat)
	var track := _confirmed_track(target_position)
	track.track_id = threat.runtime_id
	track.classification = &"cruise_missile"
	track_provider.tracks = [track]
	battery.configure_combat(registry, projectiles)
	battery.configure_player_knowledge(battlefield, track_provider)
	battery.configure_c2(c2_network)
	battery.configure_engagements(coordinator)
	battery.gameplay_tick(0.01)
	assert_eq(battery.interceptors.size(), 1)
	assert_eq(coordinator.reservation_count(track.track_id), 1)
	battery.gameplay_tick(definition.launch_interval - 0.02)
	assert_eq(battery.interceptors.size(), 1)
	battery.gameplay_tick(0.021)
	assert_eq(battery.interceptors.size(), 2)
	assert_eq(coordinator.reservation_count(track.track_id), 2)
	battery.gameplay_tick(definition.launch_interval)
	assert_eq(battery.interceptors.size(), 2, "per-track allocation must stop the rack from dumping every ready round at one threat")

func test_missile_battery_launches_within_a_broad_sector_without_exact_alignment() -> void:
	var battery := add_child_autofree(BATTERY_SCENE.instantiate()) as MissileBattery
	battery.setup(5, SCENARIO.available_defenses[0])
	var initial_yaw := battery.turret.rotation.y
	var initial_pitch := battery.elevation.rotation.x
	var launch_direction := battery.launcher_forward()
	var target_direction := launch_direction.rotated(Vector3.UP, deg_to_rad(battery.launch_sector_degrees * 0.65))
	var target_position := battery.launch_point.global_position + target_direction * 220.0
	assert_true(battery._aim_turret(target_position, 0.1))
	assert_eq(battery.turret.rotation.y, initial_yaw)
	assert_eq(battery.elevation.rotation.x, initial_pitch)
	var track := _confirmed_track(target_position)
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	battery.configure_combat(ThreatRegistry.new(), projectiles)
	battery._spawn_interceptor(track, (SCENARIO.available_defenses[0] as MissileBatteryDefinition).munitions[0], 0, 0.0)
	assert_eq(battery.interceptors.size(), 1)
	assert_almost_eq(battery.interceptors[0].velocity.normalized(), launch_direction, Vector3.ONE * 0.001)
	var launch_error := battery.interceptors[0].velocity.normalized().angle_to(target_direction)
	assert_gt(launch_error, deg_to_rad(10.0))
	battery.interceptors[0].gameplay_tick(0.05)
	var guided_error := battery.interceptors[0].velocity.normalized().angle_to(target_direction)
	assert_lt(guided_error, launch_error)
	assert_gt(guided_error, deg_to_rad(5.0))
	var far_target := battery.launch_point.global_position + launch_direction.rotated(Vector3.UP, deg_to_rad(80.0)) * 220.0
	assert_false(battery._aim_turret(far_target, 0.1))
	assert_ne(battery.turret.rotation.y, initial_yaw)

func test_long_range_launcher_selects_and_preserves_specialized_munition() -> void:
	var definition := SCENARIO.available_defenses[7] as MissileBatteryDefinition
	var battery := add_child_autofree(definition.scene.instantiate()) as MissileBattery
	battery.setup(7, definition)
	var ballistic := _confirmed_track(Vector3(200.0, 420.0, 0.0))
	ballistic.classification = &"ballistic_missile"
	assert_eq(battery.munition_for_track(ballistic).id, &"high_speed_interceptor")
	var coordinator := EngagementCoordinator.new()
	battery.configure_engagements(coordinator)
	assert_true(coordinator.try_reserve(ballistic.track_id, 90, 1.0, 2))
	assert_same(battery.select_track([ballistic], Vector3.ZERO), ballistic)
	assert_true(coordinator.try_reserve(ballistic.track_id, 91, 1.0, 2))
	assert_null(battery.select_track([ballistic], Vector3.ZERO))
	coordinator.reset()
	coordinator.free()
	var specialized: WeaponMagazine = battery.magazines[&"high_speed_interceptor"]
	specialized.rounds = 1
	specialized.reserve = 0
	assert_eq(battery.munition_for_track(ballistic).id, &"high_speed_interceptor", "마지막 특수탄도 본래 방어 대상에는 사용합니다")
	var slow := _confirmed_track(Vector3(200, 150, 0))
	slow.classification = &"small_uav"
	slow.track_id = ballistic.track_id + 1
	assert_eq(battery.munition_for_track(slow).id, &"area_defense")
	battery.set_munition_mode(&"high_speed_interceptor")
	assert_eq(battery.munition_for_track(slow).id, &"high_speed_interceptor", "명시적 탄종 지정은 최후탄 보존보다 우선합니다")
	battery.set_munition_mode(&"auto")
	battery.magazines[&"area_defense"].rounds = 0
	battery.magazines[&"area_defense"].reserve = 0
	assert_null(battery.munition_for_track(slow), "자동 모드의 최후 특수탄은 저가 표적에 보존합니다")
	battery.set_priority_track(slow.track_id)
	assert_eq(battery.munition_for_track(slow).id, &"high_speed_interceptor")
	battery.set_priority_track(ballistic.track_id)
	assert_eq(battery.munition_for_track(ballistic).id, &"high_speed_interceptor")
	battery.set_munition_mode(&"area_defense")
	battery.magazines[&"area_defense"].rounds = 2
	assert_eq(battery.munition_for_track(ballistic).id, &"area_defense")

func test_high_speed_interceptor_leads_moving_track_and_launches_individual_rack_rounds() -> void:
	var target_position := Vector3(500.0, 600.0, 0.0)
	var target_velocity := Vector3(-120.0, -180.0, 70.0)
	var lead := INTERCEPT_GUIDANCE.lead_point(Vector3.ZERO, 520.0, target_position, target_velocity, 1.8)
	assert_lt(lead.x, target_position.x)
	assert_lt(lead.y, target_position.y)
	assert_gt(lead.z, target_position.z)
	var definition := SCENARIO.available_defenses[7] as MissileBatteryDefinition
	var battery := add_child_autofree(definition.scene.instantiate()) as MissileBattery
	battery.setup(71, definition)
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	battery.configure_combat(ThreatRegistry.new(), projectiles)
	var ballistic := _confirmed_track(target_position)
	ballistic.classification = &"ballistic_missile"
	ballistic.estimated_velocity = target_velocity
	var munition := battery.munition_for_track(ballistic)
	battery.magazines[munition.id].reserve = 0
	var rounds_before := battery.magazines[munition.id].rounds
	assert_true(battery._fire_round(ballistic, munition))
	assert_eq(projectiles.get_child_count(), 1)
	assert_eq(battery.interceptors.size(), 1)
	assert_eq(battery.magazines[munition.id].rounds, rounds_before - 1)
	assert_same(battery.munition_for_track(ballistic), munition)
	assert_true(battery._fire_round(ballistic, munition))
	assert_eq(projectiles.get_child_count(), 2)
	assert_eq(battery.interceptors.size(), 2)
	assert_eq(battery.magazines[munition.id].rounds, rounds_before - 2)
	assert_true(battery.magazines[munition.id].is_depleted())
	assert_eq(battery.critical_status_text(), "일부 탄종 고갈")
	assert_false(battery.combat_resource_depleted())
	var area: WeaponMagazine = battery.magazines[&"area_defense"]
	area.rounds = 0
	area.reserve = 0
	assert_eq(battery.critical_status_text(), "탄약 고갈")
	assert_true(battery.combat_resource_depleted())
	area.rounds = 1
	assert_eq(battery.critical_status_text(), "일부 탄종 고갈")
	area.rounds = 0
	battery.magazines[munition.id].rounds = 1
	assert_eq(battery.critical_status_text(), "일부 탄종 고갈", "첫 탄종 고갈은 전체 고갈이 아닙니다")
	assert_ne(battery.interceptors[0].global_position, battery.interceptors[1].global_position)

func test_missile_launch_sequence_and_interval_round_trip() -> void:
	var definition := SCENARIO.available_defenses[7] as MissileBatteryDefinition
	var battery := add_child_autofree(definition.scene.instantiate()) as MissileBattery
	battery.setup(72, definition)
	var projectiles := add_child_autofree(Node3D.new()) as Node3D
	battery.configure_combat(ThreatRegistry.new(), projectiles)
	var track := _confirmed_track(Vector3(500.0, 600.0, 0.0))
	track.classification = &"ballistic_missile"
	var munition := battery.munition_for_track(track)
	assert_true(battery._fire_round(track, munition))
	battery.launch_cooldown = definition.launch_interval
	var state := battery.capture_content_state()
	assert_eq(int(state.next_launch_sequence), 1)
	assert_eq(definition.runtime_state_validation_error(state), "")
	var restored := add_child_autofree(definition.scene.instantiate()) as MissileBattery
	restored.setup(72, definition)
	restored.restore_content_state(state)
	assert_eq(restored.next_launch_sequence, 1)
	assert_almost_eq(restored.launch_cooldown, definition.launch_interval, 0.001)
	var legacy_state := state.duplicate(true)
	legacy_state.erase("launch_cooldown")
	legacy_state["cooldown"] = 3.5
	restored.restore_content_state(legacy_state)
	assert_almost_eq(restored.launch_cooldown, definition.launch_interval, 0.001)

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

func test_engagement_reservation_blocks_overkill_then_expires_or_releases() -> void:
	var coordinator: EngagementCoordinator = autofree(EngagementCoordinator.new()) as EngagementCoordinator
	assert_true(coordinator.try_reserve(7, 11, 0.5, 2))
	assert_true(coordinator.try_reserve(7, 12, 0.5, 2))
	assert_false(coordinator.try_reserve(7, 13, 1.0, 2))
	assert_eq(coordinator.reservation_count(7), 2)
	assert_true(coordinator.has_reservation(7))
	var saved_state := coordinator.capture_state()
	coordinator.reset()
	assert_false(coordinator.has_reservation(7))
	coordinator.restore_state(saved_state)
	coordinator.gameplay_tick(0.49)
	assert_true(coordinator.has_reservation(7))
	coordinator.gameplay_tick(0.02)
	assert_false(coordinator.has_reservation(7))
	assert_true(coordinator.try_reserve(8, 11, 2.0))
	coordinator.release(8, 11)
	assert_false(coordinator.has_reservation(8))
	assert_true(coordinator.try_reserve(9, 11, 2.0, 2))
	assert_true(coordinator.try_reserve(9, 11, 2.0, 2))
	coordinator.release_one(9, 11)
	assert_eq(coordinator.reservation_count(9), 1)
	coordinator.release(9, 11)
	assert_false(coordinator.has_reservation(9))

func test_weapon_magazine_consumes_reloads_and_restores_finite_ammunition() -> void:
	var magazine := WeaponMagazine.new()
	magazine.setup(2, 3, 1.0)
	assert_true(magazine.consume())
	assert_true(magazine.consume())
	assert_false(magazine.can_fire())
	assert_true(magazine.is_reloading())
	magazine.gameplay_tick(0.6)
	var saved_state := magazine.capture_state()
	var restored := WeaponMagazine.new()
	restored.restore_state(saved_state)
	assert_almost_eq(restored.reload_remaining, 0.4, 0.0001)
	restored.gameplay_tick(0.4)
	assert_eq(restored.rounds, 2)
	assert_eq(restored.reserve, 1)
	assert_true(restored.consume())
	assert_true(restored.consume())
	restored.gameplay_tick(1.0)
	assert_eq(restored.rounds, 1)
	assert_eq(restored.reserve, 0)
	assert_eq(WeaponMagazine.validation_error(restored.capture_state()), "")
	var invalid_state := restored.capture_state()
	invalid_state.rounds = 99
	assert_ne(WeaponMagazine.validation_error(invalid_state), "")

func test_energy_weapon_charges_cools_and_recovers_from_overheat() -> void:
	var energy := EnergyWeaponState.new()
	energy.setup(20.0, 5.0, 10.0, 5.0, 2.0)
	assert_true(energy.consume(4.0))
	assert_true(energy.consume(4.0))
	assert_true(energy.overheated)
	energy.gameplay_tick(2.0, 0.5)
	assert_almost_eq(energy.energy, 17.0, 0.0001)
	assert_true(energy.overheated)
	energy.gameplay_tick(1.5, 0.5)
	assert_false(energy.overheated)
	var restored := EnergyWeaponState.new()
	restored.restore_state(energy.capture_state())
	assert_eq(EnergyWeaponState.validation_error(restored.capture_state()), "")
	var invalid_state := restored.capture_state()
	invalid_state.energy = 99.0
	assert_ne(EnergyWeaponState.validation_error(invalid_state), "")

func test_power_manager_allocates_finite_generation_capacity() -> void:
	var manager: PowerManager = autofree(PowerManager.new()) as PowerManager
	var facility: SupportFacility = autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	manager.register_asset(facility)
	var laser: HighEnergyLaser = autofree((SCENARIO.available_defenses[6] as HighEnergyLaserDefinition).scene.instantiate()) as HighEnergyLaser
	laser.setup(2, SCENARIO.available_defenses[6])
	manager.register_asset(laser)
	var microwave: HighPowerMicrowave = autofree((SCENARIO.available_defenses[9] as HighPowerMicrowaveDefinition).scene.instantiate()) as HighPowerMicrowave
	microwave.setup(3, SCENARIO.available_defenses[9])
	manager.register_asset(microwave)
	assert_eq(manager.total_demand(), 30.0)
	manager.begin_tick()
	assert_eq(manager.request_power(12.0), 12.0)
	assert_eq(manager.request_power(12.0), 8.0)
	assert_eq(manager.request_power(1.0), 0.0)

func test_support_and_power_managers_accept_capability_providers() -> void:
	var support: SupportManager = autofree(SupportManager.new()) as SupportManager
	var power: PowerManager = autofree(PowerManager.new()) as PowerManager
	var support_session: GameSession = autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	support.configure(support_session)
	var definition := DefenseDefinition.new()
	definition.maximum_integrity = 100.0
	var provider := add_child_autofree(CapabilityProviderDouble.new()) as CapabilityProviderDouble
	provider.setup(1, definition)
	var consumer := add_child_autofree(CapabilityConsumerDouble.new()) as CapabilityConsumerDouble
	consumer.setup(2, definition)
	consumer.global_position = Vector3(100.0, 0.0, 0.0)
	consumer.configure_support(support)
	support.register_asset(provider)
	support.register_asset(consumer)
	power.register_asset(provider)
	assert_same(support.service_facility_for(consumer), provider)
	assert_true(consumer.request_resupply())
	support.gameplay_tick(1.0)
	assert_true(consumer.replenished)
	assert_eq(power.generation_capacity(), 12.0)

func test_support_queue_preserves_work_and_uses_facility_capacity() -> void:
	var manager: SupportManager = autofree(SupportManager.new()) as SupportManager
	var support_session: GameSession = autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	manager.configure(support_session)
	var facility: SupportFacility = add_child_autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	var gun: CloseInGun = add_child_autofree((SCENARIO.available_defenses[4] as CloseInGunDefinition).scene.instantiate()) as CloseInGun
	gun.setup(2, SCENARIO.available_defenses[4])
	gun.configure_support(manager)
	manager.register_asset(facility)
	manager.register_asset(gun)
	gun.magazine.rounds = 0
	gun.magazine.reserve = 0
	assert_true(gun.request_resupply())
	assert_eq(support_session.budget, 98)
	assert_false(gun.request_resupply())
	assert_eq(support_session.budget, 98)
	assert_eq(manager.task_status(gun), "재보급 진행")
	manager.gameplay_tick(1.0)
	var saved_state := manager.capture_state()
	assert_almost_eq(float(saved_state.tasks[0].remaining_work), 8.0, 0.0001)
	manager.reset()
	manager.register_asset(facility)
	manager.register_asset(gun)
	manager.restore_state(saved_state)
	manager.gameplay_tick(2.0)
	assert_eq(gun.magazine.reserve, gun.magazine.reserve_capacity)
	assert_true(gun.magazine.is_reloading())
	gun.magazine.gameplay_tick(gun.magazine.reload_duration)
	assert_eq(gun.magazine.rounds, gun.magazine.capacity)
	assert_eq(manager.task_status(gun), "")

func _automatic_resupply_fixture() -> Dictionary:
	var manager := autofree(SupportManager.new()) as SupportManager
	var support_session := autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	manager.configure(support_session)
	var facility := add_child_autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	var definition := SCENARIO.available_defenses[7] as MissileBatteryDefinition
	var battery := add_child_autofree(definition.scene.instantiate()) as MissileBattery
	battery.setup(2, definition)
	battery.configure_support(manager)
	manager.register_asset(facility)
	manager.register_asset(battery)
	return {"manager": manager, "session": support_session, "facility": facility, "battery": battery}

func test_automatic_resupply_marker_reports_progress_or_waiting_instead_of_depletion() -> void:
	var fixture := _automatic_resupply_fixture()
	var manager: SupportManager = fixture.manager
	var battery: MissileBattery = fixture.battery
	var specialized: WeaponMagazine = battery.magazines[&"high_speed_interceptor"]
	specialized.rounds = 0
	specialized.reserve = 0
	assert_eq(battery.critical_status_text(), "일부 탄종 고갈")
	battery.set_automatic_resupply(true)
	assert_eq(battery.critical_status_text(), "재보급 대기")
	manager.gameplay_tick(0.1)
	assert_eq(battery.critical_status_text(), "재보급 중")
	(fixture.facility as DefenseUnit).global_position = Vector3(10000, 0, 0)
	assert_eq(battery.critical_status_text(), "재보급 대기")
	(fixture.facility as DefenseUnit).global_position = Vector3.ZERO
	for stock: WeaponMagazine in battery.magazines.values():
		stock.rounds = 0
		stock.reserve = 0
	assert_eq(battery.critical_status_text(), "재보급 중")
	battery.set_automatic_resupply(false)
	assert_eq(battery.critical_status_text(), "탄약 고갈")
	battery.set_automatic_resupply(true)
	manager.gameplay_tick(100.0)
	assert_eq(battery.critical_status_text(), "")

func test_automatic_resupply_detects_one_low_munition_and_never_double_charges() -> void:
	var fixture := _automatic_resupply_fixture()
	var manager: SupportManager = fixture.manager
	var battery: MissileBattery = fixture.battery
	var support_session: GameSession = fixture.session
	var specialized: WeaponMagazine = battery.magazines[&"high_speed_interceptor"]
	specialized.reserve = 0
	assert_false(battery.automatic_resupply_enabled())
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 0)
	battery.set_automatic_resupply(true)
	manager.gameplay_tick(0.0)
	assert_eq(support_session.budget, 100, "일시정지 중에는 자동 결제하지 않습니다")
	var cost := battery.resupply_cost()
	manager.gameplay_tick(0.1)
	assert_eq(manager.tasks.size(), 1)
	assert_eq(support_session.budget, 100 - cost)
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 1)
	assert_eq(support_session.budget, 100 - cost, "진행 중인 작업에 중복 결제하지 않습니다")
	battery.set_automatic_resupply(false)
	assert_eq(manager.tasks.size(), 1, "자동 요청 해제는 이미 결제한 작업을 취소하지 않습니다")
	manager.gameplay_tick(100.0)
	assert_eq(specialized.reserve, specialized.reserve_capacity)
	assert_eq(manager.tasks.size(), 0)
	battery.set_automatic_resupply(true)
	manager.gameplay_tick(1.0)
	assert_eq(support_session.budget, 100 - cost, "가득 찬 예비탄에는 지출하지 않습니다")

func test_automatic_resupply_retries_only_when_budget_coverage_and_relocation_allow() -> void:
	var fixture := _automatic_resupply_fixture()
	var manager: SupportManager = fixture.manager
	var battery: MissileBattery = fixture.battery
	var support_session: GameSession = fixture.session
	var specialized: WeaponMagazine = battery.magazines[&"high_speed_interceptor"]
	specialized.reserve = 0
	battery.set_automatic_resupply(true)
	battery.position.x = 1000.0
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 0)
	assert_eq(support_session.budget, 100)
	battery.position.x = 0.0
	support_session.budget = 0
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 0)
	support_session.budget = 100
	var relocation := autofree(RelocationManager.new()) as RelocationManager
	battery.relocation_manager = relocation
	relocation.tasks.append({"target_defense_id": battery.runtime_id, "remaining": 10.0})
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 0)
	relocation.tasks.clear()
	battery.active = false
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 0)
	battery.active = true
	manager.gameplay_tick(0.1)
	assert_eq(manager.tasks.size(), 0, "자동 요청 검사는 초당 한 번으로 제한합니다")
	manager.gameplay_tick(1.0)
	assert_eq(manager.tasks.size(), 1)
	assert_eq(support_session.budget, 100 - battery.resupply_cost())

func test_automatic_resupply_policy_restores_without_spending_and_rejects_non_ammo_assets() -> void:
	var fixture := _automatic_resupply_fixture()
	var manager: SupportManager = fixture.manager
	var battery: MissileBattery = fixture.battery
	var facility: DefenseUnit = fixture.facility
	var support_session: GameSession = fixture.session
	battery.set_automatic_resupply(true)
	manager.set_automatic_resupply(facility, true)
	var saved := manager.capture_state()
	assert_eq(saved.automatic_resupply_ids, [battery.runtime_id])
	manager.reset()
	assert_false(battery.automatic_resupply_enabled())
	manager.register_asset(battery)
	manager.register_asset(facility)
	manager.restore_state(saved)
	assert_true(battery.automatic_resupply_enabled())
	assert_false(facility.automatic_resupply_enabled())
	assert_eq(support_session.budget, 100)
	assert_eq(manager.tasks.size(), 0)

func test_support_tasks_require_a_nearby_operational_facility() -> void:
	var manager: SupportManager = autofree(SupportManager.new()) as SupportManager
	var support_session: GameSession = autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	manager.configure(support_session)
	var facility: SupportFacility = add_child_autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	var gun: CloseInGun = add_child_autofree((SCENARIO.available_defenses[4] as CloseInGunDefinition).scene.instantiate()) as CloseInGun
	gun.setup(2, SCENARIO.available_defenses[4])
	gun.configure_support(manager)
	manager.register_asset(facility)
	manager.register_asset(gun)
	gun.magazine.rounds = 0
	gun.magazine.reserve = 0
	gun.global_position = Vector3(facility.service_range() + 1.0, 0.0, 0.0)
	assert_false(gun.can_request_resupply())
	assert_false(gun.request_resupply())
	assert_eq(support_session.budget, 100)
	gun.global_position = Vector3(facility.service_range(), 0.0, 0.0)
	assert_true(gun.can_request_resupply())
	assert_true(gun.request_resupply())
	assert_eq(manager.service_facility_for(gun), facility)
	gun.global_position += Vector3.RIGHT
	assert_eq(manager.task_status(gun), "재보급 대기")
	manager.gameplay_tick(20.0)
	assert_eq(gun.magazine.reserve, 0)
	gun.global_position -= Vector3.RIGHT
	manager.gameplay_tick(3.0)
	assert_eq(gun.magazine.reserve, gun.magazine.reserve_capacity)
	assert_true(gun.receive_damage(20.0))
	gun.global_position += Vector3.RIGHT
	assert_false(gun.can_request_repair())
	assert_false(gun.request_repair())
	assert_eq(support_session.budget, 98)
	gun.global_position -= Vector3.RIGHT
	assert_true(gun.can_request_repair())
	assert_true(gun.request_repair())
	assert_eq(support_session.budget, 88)

func test_damage_reduces_capability_and_repair_shares_support_queue() -> void:
	var manager: SupportManager = autofree(SupportManager.new()) as SupportManager
	var support_session: GameSession = autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	manager.configure(support_session)
	var facility: SupportFacility = add_child_autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	var gun: CloseInGun = add_child_autofree((SCENARIO.available_defenses[4] as CloseInGunDefinition).scene.instantiate()) as CloseInGun
	gun.setup(2, SCENARIO.available_defenses[4])
	gun.configure_support(manager)
	manager.register_asset(facility)
	manager.register_asset(gun)
	assert_true(facility.receive_damage(50.0))
	assert_not_null(facility.damage_smoke)
	assert_gte((facility.damage_smoke.get_node("Smoke") as GPUParticles3D).amount, 40)
	assert_true((facility.damage_smoke.get_node("Fire") as GPUParticles3D).emitting)
	facility._process(0.0)
	var damage_label := facility.status_marker.get_node("Label") as Label3D
	assert_eq(damage_label.text, "손상")
	assert_true(damage_label.no_depth_test)
	assert_gte(damage_label.render_priority, 100)
	assert_eq(facility.operational_status_text(), "상태 성능저하 · 내구도 50%")
	assert_almost_eq(facility.support_capacity(), 2.0, 0.0001)
	assert_true(gun.receive_damage(50.0))
	assert_not_null(gun.damage_smoke)
	assert_almost_eq(gun.c2_link_range(), (SCENARIO.available_defenses[4] as CloseInGunDefinition).c2_range * 0.5, 0.0001)
	assert_true(gun.request_repair())
	assert_eq(support_session.budget, 90)
	assert_eq(manager.task_status(gun), "수리 진행")
	manager.gameplay_tick(1.0)
	var saved_tasks := manager.capture_state()
	assert_eq(saved_tasks.tasks[0].kind, SupportManager.REPAIR)
	manager.reset()
	manager.register_asset(facility)
	manager.register_asset(gun)
	manager.restore_state(saved_tasks)
	manager.gameplay_tick(2.9)
	assert_eq(gun.integrity, 50.0)
	manager.gameplay_tick(0.2)
	assert_eq(gun.integrity, gun.definition.maximum_integrity)
	assert_true(gun.active)
	assert_null(gun.damage_smoke)
	assert_eq(manager.task_status(gun), "")
	gun.magazine.rounds = 0
	gun.magazine.reserve = 0
	gun._process(0.0)
	assert_true(gun.status_marker.visible)
	var depleted_label := gun.status_marker.get_node("Label") as Label3D
	assert_eq(depleted_label.text, "탄약 고갈")
	assert_almost_eq(depleted_label.pixel_size, 0.001, 0.00001)
	gun.receive_damage(70.0)
	gun._process(0.0)
	assert_eq((gun.status_marker.get_node("Label") as Label3D).text, "×")

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
