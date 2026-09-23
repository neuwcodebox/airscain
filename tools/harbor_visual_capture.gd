extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	PlayerSettings.instance().values.briefings = false
	AirscainMain.requested_seed = 7
	AirscainMain.requested_layout_id = &"rugged_harbor"
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	var main := MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.hud.hide()
	main.altitude_profile.hide()
	var route := main.harbor_port.route
	var berth := Vector3(route.berth.x, route.sea_level, route.berth.y)
	var along := Vector3(route.along_quay.x, 0.0, route.along_quay.y)
	var seaward := Vector3(route.seaward.x, 0.0, route.seaward.y)
	main.camera_rig.camera.global_position = berth + along * 170.0 + seaward * 230.0 + Vector3.UP * 145.0
	main.camera_rig.camera.look_at(berth + Vector3.UP * 7.0)
	for time_seconds: float in [65.0, 80.0, 94.0, 125.0]:
		main.harbor_port.update_at_time(time_seconds)
		for frame: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "/tmp/airscain_harbor_%d.png" % int(time_seconds)
		var result := root.get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Harbor capture failed: %s" % error_string(result))
			quit(1)
			return
	print("HARBOR_VISUAL_CAPTURE_OK berth=%s inbound=%.1f outbound=%.1f" % [berth, route.inbound_duration, route.outbound_duration])
	quit(0)
