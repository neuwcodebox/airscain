extends SceneTree
## Same missile trail, age and camera: continuous slow diffusion versus quiet reference.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	var main := preload("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.hud.hide()
	main.altitude_profile.hide()
	main.camera_rig.set_process(false)
	var missile := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(missile)
	missile.hide()
	var trail := missile.get_node("SmokeTrail") as LingeringSmokeTrail
	trail.reparent(main.effects_parent, true)
	trail.show()
	trail.set_process(false)
	missile.queue_free()
	trail.sample_world_segment(Vector3(-160, 180, 400), Vector3(160, 180, 400))
	main.camera_rig.camera.global_position = Vector3(0, 255, 680)
	main.camera_rig.camera.look_at(Vector3(0, 180, 400))
	for age: float in [2.0, 8.0, 14.0, 18.0, 20.0]:
		trail._process(age - trail._elapsed)
		for strength: float in [0.0, trail.turbulence_strength]:
			trail.smoke_material.set_shader_parameter("trail_turbulence_strength", strength)
			trail.shadow_material.set_shader_parameter("trail_turbulence_strength", strength)
			for frame: int in 3:
				await process_frame
				await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/airscain_trail_%ds_%s.png" % [int(age), "quiet" if strength == 0.0 else "turbulent"])
			print("TRAIL_CAPTURE age=", age, " strength=", strength, " puffs=", trail.active_puff_count())
	main.free()
	await process_frame
	quit()
