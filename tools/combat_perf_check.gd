extends SceneTree
## Fixed-seed CPU workload; --render samples a frozen Compatibility scene.
## Run with --audio-driver Dummy. --faded fixes smoke age at 15s instead of 6s;
## --no-smoke-shadows isolates shadow cost. Compare identical options/resolution.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var world := preload("res://world/battlefield.tscn").instantiate() as Battlefield
	root.add_child(world)
	world.build(preload("res://main/first_scenario.tres"))
	var registry := ThreatRegistry.new()
	var definition := preload("res://enemy/attack_uav/attack_uav.tres")
	for index: int in 60:
		var target := ThreatUnit.new()
		world.add_child(target)
		target.setup(index, definition)
		target.health = 1000000
		target.position = Vector3(-180 + index * 6, 110 + index % 4 * 20, -100)
		registry.add(target)
	var guns: Array[GunfireRuntime] = []
	for index: int in 12:
		var gun := GunfireRuntime.new()
		world.add_child(gun)
		gun.battlefield = world
		gun.registry = registry
		guns.append(gun)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71019
	var gun_definition := preload("res://defense/close_in_gun/close_in_gun.tres")
	var samples: Array[float] = []
	for frame: int in 160:
		if frame % 14 == 0:
			for index: int in guns.size():
				guns[index].enqueue(Vector3(-200 + index * 30, 8, 100), Vector3(0, 110, -100), Vector3.ZERO, 0.8, 1.0, gun_definition, rng)
		var start := Time.get_ticks_usec()
		for gun: GunfireRuntime in guns:
			gun.gameplay_tick(0.02)
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	_report("gun_12_targets_60", samples)
	var trails: Array[LingeringSmokeTrail] = []
	var template := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate()
	var puff_mesh := (template.get_node("SmokeTrail") as LingeringSmokeTrail).puff_mesh
	template.free()
	for index: int in 24:
		var trail := LingeringSmokeTrail.new()
		trail.puff_mesh = puff_mesh
		trail.amount = 1024
		trail.sample_spacing = 1.0
		world.add_child(trail)
		trail.set_process(false)
		trail.sample_world_segment(Vector3(-400, 30 + index * 3, -200), Vector3(400, 30 + index * 3, -200))
		trails.append(trail)
	samples.clear()
	for frame: int in 90:
		var start := Time.get_ticks_usec()
		for trail: LingeringSmokeTrail in trails:
			trail._process(1.0 / 15.0)
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	_report("smoke_24_puffs_19200", samples)
	if OS.get_cmdline_user_args().has("--render"):
		if OS.get_cmdline_user_args().has("--no-city"):
			world.city_visuals.hide()
		if OS.get_cmdline_user_args().has("--no-smoke"):
			for trail: LingeringSmokeTrail in trails:
				trail.hide()
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(0, 300, 450)
		camera.look_at(Vector3(0, 40, -180))
		camera.current = true
		var light := DirectionalLight3D.new()
		world.add_child(light)
		light.rotation_degrees = Vector3(-55, -25, 0)
		light.shadow_enabled = true
		# Freeze simulation ages so identical geometry is measured every frame.
		if OS.get_cmdline_user_args().has("--faded"):
			for trail: LingeringSmokeTrail in trails:
				trail._process(9.0)
		if OS.get_cmdline_user_args().has("--no-smoke-shadows"):
			for trail: LingeringSmokeTrail in trails:
				trail.shadow_particles.hide()
		samples.clear()
		for frame: int in 120:
			var start := Time.get_ticks_usec()
			await process_frame
			await RenderingServer.frame_post_draw
			if frame >= 20:
				samples.append((Time.get_ticks_usec() - start) / 1000.0)
		_report("render_frame", samples)
		print("RENDER draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		root.get_texture().get_image().save_png("/tmp/airscain_combat_perf.png")
	world.free()
	await process_frame
	quit()

func _report(label: String, samples: Array[float]) -> void:
	samples.sort()
	var total := 0.0
	for value: float in samples:
		total += value
	print("COMBAT_PERF ", label, " avg_ms=", total / samples.size(), " p95_ms=", samples[int(samples.size() * 0.95)], " max_ms=", samples.back())
