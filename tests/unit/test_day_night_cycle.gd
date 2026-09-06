extends GutTest

func test_clock_wraps_and_repeats_saved_elapsed_time() -> void:
	assert_almost_eq(DayNightCycle.hour_at(0.0), 9.0, 0.001)
	assert_almost_eq(DayNightCycle.hour_at(450.0), 0.0, 0.001)
	assert_almost_eq(DayNightCycle.hour_at(720.0), 9.0, 0.001)
	assert_almost_eq(DayNightCycle.hour_at(999.0), DayNightCycle.hour_at(279.0), 0.001)

func test_night_lighting_is_local_and_environment_is_not_shared() -> void:
	var cycle := DayNightCycle.new()
	var sun := DirectionalLight3D.new()
	var world := WorldEnvironment.new()
	var field := Battlefield.new()
	var original := Environment.new()
	world.environment = original
	cycle.configure(sun, world, field)
	var day_energy := world.environment.ambient_light_energy
	assert_ne(world.environment, original)
	cycle.apply_time(450.0)
	assert_eq(cycle.night_amount, 1.0)
	assert_eq(sun.light_energy, 0.0)
	assert_false(sun.visible, "광량 0인 한밤중에는 태양과 그림자 pass를 제출하지 않습니다")
	assert_gt(world.environment.ambient_light_energy, 0.0)
	assert_lt(world.environment.ambient_light_energy, day_energy)
	cycle.apply_time(720.0)
	assert_eq(cycle.night_amount, 0.0)
	assert_true(sun.visible)
	assert_almost_eq(world.environment.ambient_light_energy, day_energy, 0.001)
	cycle.free()
	sun.free()
	world.free()
	field.free()

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
	var cycle := DayNightCycle.new()
	var sun := DirectionalLight3D.new()
	var world := WorldEnvironment.new()
	var field := Battlefield.new()
	world.environment = Environment.new()
	cycle.configure(sun, world, field)
	assert_eq(sun.shadow_opacity, 1.0)
	for interval: Vector2 in [Vector2(244.0, 272.0), Vector2(628.0, 656.0)]:
		cycle.apply_time(interval.x, true)
		var previous := sun.shadow_opacity
		for index: int in 280:
			cycle.apply_time(interval.x + (index + 1) * 0.1, true)
			var opacity := sun.shadow_opacity
			assert_true(sun.shadow_enabled, "No shadow mode switch at twilight")
			assert_true(sun.visible, "가시적인 황혼 구간에서는 태양을 숨기지 않습니다")
			assert_lt(absf(opacity - previous), 0.01, "No opacity jump")
			if interval.x < 300.0:
				assert_lte(opacity, previous)
			else:
				assert_gte(opacity, previous)
			previous = opacity
	cycle.apply_time(450.0)
	assert_eq(sun.shadow_opacity, 0.0)
	cycle.free()
	sun.free()
	world.free()
	field.free()
