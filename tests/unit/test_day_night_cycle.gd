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
	assert_gt(world.environment.ambient_light_energy, 0.0)
	assert_lt(world.environment.ambient_light_energy, day_energy)
	cycle.apply_time(720.0)
	assert_eq(cycle.night_amount, 0.0)
	assert_almost_eq(world.environment.ambient_light_energy, day_energy, 0.001)
	cycle.free()
	sun.free()
	world.free()
	field.free()

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
