extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_each_battlefield_has_a_water_route_between_the_fog_and_a_coastal_berth() -> void:
	for layout_id: StringName in [&"rugged_harbor", &"island_city", &"valley_corridor", &"coastal_plain"]:
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.selected_battlefield_layout_id = layout_id
		var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
		field.build(scenario)
		var route := HarborRoute.plan(field)
		assert_not_null(route, String(layout_id))
		if route == null:
			continue
		assert_gt(route.inbound_duration, 90.0, "%s: 화물선이 수 km를 비현실적으로 질주하지 않습니다" % layout_id)
		assert_gt(route.outbound_duration, 90.0, String(layout_id))
		assert_gt(Vector2(route.inbound[0].x, route.inbound[0].z).length(), scenario.battlefield_size * 2.2, "%s: 불투명 연무 바깥에서 출발합니다" % layout_id)
		assert_almost_eq(route.inbound[route.inbound.size() - 1], Vector3(route.berth.x, route.sea_level, route.berth.y), Vector3.ONE * 0.01)
		assert_almost_eq(route.outbound[0], route.inbound[route.inbound.size() - 1], Vector3.ONE * 0.01)
		var inbound_direction := (route.inbound[route.inbound.size() - 1] - route.inbound[route.inbound.size() - 2]).normalized()
		assert_gt(-route.inbound_pose(route.inbound_duration).basis.z.dot(inbound_direction), 0.99, "%s: 선수는 접안 방향을 향합니다" % layout_id)
		for index: int in range(0, route.inbound.size(), 8):
			var point := route.inbound[index]
			if not (field.terrain_height(point.x, point.z) < route.sea_level - HarborRoute.MINIMUM_WATER_DEPTH):
				fail_test("%s: inbound %d crosses shallow water" % [layout_id, index])
				return
		for index: int in range(0, route.outbound.size(), 8):
			var point := route.outbound[index]
			if not (field.terrain_height(point.x, point.z) < route.sea_level - HarborRoute.MINIMUM_WATER_DEPTH):
				fail_test("%s: outbound %d crosses shallow water" % [layout_id, index])
				return

func test_delivery_occurs_after_docking_and_is_reconstructed_from_operation_time() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var session := add_child_autofree(GameSession.new()) as GameSession
	session.reset(100, 90.0, 180)
	var port := add_child_autofree(HarborPort.new()) as HarborPort
	assert_true(port.configure(field, session))
	if port.route == null:
		return
	session.external_regular_support = true
	session.defense_count = 1
	assert_true(session.start_defense())
	port.update_at_time(80.0)
	assert_true(port.ships.has(1))
	var vessel := port.ships[1]
	assert_lt(vessel.global_position.distance_to(Vector3(port.route.berth.x, port.route.sea_level, port.route.berth.y)), 1.0)
	assert_true(port.ships.has(2))
	assert_gt(port.ships[2].global_position.distance_to(vessel.global_position), CargoShip.HULL_LENGTH * 2.0)
	assert_eq(session.budget, 100)
	session.gameplay_delta(90.0)
	port.update_at_time(session.survival_time)
	assert_eq(session.budget, 280)
	assert_eq(session.support_payment_count, 1)
	var saved_time := session.survival_time
	var dock_position := vessel.global_position
	port.update_at_time(saved_time + 20.0)
	assert_gt(port.ships[1].global_position.distance_to(dock_position), 1.0)
	assert_false(port.ships[1].cargo_containers[0].visible)
	var state := session.capture_state()
	port.free()
	session.restore_state(state)
	var restored_port := add_child_autofree(HarborPort.new()) as HarborPort
	assert_true(restored_port.configure(field, session))
	assert_true(restored_port.ships.has(1))
	assert_almost_eq(restored_port.ships[1].global_position, dock_position, Vector3.ONE * 0.5)

