extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AirscainMain.requested_seed = 73129
	var main := load("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.hud.visible = false
	main.altitude_profile.visible = false
	main.camera_rig.set_process(false)
	main.camera_rig.camera.position = Vector3(360, 260, 430)
	main.camera_rig.camera.look_at(Vector3(0, 15, 0))
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
	quit()

func capture(label: String) -> void:
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_day_night_%s.png" % label)
