extends SceneTree
## Real-window check: an unsuccessful flare release must still burn and smoke.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	AirscainApp.apply_global_font()
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	AirscainMain.requested_seed = 73129
	var main := preload("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.hud.hide()
	main.altitude_profile.hide()
	main.camera_rig.set_process(false)
	if OS.get_cmdline_user_args().has("--linger"):
		await capture_residue(main)
		return
	var definition := preload("res://enemy/strike_aircraft/strike_aircraft.tres").duplicate() as AttackUavDefinition
	definition.flare_effectiveness = 0.001
	definition.chaff_effectiveness = 0.0
	var aircraft := definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(aircraft)
	aircraft.setup(90001, definition)
	aircraft.position = Vector3(0, 220, 400)
	aircraft.configure_mission(main.objective, main.battlefield, Vector3(1800, 220, 400), 1.0, null, Vector3(3000, 300, 400))
	main.registry.add(aircraft)
	var track := PlayerTrack.new()
	track.track_id = 90001
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = aircraft.position
	var munition := MissileMunitionDefinition.new()
	munition.infrared_sensitivity = 1.0
	munition.radar_sensitivity = 0.0
	munition.interceptor_lifetime = 8.0
	var interceptor := CombatVfxWarmup.INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.position = aircraft.position + Vector3.LEFT * 220.0
	interceptor.configure(track, main.registry, munition, Vector3.RIGHT, 941)
	var released_at := -1
	for frame: int in 240:
		var delta := minf(main.get_process_delta_time(), 0.05)
		aircraft.gameplay_tick(delta)
		track.estimated_position = aircraft.position
		track.estimated_velocity = aircraft.presentation_velocity()
		if is_instance_valid(interceptor) and not interceptor.is_queued_for_deletion():
			interceptor.gameplay_tick(delta)
		var camera := main.camera_rig.camera
		camera.global_position = aircraft.global_position + Vector3(-45, 25, 160)
		camera.look_at(aircraft.global_position + Vector3.LEFT * 35)
		if aircraft.countermeasure_charges_remaining < definition.countermeasure_charges and released_at < 0:
			released_at = Time.get_ticks_msec()
			if interceptor.countermeasure_decoy_active:
				push_error("Probe expects a failed seeker defeat")
				quit(1)
				return
			interceptor.queue_free()
		await process_frame
		await RenderingServer.frame_post_draw
		if released_at >= 0 and Time.get_ticks_msec() - released_at >= 1100:
			root.get_texture().get_image().save_png("/tmp/airscain_flare_burn_and_smoke.png")
			print("FLARE_CAPTURE_OK failed defeat still releases visible flare and smoke; charges=", aircraft.countermeasure_charges_remaining)
			main.free()
			await process_frame
			quit()
			return
	push_error("No flare release observed")
	quit(1)

func capture_residue(main: AirscainMain) -> void:
	var scene := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
	var flare := scene.instantiate() as CountermeasureBurst
	main.effects_parent.add_child(flare)
	flare.global_position = Vector3(0,240,400)
	flare.setup(&"flare", Vector3(90,0,0))
	var chaff := scene.instantiate() as CountermeasureBurst
	main.effects_parent.add_child(chaff)
	chaff.global_position = Vector3(140,220,400)
	chaff.setup(&"chaff")
	main.camera_rig.camera.global_position = Vector3(70,280,640)
	main.camera_rig.camera.look_at(Vector3(70,210,400))
	for seconds: float in [2.0, 8.0, 12.0]:
		while flare.elapsed < seconds:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/airscain_countermeasure_%ds.png" % int(seconds))
		print("RESIDUE_CAPTURE time=", flare.elapsed, " smoke=", flare.smoke_trails[0].active_puff_count(), " chaff_alive=", is_instance_valid(chaff))
	main.free()
	await process_frame
	quit()