func test_port_impact_interrupts_deliveries_without_city_damage_and_restores_repair_time() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var session := add_child_autofree(GameSession.new()) as GameSession
	session.reset(100, 90.0, 180)
	var city := add_child_autofree(SCENARIO.objective_definition.scene.instantiate()) as ProtectedObjective
	city.setup(1, SCENARIO.objective_definition)
	var port := add_child_autofree(HarborPort.new()) as HarborPort
	assert_true(port.configure(field, session))
	assert_eq(port.identity_marker.icon.texture, HarborPort.IDENTITY_ICON)
	assert_eq(port.identity_marker.icon.texture.get_size(), Vector2(48, 48))
	assert_eq(port.identity_marker.icon.modulate, HarborPort.IDENTITY_COLOR)
	assert_false(port.identity_marker.condition_frame.visible)
	assert_false(port.identity_marker.reload_background.visible)
	assert_false(port.damage_smoke.visible)
	city.impact_redirect = Callable(port, "try_apply_impact")
	session.external_regular_support = true
	session.defense_count = 1
	assert_true(session.start_defense())
	assert_true(city.apply_surface_impact(30, port.strike_target()))
	assert_eq(city.current_integrity, city.definition.maximum_integrity)
	assert_false(port.operational)
	assert_true(port.damage_smoke.visible)
	assert_true(port.damage_smoke.smoke.emitting)
	assert_true(port.identity_marker.condition_frame.visible)
	assert_eq(port.identity_marker.condition_frame.texture, UnitIdentityMarker.DISABLED_FRAME)
	assert_true(port.identity_marker.reload_background.visible)
	session.gameplay_delta(90.0)
	port.update_at_time(session.survival_time)
	assert_true(port.identity_marker.reload_fill.visible)
	assert_almost_eq(port.identity_marker.reload_fill.region_rect.size.x, 20.0, 0.1)
	assert_eq(session.budget, 100)
	assert_true(port.ships[1].cargo_containers[0].visible)
	var harbor_state := port.capture_state()
	var session_state := session.capture_state()
	port.free()
	session.restore_state(session_state)
	var restored_port := add_child_autofree(HarborPort.new()) as HarborPort
	assert_true(restored_port.configure(field, session))
	restored_port.restore_state(harbor_state)
	assert_eq(restored_port.window_material.get_shader_parameter("damaged_building_count"), 1, "복원된 폐쇄 항구는 불빛이 꺼져 있습니다")
	assert_false(restored_port.operational)
	assert_true(restored_port.damage_smoke.visible)
	assert_true(restored_port.identity_marker.condition_frame.visible)
	assert_almost_eq(restored_port.identity_marker.reload_fill.region_rect.size.x, 20.0, 0.1)
	session.gameplay_delta(90.0)
	assert_true(restored_port.operational)
	restored_port.update_at_time(session.survival_time)
	assert_false(restored_port.identity_marker.condition_frame.visible)
	assert_false(restored_port.identity_marker.reload_background.visible)
	assert_false(restored_port.damage_smoke.visible)
	assert_false(restored_port.damage_smoke.smoke.emitting)
	assert_false(restored_port.damage_smoke.fire.emitting)
	assert_eq(session.budget, 280)
	assert_eq(session.support_payment_count, 1)
	city.impact_redirect = Callable(restored_port, "try_apply_impact")
	session.gameplay_delta(20.0)
	assert_true(city.apply_surface_impact(30, restored_port.strike_target()))
	assert_true(restored_port.damage_smoke.visible, "재피격 시 연기가 다시 시작됩니다")
	session.gameplay_delta(100.0)
	restored_port.update_at_time(session.survival_time)
	assert_true(restored_port.ships[1].cargo_containers[0].visible, "이전 중단 배송의 화물은 새 피격 후에도 복원되지 않습니다")
	assert_false(restored_port.ships[2].cargo_containers[0].visible, "이미 하역한 선박의 화물은 새 피격으로 되돌아오지 않습니다")

func test_voyages_use_separate_water_approaches_and_turn_continuously() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var route := HarborRoute.plan(field)
	var variants := route.variants(field)
	assert_gt(variants.size(), 1, "먼바다 접근 항로가 분산됩니다")
	assert_gt(variants[0].inbound[0].distance_to(variants[-1].inbound[0]), 100.0)
	for voyage: HarborRoute in variants:
		for entering: bool in [true, false]:
			var times := voyage.inbound_times if entering else voyage.outbound_times
			for index: int in range(1, times.size() - 1):
				var before := voyage.inbound_pose(times[index] - 0.001) if entering else voyage.outbound_pose(times[index] - 0.001)
				var after := voyage.inbound_pose(times[index] + 0.001) if entering else voyage.outbound_pose(times[index] + 0.001)
				if not (before.basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion()) < 0.002):
					fail_test("항로 %d 진입 %s 표본 %d에서 방향이 불연속입니다" % [variants.find(voyage), entering, index])
					return
				if not (field.terrain_height(after.origin.x, after.origin.z) < voyage.sea_level - HarborRoute.MINIMUM_WATER_DEPTH):
					fail_test("항로 %d 진입 %s 표본 %d에서 수심이 부족합니다" % [variants.find(voyage), entering, index])
					return
		var dock := voyage.inbound_pose(voyage.inbound_duration)
		var departure := voyage.outbound_pose(0.0)
		assert_almost_eq(dock.basis.z, departure.basis.z, Vector3.ONE * 0.0001, "접안과 출항 사이에 선수가 튀지 않습니다")

