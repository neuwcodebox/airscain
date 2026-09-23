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
	Input.warp_mouse(main.camera_rig.camera.unproject_position(main.harbor_port.identity_marker.icon.global_position))
	for frame: int in 4:
		await process_frame
	if not main.tactical_screen_overlay.pointer_hint.visible or main.tactical_screen_overlay.pointer_label.text != TranslationServer.translate("화물 항구"):
		push_error("Harbor hover did not display the tactical hint")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_harbor_hint_normal.png")
	Input.warp_mouse(Vector2(12.0, 12.0))
	main.harbor_port.update_at_time(125.0)
	main.camera_rig.camera.global_position = berth - seaward * 330.0 + Vector3.UP * 310.0
	main.camera_rig.camera.look_at(berth + seaward * 500.0)
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_harbor_shipping.png")
	main.camera_rig.camera.global_position = berth + along * 170.0 + seaward * 230.0 + Vector3.UP * 145.0
	main.camera_rig.camera.look_at(berth + Vector3.UP * 7.0)
	Input.warp_mouse(main.camera_rig.camera.unproject_position(main.harbor_port.identity_marker.icon.global_position))
	var city_integrity := main.objective.current_integrity
	if not main.objective.apply_surface_impact(30, main.harbor_port.strike_target()) or main.objective.current_integrity != city_integrity:
		push_error("Harbor impact did not stay separate from city damage")
		quit(1)
		return
	var night := fposmod(22.0 - DayNightCycle.START_HOUR, 24.0) / 24.0 * DayNightCycle.CYCLE_SECONDS
	main.day_night.apply_time(night, true)
	for age: float in [42.0, 181.0]:
		main.session.survival_time = age
		main.harbor_port.update_at_time(age)
		for frame: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/airscain_harbor_repair_%d.png" % int(age))
		if age == 42.0 or age == 181.0:
			var expected := TranslationServer.translate("복구 중 · 지원 중단") if age == 42.0 else TranslationServer.translate("정상 운영")
			if not main.tactical_screen_overlay.pointer_hint.visible or main.tactical_screen_overlay.hint_rows[1].text != expected:
				push_error("Harbor tactical hint did not follow repair state")
				quit(1)
				return
			root.get_texture().get_image().save_png("/tmp/airscain_harbor_hint_%d.png" % int(age))
	print("HARBOR_VISUAL_CAPTURE_OK berth=%s inbound=%.1f outbound=%.1f" % [berth, route.inbound_duration, route.outbound_duration])
	quit(0)
