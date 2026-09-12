extends GutTest

class CycleFixture:
	var cycle: DayNightCycle
	var sun: DirectionalLight3D
	var world: WorldEnvironment
	var field: Battlefield
	var sky: ShaderMaterial
	var ocean: ShaderMaterial

func test_sky_state_is_owned_per_world_and_restores_from_elapsed_time() -> void:
	var first := _cycle_fixture()
	var second := _cycle_fixture()
	assert_ne(first.sky, second.sky)
	first.cycle.apply_time(450.0, true)
	assert_eq(float(first.sky.get_shader_parameter("sky_clock")), 450.0)
	assert_eq(float(second.sky.get_shader_parameter("sky_clock")), 0.0)
	first.cycle.apply_time(0.0, true)
	for parameter: String in ["sky_clock", "sun_direction", "moon_direction", "daylight", "night_amount", "horizon_color", "zenith_color", "star_rotation"]:
		assert_eq(first.sky.get_shader_parameter(parameter), second.sky.get_shader_parameter(parameter), "복원된 sky parameter: " + parameter)

func test_celestial_motion_updates_without_waiting_for_lighting_interval() -> void:
	var fixture := _cycle_fixture()
	fixture.cycle.apply_time(450.0, true)
	assert_eq(fixture.sky.get_shader_parameter("sun_direction"), fixture.sun.basis.z.normalized())
	var moon_direction := fixture.sky.get_shader_parameter("moon_direction") as Vector3
	var moon_hour := fposmod(DayNightCycle.hour_at(450.0) + 12.0, 24.0)
	var expected_moon_direction := Basis.from_euler(DayNightCycle.orbit_rotation(moon_hour) * PI / 180.0).z.normalized()
	assert_almost_eq(moon_direction, expected_moon_direction, Vector3.ONE * 0.0001)
	assert_gt(moon_direction.y, 0.0)
	fixture.cycle.apply_time(450.0)
	assert_eq(float(fixture.sky.get_shader_parameter("sky_clock")), 450.0, "정지한 simulation clock은 구름도 정지시킵니다")
	fixture.cycle.apply_time(450.016)
	assert_almost_eq(float(fixture.sky.get_shader_parameter("sky_clock")), 450.016, 0.0001, "천체 운동은 조명 갱신 간격을 기다리지 않습니다")

func test_celestial_orbit_is_continuous_at_midnight() -> void:
	var before := Basis.from_euler(DayNightCycle.orbit_rotation(23.999) * PI / 180.0).z
	var after := Basis.from_euler(DayNightCycle.orbit_rotation(0.001) * PI / 180.0).z
	assert_lt(before.distance_to(after), 0.001)

func test_ocean_material_is_owned_per_world() -> void:
	var first := _cycle_fixture(true)
	var second := _cycle_fixture(true)
	assert_ne(first.ocean, second.ocean)
	first.cycle.apply_time(450.0, true)
	assert_eq(float(second.ocean.get_shader_parameter("daylight")), 1.0)

func test_ocean_and_sky_receive_the_same_haze_state() -> void:
	var fixture := _cycle_fixture(true)
	fixture.cycle.apply_time(450.0, true)
	for parameter: String in ["sun_direction", "horizon_color", "zenith_color", "daylight", "twilight"]:
		assert_eq(fixture.ocean.get_shader_parameter(parameter), fixture.sky.get_shader_parameter(parameter), "ocean/sky haze parameter: " + parameter)

func test_horizon_color_changes_without_large_twilight_steps() -> void:
	var fixture := _cycle_fixture()
	fixture.cycle.apply_time(250.0, true)
	var previous: Color = fixture.sky.get_shader_parameter("horizon_color")
	var maximum_step := 0.0
	for index: int in 400:
		var elapsed := 250.0 + (index + 1) * 0.1
		fixture.cycle.apply_time(elapsed, true)
		var horizon: Color = fixture.sky.get_shader_parameter("horizon_color")
		maximum_step = maxf(maximum_step, _color_distance(previous, horizon))
		previous = horizon
	assert_lt(maximum_step, 0.01, "250~290초 황혼 구간의 0.1초당 horizon 색 변화량")

func test_clock_wraps_and_repeats_saved_elapsed_time() -> void:
	assert_almost_eq(DayNightCycle.hour_at(0.0), 9.0, 0.001)
	assert_almost_eq(DayNightCycle.hour_at(450.0), 0.0, 0.001)
	assert_almost_eq(DayNightCycle.hour_at(720.0), 9.0, 0.001)
	assert_almost_eq(DayNightCycle.hour_at(999.0), DayNightCycle.hour_at(279.0), 0.001)

