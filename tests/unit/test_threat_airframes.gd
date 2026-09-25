extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func _spawn(definition: ThreatDefinition) -> AttackUav:
	var threat := add_child_autofree(definition.scene.instantiate()) as AttackUav
	threat.setup(1, definition)
	threat.set_process(false)
	threat.set_physics_process(false)
	return threat

func _definitions() -> Array[AttackUavDefinition]:
	var result: Array[AttackUavDefinition] = []
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		if not entry.threat_definition is AttackUavDefinition:
			continue
		var probe := entry.threat_definition.scene.instantiate()
		if probe is AttackUav:
			result.append(entry.threat_definition as AttackUavDefinition)
		probe.free()
	return result

func test_engine_glows_keep_their_flame_color_under_paint() -> void:
	for definition: AttackUavDefinition in _definitions():
		var threat := _spawn(definition)
		for child: Node in threat.body.get_children():
			if child is MeshInstance3D:
				var finish := (child as MeshInstance3D).get_active_material(0) as StandardMaterial3D
				if finish != null and finish.emission_enabled:
					assert_ne(finish.albedo_color, definition.visual_color, "%s %s" % [definition.id, child.name])

func test_painted_airframes_keep_distinct_part_tones() -> void:
	for definition: AttackUavDefinition in _definitions():
		var threat := _spawn(definition)
		var airframe := threat.body.get_node_or_null("Airframe") as MeshInstance3D
		assert_not_null(airframe, String(definition.id))
		if airframe == null:
			continue
		var paint := airframe.get_active_material(0) as StandardMaterial3D
		assert_eq(paint.albedo_color, definition.visual_color, String(definition.id))
		assert_true(paint.vertex_color_use_as_albedo, String(definition.id))
		var tones: Dictionary[Color, bool] = {}
		for color: Color in airframe.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			tones[color] = true
		assert_gte(tones.size(), 3, "%s: 동체·어두운 부품·표식 명암이 구분됩니다" % definition.id)

func test_missile_families_have_their_own_silhouettes() -> void:
	var cruise := preload("res://enemy/cruise_missile/cruise_missile.tres") as ThreatDefinition
	var ballistic := preload("res://enemy/ballistic_missile/ballistic_missile.tres") as ThreatDefinition
	var rocket := preload("res://enemy/rocket_salvo/rocket.tres") as ThreatDefinition
	var meshes: Array[Mesh] = []
	for definition: ThreatDefinition in [cruise, ballistic, rocket]:
		meshes.append((_spawn(definition as AttackUavDefinition).body.get_node("Airframe") as MeshInstance3D).mesh)
	assert_ne(meshes[0], meshes[1])
	assert_ne(meshes[0], meshes[2])
	assert_ne(meshes[1], meshes[2])
	assert_lt(meshes[2].get_aabb().size.x, meshes[0].get_aabb().size.x, "로켓은 순항미사일 주익이 없는 가는 동체입니다")

func test_resolution_policy_is_independent_of_sensor_classification() -> void:
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		var definition := entry.threat_definition as AttackUavDefinition
		if definition == null or definition.movement.mode != ThreatMovementDefinition.Mode.ALTITUDE_HOLD:
			continue
		assert_not_null(definition.resolution_profile, "%s 항공체에 추락 정책이 필요합니다" % definition.id)
		if definition.resolution_profile != null:
			assert_true(definition.resolution_profile.leave_wreck, "%s 격추 시 잔해가 추락해야 합니다" % definition.id)
	var aircraft := preload("res://enemy/strike_aircraft/battery_strike_aircraft.tres").duplicate(true) as ThreatDefinition
	assert_true(aircraft.resolution_profile.leave_wreck)
	assert_true(aircraft.has_resolution_explosion())
	aircraft.signature_class = &"bird"
	assert_true(aircraft.has_resolution_explosion(), "센서 분류 변경은 파괴 연출을 변경하지 않습니다")
	var bird := _ambient_definition(&"bird_contact").duplicate(true) as ThreatDefinition
	bird.signature_class = &"aircraft"
	assert_false(bird.has_resolution_explosion())
	assert_false(bird.resolution_profile.wreck_smoke)
	assert_false(bird.resolution_profile.landing_flash)
	assert_eq(bird.validation_error(), "")
	assert_eq(aircraft.validation_error(), "")

func _ambient_definition(id: StringName) -> ThreatDefinition:
	for definition: ThreatDefinition in SCENARIO.ambient_contacts:
		if definition.id == id:
			return definition
	fail_test("주변 접촉 정의를 찾지 못했습니다: %s" % id)
	return null
