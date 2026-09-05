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
	for entry: Vector2 in [Vector2(0, 9), Vector2(260, 17), Vector2(450, 0), Vector2(630, 6)]:
		main.day_night.apply_time(entry.x)
		await capture("%02d" % int(entry.y))
	main.day_night.apply_time(450.0)
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
