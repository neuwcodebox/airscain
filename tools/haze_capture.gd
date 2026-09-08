extends SceneTree

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	AirscainMain.requested_seed = 73129
	var main := preload("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.hud.hide()
	main.altitude_profile.hide()
	main.track_display.hide()
	var definition := preload("res://enemy/strike_aircraft/strike_aircraft.tres")
	var aircraft := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(aircraft)
	aircraft.setup(5001, definition)
	aircraft.configure_mission(main.objective, main.battlefield, main.objective.global_position, 1.0)
	main._on_threat_spawned(aircraft)
	for radius: float in [5400.0, 4200.0, 3000.0, 1900.0]:
		aircraft.global_position = Vector3(radius, 180, 0)
		main.camera_rig.camera.global_position = aircraft.global_position + Vector3(45, 20, 60)
		main.camera_rig.camera.look_at(aircraft.global_position)
		for frame: int in 5:
			await process_frame
			await RenderingServer.frame_post_draw
		var path := "/tmp/airscain_haze_%d.png" % int(radius)
		root.get_texture().get_image().save_png(path)
		print("HAZE_CAPTURE ", radius, " opacity=", DistantContactHaze.opacity_at(aircraft.global_position, main.scenario.battlefield_size), " ", path)
	main.free()
	quit()