func test_night_lighting_is_local_and_environment_is_not_shared() -> void:
	var original := Environment.new()
	var fixture := _cycle_fixture(false, original)
	var day_energy := fixture.world.environment.ambient_light_energy
	assert_ne(fixture.world.environment, original)
	fixture.cycle.apply_time(450.0)
	assert_eq(fixture.cycle.night_amount, 1.0)
	assert_eq(fixture.sun.light_energy, 0.0)
	assert_false(fixture.sun.visible, "광량 0인 한밤중에는 태양과 그림자 pass를 제출하지 않습니다")
	assert_gt(fixture.world.environment.ambient_light_energy, 0.0)
	assert_lt(fixture.world.environment.ambient_light_energy, day_energy)
	fixture.cycle.apply_time(720.0)
	assert_eq(fixture.cycle.night_amount, 0.0)
	assert_true(fixture.sun.visible)
	assert_almost_eq(fixture.world.environment.ambient_light_energy, day_energy, 0.001)

func test_smoke_projection_is_local_preserves_sun_and_retires_when_unused() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	var sun := DirectionalLight3D.new()
	field.add_child(sun)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	field.configure_smoke_shadows(sun)
	var projection := field.smoke_shadow_projection
	projection.update_projection()
	assert_eq(projection.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(sun.shadow_caster_mask & SmokeShadowFactory.SMOKE_LAYER, 0)
	assert_ne(sun.shadow_caster_mask & 1, 0, "건물 등 일반 물체의 그림자는 그대로 유지합니다")
	var caster := MeshInstance3D.new()
	caster.mesh = SphereMesh.new()
	field.add_child(caster)
	SmokeShadowFactory.register_caster(caster)
	projection.update_projection()
	assert_eq(projection.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_almost_eq(sun.light_energy, 1.2, 0.0001)
	assert_gt(float(projection.receivers[0].get_shader_parameter("smoke_shadow_strength")), 0.0)
	assert_lt(float(projection.receivers[0].get_shader_parameter("smoke_shadow_strength")), 1.0)
	assert_false(SmokeShadowFactory.has_visible_casters(World3D.new()))
	caster.hide()
	projection.update_projection()
	assert_eq(projection.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(float(projection.receivers[0].get_shader_parameter("smoke_shadow_strength")), 0.0)
	caster.show()
	sun.hide()
	projection.update_projection()
	assert_eq(projection.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)

func test_twilight_shadows_fade_continuously_in_both_directions() -> void:
	var fixture := _cycle_fixture()
	assert_eq(fixture.sun.shadow_opacity, 1.0)
	for interval: Vector2 in [Vector2(244.0, 272.0), Vector2(628.0, 656.0)]:
		fixture.cycle.apply_time(interval.x, true)
		var previous := fixture.sun.shadow_opacity
		var maximum_step := 0.0
		var monotonic := true
		var always_visible := true
		var always_enabled := true
		for index: int in 280:
			fixture.cycle.apply_time(interval.x + (index + 1) * 0.1, true)
			var opacity := fixture.sun.shadow_opacity
			always_enabled = always_enabled and fixture.sun.shadow_enabled
			always_visible = always_visible and fixture.sun.visible
			maximum_step = maxf(maximum_step, absf(opacity - previous))
			monotonic = monotonic and (opacity <= previous if interval.x < 300.0 else opacity >= previous)
			previous = opacity
		var case_name := "%d~%d초" % [int(interval.x), int(interval.y)]
		assert_true(always_enabled, case_name + " 황혼 중 shadow mode를 바꾸지 않습니다")
		assert_true(always_visible, case_name + " 가시적인 태양을 숨기지 않습니다")
		assert_true(monotonic, case_name + " shadow opacity가 한 방향으로 변합니다")
		assert_lt(maximum_step, 0.01, case_name + " 0.1초당 shadow opacity 변화량")
	fixture.cycle.apply_time(450.0)
	assert_eq(fixture.sun.shadow_opacity, 0.0)

func _cycle_fixture(with_ocean: bool = false, environment: Environment = null) -> CycleFixture:
	var fixture := CycleFixture.new()
	fixture.field = add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield if with_ocean else autofree(Battlefield.new()) as Battlefield
	fixture.cycle = add_child_autofree(DayNightCycle.new()) as DayNightCycle
	fixture.sun = add_child_autofree(DirectionalLight3D.new()) as DirectionalLight3D
	fixture.world = add_child_autofree(WorldEnvironment.new()) as WorldEnvironment
	fixture.world.environment = Environment.new() if environment == null else environment
	fixture.cycle.configure(fixture.sun, fixture.world, fixture.field)
	fixture.sky = fixture.world.environment.sky.sky_material as ShaderMaterial
	if fixture.field.ocean != null:
		fixture.ocean = fixture.field.ocean.mesh.surface_get_material(0) as ShaderMaterial
	return fixture

func _color_distance(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_to(Vector3(second.r, second.g, second.b))
