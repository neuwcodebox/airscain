extends GutTest

const BATTLEFIELD_SCENE := preload("res://world/battlefield.tscn")
const CITY_SCENE := preload("res://world/objective/city/city_objective.tscn")
const BATTERY_SCENE := preload("res://defense/missile_battery/missile_battery.tscn")
const SCENARIO := preload("res://main/first_scenario.tres")
const INTERCEPT_GUIDANCE := preload("res://defense/intercept_guidance.gd")

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

func test_interceptor_seeker_can_be_defeated_by_finite_countermeasure() -> void:
	var registry := ThreatRegistry.new()
	var threat := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var threat_definition := ThreatDefinition.new()
	threat_definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	threat_definition.flare_effectiveness = 1.0
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
	assert_true(interceptor.is_queued_for_deletion())
	assert_eq(threat.countermeasure_charges_remaining, 0)
	assert_eq(threat.health, 1.0)

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
	assert_eq(battery.munition_for_track(ballistic).id, &"area_defense")
	battery.set_priority_track(ballistic.track_id)
	assert_eq(battery.munition_for_track(ballistic).id, &"high_speed_interceptor")
	battery.set_munition_mode(&"area_defense")
	assert_eq(battery.munition_for_track(ballistic).id, &"area_defense")

func test_high_speed_interceptor_leads_moving_track_and_launches_configured_salvo() -> void:
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
	var rounds_before := battery.magazines[munition.id].rounds
	battery._launch_salvo(ballistic, munition, munition.salvo_size)
	assert_eq(projectiles.get_child_count(), 2)
	assert_eq(battery.interceptors.size(), 2)
	assert_eq(battery.magazines[munition.id].rounds, rounds_before - 2)
	assert_ne(battery.interceptors[0].global_position, battery.interceptors[1].global_position)

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
	manager.begin_tick()
	assert_eq(manager.request_power(12.0), 12.0)
	assert_eq(manager.request_power(12.0), 8.0)
	assert_eq(manager.request_power(1.0), 0.0)

func test_support_queue_preserves_work_and_uses_facility_capacity() -> void:
	var manager: SupportManager = autofree(SupportManager.new()) as SupportManager
	var support_session: GameSession = autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	manager.configure(support_session)
	var facility: SupportFacility = autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	var gun: CloseInGun = autofree((SCENARIO.available_defenses[4] as CloseInGunDefinition).scene.instantiate()) as CloseInGun
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

func test_damage_reduces_capability_and_repair_shares_support_queue() -> void:
	var manager: SupportManager = autofree(SupportManager.new()) as SupportManager
	var support_session: GameSession = autofree(GameSession.new()) as GameSession
	support_session.reset(100)
	manager.configure(support_session)
	var facility: SupportFacility = autofree(SupportFacility.new()) as SupportFacility
	facility.setup(1, SCENARIO.available_defenses[5])
	var gun: CloseInGun = autofree((SCENARIO.available_defenses[4] as CloseInGunDefinition).scene.instantiate()) as CloseInGun
	gun.setup(2, SCENARIO.available_defenses[4])
	gun.configure_support(manager)
	manager.register_asset(facility)
	manager.register_asset(gun)
	assert_true(facility.receive_damage(50.0))
	assert_not_null(facility.damage_smoke)
	assert_gte((facility.damage_smoke.get_node("Smoke") as GPUParticles3D).amount, 40)
	assert_true((facility.damage_smoke.get_node("Fire") as GPUParticles3D).emitting)
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
	assert_eq((gun.status_marker.get_node("Label") as Label3D).text, "탄")
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
