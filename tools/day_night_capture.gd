extends SceneTree

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	if OS.get_cmdline_user_args().has("--sky-menu"):
		var app := load("res://main/app.tscn").instantiate() as AirscainApp
		root.add_child(app)
		var backdrop := app.get_node("MainMenu/Background") as TextureRect
		var demo: AirscainMain = backdrop.get("demo")
		while not app.combat_vfx_warmup_completed or not demo.combat_effect_pool.prepared:
			await process_frame
		demo.set_process(false)
		for elapsed: float in [0.0, 255.0, 450.0]:
			demo.day_night.apply_time(elapsed, true)
			await capture("sky_menu_%03d" % int(elapsed))
		app.free()
		for frame: int in 3:
			await process_frame
		quit()
		return
	AirscainMain.requested_seed = 73129
	var main := load("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.hud.visible = false
	main.altitude_profile.visible = false
	main.camera_rig.set_process(false)
	main.camera_rig.camera.position = Vector3(360, 260, 430)
	main.camera_rig.camera.look_at(Vector3(0, 15, 0))
	if OS.get_cmdline_user_args().has("--sky-benchmark"):
		await benchmark_sky(main)
		main.free()
		for frame: int in 3:
			await process_frame
		quit()
		return
	if OS.get_cmdline_user_args().has("--sky"):
		await capture_sky(main)
		main.free()
		for frame: int in 3:
			await process_frame
		quit()
		return
	if OS.get_cmdline_user_args().has("--smoke-lighting"):
		await capture_smoke_lighting(main)
		main.free()
		for frame: int in 3:
			await process_frame
		quit()
		return
	if OS.get_cmdline_user_args().has("--transition"):
		for elapsed: float in [263.0, 265.3, 265.6, 268.0, 632.0, 634.4, 634.7, 637.0]:
			main.day_night.apply_time(elapsed, true)
			await capture("transition_%05.1f" % elapsed)
		main.free()
		quit()
		return
	var trail := LingeringSmokeTrail.new()
	trail.puff_mesh = QuadMesh.new()
	trail.puff_mesh.size = Vector2(2, 2)
	trail.puff_mesh.material = preload("res://effects/missile_smoke_material.tres")
	main.effects_parent.add_child(trail)
	trail.sample_world_segment(Vector3(-180, 110, 80), Vector3(180, 180, 80))
	trail._process(1.0)
	trail.set_process(false)
	for entry: Vector2 in [Vector2(0, 9), Vector2(260, 17), Vector2(450, 0), Vector2(630, 6)]:
		main.day_night.apply_time(entry.x)
		await capture("%02d" % int(entry.y))
	main.day_night.apply_time(450.0)
	if OS.get_cmdline_user_args().has("--glow-check"):
		var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		environment.glow_enabled = false
		await capture("glow_off")
		environment.glow_enabled = true
		await capture("glow_probe")
		main.free()
		quit()
		return
	var building := main.battlefield.city_buildings[-1]
	var size := building.basis.get_scale()
	main.objective.apply_building_impact(10, building.origin + Vector3.UP * size.y * 0.5, size.y)
	await capture("blackout")
	main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	await capture("repaired")
	var explosion := load("res://effects/explosion/explosion.tscn").instantiate() as ExplosionEffect
	main.effects_parent.add_child(explosion)
	explosion.position = Vector3(0, main.battlefield.terrain_height(0, 0) + 95, 0)
	explosion.setup(Color(1.0, 0.43, 0.12), 15.0)
	explosion.set_process(false)
	explosion._process(0.06)
	await capture("blast")
	var gunfire := GunfireRuntime.new()
	main.effects_parent.add_child(gunfire)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	gunfire.enqueue(Vector3(130, 35, 150), Vector3(-90, 160, -50), Vector3.ZERO, 0.8, 1.0, preload("res://defense/close_in_gun/close_in_gun.tres"), rng)
	gunfire.gameplay_tick(0.28)
	main.objective.apply_surface_impact(10, Vector3(90, main.battlefield.terrain_height(90, 90) + 30, 90))
	for frame: int in 30:
		await process_frame
	await capture("combat")
	main.free()
	for frame: int in 3:
		await process_frame
	quit()

func capture(label: String) -> void:
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_day_night_%s.png" % label)

func capture_smoke_lighting(main: AirscainMain) -> void:
	var missile := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate()
	var trail := missile.get_node("SmokeTrail") as LingeringSmokeTrail
	missile.remove_child(trail)
	missile.free()
	main.effects_parent.add_child(trail)
	trail.sample_world_segment(Vector3(-100, 100, 80), Vector3(100, 130, 80))
	trail._process(6.0)
	trail.set_process(false)
	main.camera_rig.camera.position = Vector3(30, 180, 290)
	main.camera_rig.camera.look_at(Vector3(0, 110, 80))
	for entry: Vector2 in [Vector2(0, 9), Vector2(450, 0)]:
		main.day_night.apply_time(entry.x, true)
		await capture("smoke_%02d" % int(entry.y))
		trail.shadow_particles.visible = false
		await capture("smoke_%02d_no_proxy" % int(entry.y))
		trail.shadow_particles.visible = true

func capture_sky(main: AirscainMain) -> void:
	var camera := main.camera_rig.camera
	for time_hour: float in [5.5, 6.2, 9.0, 17.5, 18.2, 20.0, 0.0]:
		var elapsed := fposmod(time_hour - DayNightCycle.START_HOUR, 24.0) / 24.0 * DayNightCycle.CYCLE_SECONDS
		main.day_night.apply_time(elapsed, true)
		# Actual lowest gameplay orbit, facing the sunrise/sunset azimuth.
		main.camera_rig.pitch_radians = CameraRig.MINIMUM_PITCH
		main.camera_rig.yaw_radians = deg_to_rad(DayNightCycle.orbit_rotation(time_hour if time_hour > 5.0 and time_hour < 19.0 else fposmod(time_hour + 12.0, 24.0)).y) + PI
		main.camera_rig._update_camera()
		await capture("sky_horizon_%04.1f" % time_hour)
		# Inspection angle for the complete dome, not a change to player controls.
		camera.global_position = Vector3(0, 180, 0)
		var direction := main.day_night._sun.basis.z if time_hour > 5.0 and time_hour < 19.0 else main.day_night._moon.basis.z
		direction.y = maxf(direction.y, 0.15)
		camera.look_at(camera.global_position + direction * 100)
		await capture("sky_dome_%04.1f" % time_hour)

func benchmark_sky(main: AirscainMain) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var sky := main.day_night._environment.sky
	var reference := Sky.new()
	reference.radiance_size = Sky.RADIANCE_SIZE_32
	reference.sky_material = ProceduralSkyMaterial.new()
	var camera := main.camera_rig.camera
	for angle: String in ["tactical", "dome"]:
		camera.global_position = Vector3(360, 260, 430)
		camera.look_at(Vector3(0, 15, 0) if angle == "tactical" else camera.global_position + Vector3(0.0, 1.0, -1.0))
		for candidate: Sky in [reference, sky, sky, reference]:
			main.day_night._environment.sky = candidate
			var frames: Array[float] = []
			for index: int in 210:
				main.day_night.apply_time(450.0 + float(index) / 60.0, true)
				var start := Time.get_ticks_usec()
				await process_frame
				if index >= 30:
					frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
			frames.sort()
			print("SKY_BENCH %s %s median=%.3f p95=%.3f" % [angle, "living" if candidate == sky else "procedural", frames[90], frames[171]])
	main.day_night._environment.sky = sky