func test_ship_haze_fades_all_surfaces_without_changing_cargo_or_other_ships() -> void:
	var ship := add_child_autofree(CargoShip.new()) as CargoShip
	var other := add_child_autofree(CargoShip.new()) as CargoShip
	ship.configure_haze(1000.0)
	other.configure_haze(1000.0)
	ship.set_cargo_remaining(0.5)
	ship.position = Vector3(1600, 0, 0)
	ship.refresh_haze()
	assert_gt(ship.haze.opacity, 0.0)
	assert_lt(ship.haze.opacity, 1.0)
	for surface: DistantContactHaze.SurfaceFade in ship.haze.surfaces:
		assert_almost_eq(surface.faded.albedo_color.a, surface.alpha * ship.haze.opacity, 0.0001)
	assert_eq(other.haze.opacity, 1.0, "공유 모델을 쓰는 다른 배는 흐려지지 않습니다")
	ship.position = Vector3(2300, 0, 0)
	ship.refresh_haze()
	assert_false(ship.visible, "연무 밖의 선박과 항적은 보이지 않습니다")
	ship.position = Vector3.ZERO
	ship.refresh_haze()
	assert_true(ship.visible)
	assert_true(ship.cargo_containers[0].visible)
	assert_false(ship.cargo_containers[-1].visible, "안개 복귀가 하역한 화물을 다시 표시하지 않습니다")

func test_terminal_lights_follow_night_and_go_dark_until_repair_completes() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var session := add_child_autofree(GameSession.new()) as GameSession
	session.reset(100, 90.0, 180)
	var port := add_child_autofree(HarborPort.new()) as HarborPort
	assert_true(port.configure(field, session))
	field.set_night_amount(1.0)
	assert_eq(port.window_material.get_shader_parameter("night_amount"), 1.0)
	assert_eq(port.window_material.get_shader_parameter("damaged_building_count"), 0)
	session.external_regular_support = true
	session.defense_count = 1
	assert_true(session.start_defense())
	assert_true(port.try_apply_impact(30, port.strike_target()))
	assert_eq(port.window_material.get_shader_parameter("damaged_building_count"), 1, "피격 후 불빛이 꺼집니다")
	session.gameplay_delta(HarborPort.EMERGENCY_REPAIR_SECONDS)
	port.update_at_time(session.survival_time)
	assert_eq(port.window_material.get_shader_parameter("damaged_building_count"), 0, "복구 후 불빛이 다시 켜집니다")

func test_thin_harbor_detail_hands_over_to_thick_members_at_one_camera_distance() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var session := add_child_autofree(GameSession.new()) as GameSession
	session.reset(100, 90.0, 180)
	var port := add_child_autofree(HarborPort.new()) as HarborPort
	assert_true(port.configure(field, session))
	var near := port.get_node("TerminalDetailNear") as MeshInstance3D
	var far := port.get_node("TerminalDetailFar") as MeshInstance3D
	assert_gt(near.visibility_range_end, 0.0)
	assert_eq(far.visibility_range_begin, near.visibility_range_end, "원거리 형상은 세부 형상이 사라지는 거리에서 나타납니다")
	assert_eq(far.custom_aabb, near.custom_aabb, "두 단계는 같은 기준 거리로 전환됩니다")

func _triangle_count(mesh: ArrayMesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	var indices = arrays[Mesh.ARRAY_INDEX]
	return (indices as PackedInt32Array).size() / 3 if indices != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

func test_same_colored_parts_keep_every_triangle_when_merged() -> void:
	var loose := SurfaceTool.new()
	loose.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in [Vector3.ZERO, Vector3.UP, Vector3.RIGHT, Vector3.RIGHT, Vector3.UP, Vector3(1, 1, 0)]:
		loose.add_vertex(vertex)
	loose.generate_normals()
	var geometry := HarborGeometry.new()
	geometry.append(loose.commit(), Transform3D.IDENTITY, "294552")
	geometry.box(Vector3.ONE, Vector3(5, 0, 0), "294552")
	var merged := geometry.mesh()
	assert_eq(merged.get_surface_count(), 1)
	assert_eq(_triangle_count(merged, 0), 2 + 12, "색이 같은 인덱스 없는 선체 면과 상자가 모두 그려집니다")

func test_cargo_ship_hull_sides_face_outward() -> void:
	var ship := add_child_autofree(CargoShip.new()) as CargoShip
	var hull := (ship.get_node("SculptedHullAndRails") as MeshInstance3D).mesh as ArrayMesh
	var outward := 0
	var inward := 0
	for surface: int in hull.get_surface_count():
		var arrays := hull.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle: int in range(0, indices.size(), 3):
			var corners := [indices[triangle], indices[triangle + 1], indices[triangle + 2]]
			var center := (vertices[corners[0]] + vertices[corners[1]] + vertices[corners[2]]) / 3.0
			if absf(center.x) < CargoShip.HULL_WIDTH * 0.4 or center.y > 4.7 or absf(center.z) > 30.0:
				continue
			# Generated normals follow the front face, so they must point away from the keel.
			var normal: Vector3 = normals[corners[0]] + normals[corners[1]] + normals[corners[2]]
			if normal.x * signf(center.x) > 0.0:
				outward += 1
			else:
				inward += 1
	assert_gt(outward, 0, "측면 선체 삼각형이 존재합니다")
	assert_eq(inward, 0, "측면 선체는 바깥에서 보입니다")
