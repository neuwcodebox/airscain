extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	_apply_requested_seed()
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	for index: int in 20:
		await process_frame
	_save_capture("/tmp/airscain_initial.png")
	if OS.get_cmdline_user_args().has("--capture-city-only"):
		await _capture_city_detail()
		print("VISUAL_CAPTURE_OK western_city_detail contextual_rooftop_pads")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-marker-only"):
		await _capture_offscreen_marker_safe_area()
		print("VISUAL_CAPTURE_OK offscreen_marker_safe_area")
		quit(0)
		return
	await _verify_catalog_wheel_input()
	await _capture_camera_rotation()
	if OS.get_cmdline_user_args().has("--capture-camera-only"):
		print("VISUAL_CAPTURE_OK camera_rotation")
		quit(0)
		return
	main.placement.select(main.scenario.available_defenses[1])
	var rooftop_position: Vector3 = main.battlefield.rooftop_pads[0].position
	Input.warp_mouse(main.camera_rig.camera.unproject_position(rooftop_position))
	for index: int in 20:
		await process_frame
	if not main.placement.candidate_valid or not main.placement.preview.visible or main.placement.candidate_position.y < rooftop_position.y - 1.0:
		push_error("Placement preview did not acquire the designated rooftop")
		quit(1)
		return
	_save_capture("/tmp/airscain_placement.png")
	main.placement.cancel()
	_place_initial_assets()
	if OS.get_cmdline_user_args().has("--capture-countermeasure-only"):
		var countermeasure_center := main.objective.global_position + Vector3(0.0, 90.0, 80.0)
		main.camera_rig.camera.global_position = countermeasure_center + Vector3(0.0, 65.0, 190.0)
		main.camera_rig.camera.look_at(countermeasure_center, Vector3.UP)
		main.hud.visible = false
		main.altitude_profile.visible = false
		await _capture_countermeasure_defeat(countermeasure_center, false)
		print("VISUAL_CAPTURE_OK chaff_cloud delayed_diversion")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-light-only"):
		await _capture_hdr_light_vfx()
		print("VISUAL_CAPTURE_OK hdr_explosion laser_glow")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--capture-city-status-only"):
		await _capture_city_smoke_and_ammo_status()
		print("VISUAL_CAPTURE_OK city_damage_smoke ammo_depleted_status")
		quit(0)
		return
	await _capture_missile_battery_variants()
	if OS.get_cmdline_user_args().has("--capture-batteries-only"):
		print("VISUAL_CAPTURE_OK missile_battery_variants")
		quit(0)
		return
	await _capture_missile_smoke_trail()
	if OS.get_cmdline_user_args().has("--capture-smoke-only"):
		print("VISUAL_CAPTURE_OK catalog_wheel missile_smoke_timed_fade")
		quit(0)
		return
	var city_camera_position := main.camera_rig.global_position
	var city_camera_zoom := main.camera_rig.zoom_distance
	main.objective.apply_mission_damage(35)
	main.camera_rig.focus_on(main.objective.global_position)
	main.camera_rig.zoom_distance = 360.0
	main.camera_rig._update_camera()
	for index: int in 15:
		await process_frame
	if main.objective.damage_smoke_effects.size() < 2:
		push_error("City damage did not create persistent smoke sites")
		quit(1)
		return
	_save_capture("/tmp/airscain_city_damage.png")
	main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	main.camera_rig.global_position = city_camera_position
	main.camera_rig.zoom_distance = city_camera_zoom
	main.camera_rig._update_camera()
	for defense: DefenseUnit in main.defenses:
		if defense.definition.id == &"long_range_missile":
			defense.receive_damage(50.0)
			main.placement.pick_asset_at(defense.global_position)
			break
	main.session.start_defense()
	main.director.enabled = false
	for index: int in 8:
		var threat := main.director.spawn_one()
		var angle := TAU * float(index) / 8.0
		var target_position := Vector3(cos(angle) * 230.0, 72.0, sin(angle) * 230.0)
		threat.global_position = target_position
	for entry_index: int in range(2, 6):
		var mission_threat := main.director._spawn_entry(main.scenario.threat_entries[entry_index], TAU * float(entry_index) / 5.0, 0.0)
		mission_threat.global_position = Vector3(-320.0 + float(entry_index) * 110.0, 90.0 if entry_index < 5 else 28.0, 260.0)
	var jammer := main.director._spawn_entry(main.scenario.threat_entries[7], 0.4, 0.0)
	jammer.global_position = Vector3(60.0, 90.0, 120.0)
	for entry_index: int in range(9, 12):
		var advanced_threat := main.director._spawn_entry(main.scenario.threat_entries[entry_index], PI + float(entry_index - 9) * 0.16, 0.0)
		advanced_threat.global_position = Vector3(-520.0, 35.0 + float(entry_index - 9) * 55.0, -150.0 + float(entry_index - 9) * 150.0)
	await _capture_strike_vfx()
	_spawn_swarm_near_close_in_gun()
	var visual_target := main.director._spawn_entry(main.scenario.threat_entries[0], 0.0, 0.0)
	var visual_target_position := Vector3(-70.0, 105.0, 40.0)
	visual_target.global_position = visual_target_position
	visual_target.receive_damage(10000.0)
	for index: int in 6:
		await process_frame
	if main.effects_parent.get_node_or_null("FallingWreck") == null:
		push_error("Neutralized aircraft did not leave a falling wreck")
		quit(1)
		return
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	main.camera_rig.focus_on(visual_target_position)
	main.camera_rig.zoom_distance = 260.0
	main.camera_rig._update_camera()
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_combat_vfx.png")
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()
	for index: int in 30:
		await process_frame
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			(defense as CloseInGun).magazine.rounds = 0
			(defense as CloseInGun).magazine.reserve = 0
			defense._process(0.0)
			break
	main.altitude_profile.call("refresh_snapshot")
	if (main.altitude_profile.get("track_markers") as Array).is_empty() or (main.altitude_profile.get("projectile_markers") as Array).is_empty():
		push_error("Altitude profile did not render public tracks and friendly projectiles")
		quit(1)
		return
	_save_capture("/tmp/airscain_altitude_profile.png")
	_save_capture("/tmp/airscain_layered_defense.png")
	main.hud._on_c2_overlay_pressed()
	for index: int in 3:
		await process_frame
	if main.tactical_range_overlay.get("mode") != &"sensor":
		push_error("Sensor range overlay did not activate")
		quit(1)
		return
	_save_capture("/tmp/airscain_sensor_overlay.png")
	for index: int in 3:
		main.hud._on_c2_overlay_pressed()
	for index: int in 3:
		await process_frame
	if main.tactical_range_overlay.get("mode") != &"electronic":
		push_error("Electronic impact overlay did not activate")
		quit(1)
		return
	_save_capture("/tmp/airscain_electronic_overlay.png")
	main.hud._on_c2_overlay_pressed()
	main.hud._on_c2_overlay_pressed()
	var early_tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	if early_tracks.is_empty():
		push_error("No public track was available for tactical selection capture")
		quit(1)
		return
	main._on_world_selected(early_tracks[0].estimated_position)
	if main.selected_track == null or main.track_display.selection_lines.mesh == null:
		push_error("Selected track tactical relations were not rendered")
		quit(1)
		return
	for index: int in 3:
		await process_frame
	if main.hud.selected_track_label.text.is_empty() or not main.hud.selected_track_label.visible:
		push_error("Selected track detail panel was not populated")
		quit(1)
		return
	_save_capture("/tmp/airscain_tactical_selection.png")
	for index: int in 150:
		await process_frame
	var known_tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	if not known_tracks.is_empty():
		main._on_world_selected(known_tracks[0].estimated_position)
	_save_capture("/tmp/airscain_combat.png")
	for defense: DefenseUnit in main.defenses:
		if defense is SearchRadar:
			defense.active = false
	main.set_process(false)
	main.player_knowledge.call("gameplay_tick", 0.7)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_coasting.png")
	main.objective.apply_mission_damage(main.objective.current_integrity)
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_game_over.png")
	print("VISUAL_CAPTURE_OK initial catalog_wheel camera_rotation placement missile_battery_variants missile_smoke_trail combat_vfx strike_vfx altitude_profile layered_defense sensor_overlay electronic_overlay tactical_selection combat coasting city_damage game_over")
	quit(0)

func _verify_catalog_wheel_input() -> void:
	var defense_scroll := main.hud.get_node("Catalog/VBox/DefenseScroll") as ScrollContainer
	var target_button: Button
	for child: Node in main.hud.defense_list.get_children():
		if child is Button:
			target_button = child as Button
			break
	if target_button == null:
		push_error("Catalog did not expose a child button for wheel verification")
		quit(1)
		return
	defense_scroll.scroll_vertical = 0
	Input.warp_mouse(target_button.get_global_rect().get_center())
	for index: int in 2:
		await process_frame
	for index: int in 3:
		var scroll_down := InputEventMouseButton.new()
		scroll_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
		scroll_down.pressed = true
		scroll_down.position = target_button.get_global_rect().get_center()
		scroll_down.global_position = scroll_down.position
		Input.parse_input_event(scroll_down)
		await process_frame
	if defense_scroll.scroll_vertical <= 0:
		push_error("Catalog wheel did not scroll while the pointer was over a child button")
		quit(1)
		return
	defense_scroll.scroll_vertical = int(defense_scroll.get_v_scroll_bar().max_value)
	var initial_zoom := main.camera_rig.zoom_distance
	var boundary_scroll := InputEventMouseButton.new()
	boundary_scroll.button_index = MOUSE_BUTTON_WHEEL_DOWN
	boundary_scroll.pressed = true
	boundary_scroll.position = defense_scroll.get_global_rect().get_center()
	boundary_scroll.global_position = boundary_scroll.position
	Input.parse_input_event(boundary_scroll)
	await process_frame
	if not is_equal_approx(main.camera_rig.zoom_distance, initial_zoom):
		push_error("Catalog boundary wheel propagated to the battlefield camera")
		quit(1)
		return
	defense_scroll.scroll_vertical = 0

func _capture_camera_rotation() -> void:
	var initial_yaw := main.camera_rig.yaw_radians
	var initial_camera_position := main.camera_rig.camera.position
	main.camera_rig.yaw_radians += deg_to_rad(55.0)
	main.camera_rig._update_camera()
	for index: int in 5:
		await process_frame
	if main.camera_rig.camera.position.is_equal_approx(initial_camera_position):
		push_error("Camera rotation did not orbit the battlefield view")
		quit(1)
		return
	_save_capture("/tmp/airscain_camera_rotated.png")
	main.camera_rig.yaw_radians = initial_yaw
	main.camera_rig._update_camera()

func _apply_requested_seed() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			AirscainMain.requested_seed = int(argument.trim_prefix("--seed="))
		elif argument == "--mode=training":
			AirscainMain.requested_mode = AirscainMain.GameMode.TRAINING
		elif argument == "--mode=sandbox":
			AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX

func _place_initial_assets() -> void:
	main.session.budget = 5000
	main._on_pressure_changed(5)
	_place_asset(main.scenario.available_defenses[0], -1.0)
	_place_asset(main.scenario.available_defenses[1], 1.0)
	_place_asset(main.scenario.available_defenses[2], 1.0)
	_place_asset(main.scenario.available_defenses[3], -1.0)
	_place_asset(main.scenario.available_defenses[4], 1.0)
	_place_asset(main.scenario.available_defenses[5], -1.0)
	_place_asset(main.scenario.available_defenses[6], 1.0)
	_place_asset(main.scenario.available_defenses[7], -1.0)
	_place_asset(main.scenario.available_defenses[8], 1.0)
	_place_asset(main.scenario.available_defenses[9], -1.0)
	_place_asset(main.scenario.available_defenses[10], 1.0)
	var rooftop_position: Vector3 = main.battlefield.rooftop_pads[0].position
	main.session.request_placement(main.scenario.available_defenses[1], rooftop_position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)

func _spawn_swarm_near_close_in_gun() -> void:
	var gun: CloseInGun
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			gun = defense as CloseInGun
			break
	if gun == null:
		return
	var definition: ThreatDefinition = main.scenario.threat_entries[1].threat_definition
	for index: int in 4:
		var threat := definition.scene.instantiate() as ThreatUnit
		main.threat_parent.add_child(threat)
		threat.global_position = gun.global_position + Vector3(125.0 + float(index) * 7.0, 48.0, (float(index) - 1.5) * 9.0)
		threat.setup(1000 + index, definition)
		threat.configure_mission(main.objective, main.battlefield, main.objective.global_position, 1.0)
		main.registry.add(threat)
		main._on_threat_spawned(threat)

func _capture_hdr_light_vfx() -> void:
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	if not environment.glow_enabled or environment.glow_strength < 0.75:
		push_error("HDR glow environment was not enabled strongly enough")
		quit(1)
		return
	var center := main.objective.global_position + Vector3(0.0, 82.0, 260.0)
	var laser_from := center + Vector3(-92.0, -18.0, 0.0)
	var laser_to := center + Vector3(36.0, 18.0, 0.0)
	var pulse := preload("res://effects/laser_pulse/laser_pulse.tscn").instantiate() as LaserPulse
	main.projectile_parent.add_child(pulse)
	pulse.setup(laser_from, laser_to)
	var explosion := preload("res://effects/explosion/explosion.tscn").instantiate() as ExplosionEffect
	main.effects_parent.add_child(explosion)
	explosion.global_position = center + Vector3(92.0, 8.0, -12.0)
	explosion.setup(Color(1.0, 0.3, 0.04), 12.0)
	main.camera_rig.camera.global_position = center + Vector3(15.0, 72.0, 190.0)
	main.camera_rig.camera.look_at(center, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	await process_frame
	if not is_instance_valid(pulse) or not (pulse.get_node("Beam") as MeshInstance3D).mesh is CylinderMesh:
		push_error("Laser pulse did not render a volumetric core")
		quit(1)
		return
	_save_capture("/tmp/airscain_hdr_light_vfx.png")

func _capture_city_detail() -> void:
	main.camera_rig.focus_on(main.objective.global_position)
	main.camera_rig.yaw_radians = deg_to_rad(32.0)
	main.camera_rig.zoom_distance = 285.0
	main.camera_rig._update_camera()
	main.hud.visible = false
	main.altitude_profile.visible = false
	for pad: MeshInstance3D in main.battlefield.rooftop_pad_visuals:
		if pad.visible:
			push_error("Rooftop placement pad was visible outside placement mode")
			quit(1)
			return
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_western_city_detail.png")
	var rooftop_definition := main.scenario.available_defenses[1]
	main.placement.select(rooftop_definition)
	var visible_pad_count := 0
	for pad: MeshInstance3D in main.battlefield.rooftop_pad_visuals:
		if pad.visible:
			visible_pad_count += 1
	if visible_pad_count == 0:
		push_error("Rooftop placement pads did not appear for a compatible asset")
		quit(1)
		return
	for index: int in 3:
		await process_frame
	_save_capture("/tmp/airscain_western_city_rooftop_placement.png")
	main.placement.cancel()

func _capture_offscreen_marker_safe_area() -> void:
	var viewport_size := root.get_visible_rect().size
	var track := PlayerTrack.new()
	track.track_id = 9991
	track.state = PlayerTrack.State.CONFIRMED
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 1.0
	track.estimated_position = main.camera_rig.camera.project_position(Vector2(viewport_size.x + 500.0, viewport_size.y * 0.5), 500.0)
	main.player_knowledge.tracks.append(track)
	for index: int in 3:
		await process_frame
	var projected := main.camera_rig.camera.unproject_position(track.estimated_position)
	var marker := TacticalScreenOverlay.tactical_marker_position(projected, viewport_size, false)
	if marker.x > viewport_size.x - TacticalScreenOverlay.RIGHT_UI_INSET + 0.01:
		push_error("Offscreen marker overlapped the right-side UI safe area")
		quit(1)
		return
	_save_capture("/tmp/airscain_offscreen_marker_safe_area.png")

func _capture_city_smoke_and_ammo_status() -> void:
	var target := main.objective.global_position
	var smoke_start_msec := Time.get_ticks_msec()
	main.objective.apply_mission_damage(55)
	var smoke_spawn_msec := Time.get_ticks_msec() - smoke_start_msec
	if smoke_spawn_msec > 100:
		push_error("City smoke spawn blocked the main thread for %dms" % smoke_spawn_msec)
		quit(1)
		return
	main.camera_rig.camera.global_position = target + Vector3(165.0, 105.0, 185.0)
	main.camera_rig.camera.look_at(target + Vector3.UP * 32.0, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	await _wait_simulation_seconds(0.8)
	if main.objective.damage_smoke_effects.size() < 3:
		push_error("City damage did not create dense multi-site smoke")
		quit(1)
		return
	_save_capture("/tmp/airscain_city_damage_smoke.png")
	await _wait_simulation_seconds(2.4)
	var lower_smoke := main.objective.damage_smoke_effects[0].get_node("Smoke") as GPUParticles3D
	var upper_smoke := main.objective.damage_smoke_effects[0].get_node("SmokeUpper") as GPUParticles3D
	if not upper_smoke.emitting or upper_smoke.global_position.y - lower_smoke.global_position.y < 16.0:
		push_error("City smoke did not maintain a rising upper plume")
		quit(1)
		return
	_save_capture("/tmp/airscain_city_damage_smoke_rising.png")
	await _wait_simulation_seconds(2.8)
	_save_capture("/tmp/airscain_city_damage_smoke_plume.png")
	main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	var gun: CloseInGun
	for defense: DefenseUnit in main.defenses:
		if defense is CloseInGun:
			gun = defense as CloseInGun
			break
	if gun == null:
		push_error("Close-in gun was unavailable for ammunition status capture")
		quit(1)
		return
	gun.magazine.rounds = 0
	gun.magazine.reserve = 0
	gun._process(0.0)
	var label := gun.status_marker.get_node("Label") as Label3D
	if label.text != "탄약 고갈" or label.pixel_size > 0.0011:
		push_error("Depleted ammunition status was not concise and screen-sized")
		quit(1)
		return
	main.camera_rig.camera.global_position = gun.global_position + Vector3(42.0, 28.0, 52.0)
	main.camera_rig.camera.look_at(gun.global_position + Vector3.UP * 11.0, Vector3.UP)
	await _wait_seconds(0.2)
	_save_capture("/tmp/airscain_ammo_depleted_status.png")

func _capture_missile_battery_variants() -> void:
	var definitions: Array[MissileBatteryDefinition] = [
		main.scenario.available_defenses[8] as MissileBatteryDefinition,
		main.scenario.available_defenses[0] as MissileBatteryDefinition,
		main.scenario.available_defenses[7] as MissileBatteryDefinition,
	]
	var expected_nodes: Array[String] = ["QuickReactionCluster", "SixCellRack", "FourCanisterBank"]
	var showcase: Array[MissileBattery] = []
	var center := main.objective.global_position + Vector3(0.0, 0.0, 360.0)
	for index: int in definitions.size():
		var battery := definitions[index].scene.instantiate() as MissileBattery
		main.effects_parent.add_child(battery)
		battery.setup(-100 - index, definitions[index])
		var position := center + Vector3((float(index) - 1.0) * 30.0, 0.0, 0.0)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		battery.global_position = position
		battery.rotation.y = -0.45
		if battery.get_node_or_null("Turret/Elevation/Launcher/%s" % expected_nodes[index]) == null:
			push_error("Missile battery variant did not expose its distinct launcher silhouette")
			quit(1)
			return
		showcase.append(battery)
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	main.camera_rig.camera.global_position = center + Vector3(58.0, 34.0, 72.0)
	main.camera_rig.camera.look_at(center + Vector3.UP * 7.0, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_missile_battery_variants.png")
	for battery: MissileBattery in showcase:
		battery.queue_free()
	main.hud.visible = true
	main.altitude_profile.visible = true
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()

func _capture_strike_vfx() -> void:
	var strike := main.director._spawn_entry(main.scenario.threat_entries[11], 0.0, 0.0) as AttackUav
	var target := main.objective.global_position
	strike.global_position = target + Vector3(0.0, 105.0, 20.0)
	strike.configure_mission(main.objective, main.battlefield, target, 1.0, null, strike.global_position + Vector3(500.0, 0.0, 0.0))
	strike.gameplay_tick(0.1)
	var munition := main.threat_parent.get_node_or_null("StrikeMunition") as Node3D
	if munition == null:
		push_error("Strike aircraft did not release its visible munition")
		quit(1)
		return
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	main.camera_rig.camera.global_position = target + Vector3(130.0, 125.0, 165.0)
	main.camera_rig.camera.look_at(target + Vector3.UP * 58.0, Vector3.UP)
	main.hud.visible = false
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_strike_vfx.png")
	main.hud.visible = true
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()

func _capture_missile_smoke_trail() -> void:
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	var start := main.objective.global_position + Vector3(-120.0, 95.0, -35.0)
	var target := PlayerTrack.new()
	target.track_id = 9901
	target.state = PlayerTrack.State.CONFIRMED
	target.estimated_position = main.objective.global_position + Vector3(150.0, 125.0, -35.0)
	interceptor.global_position = start
	var battery_definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(target, ThreatRegistry.new(), battery_definition.munitions[0], start.direction_to(target.estimated_position), 9901)
	for index: int in 18:
		interceptor.gameplay_tick(0.04)
		await process_frame
	var previous_camera_position := main.camera_rig.global_position
	var previous_zoom := main.camera_rig.zoom_distance
	var midpoint := start.lerp(interceptor.global_position, 0.5)
	main.camera_rig.camera.global_position = midpoint + Vector3(0.0, 75.0, 190.0)
	main.camera_rig.camera.look_at(midpoint, Vector3.UP)
	main.hud.visible = false
	main.altitude_profile.visible = false
	await _wait_seconds(0.35)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	var smoke_bounds := smoke.capture_aabb()
	_save_capture("/tmp/airscain_missile_smoke_trail.png")
	if smoke_bounds.size.length() < 25.0:
		push_error("Missile smoke trail did not produce a visible particle footprint")
		quit(1)
		return
	smoke.call("release_to", main.effects_parent)
	interceptor.queue_free()
	await _wait_seconds(2.0)
	var aged_smoke_bounds := smoke.capture_aabb()
	_save_capture("/tmp/airscain_missile_smoke_aged.png")
	if maxf(aged_smoke_bounds.size.y, aged_smoke_bounds.size.z) < 4.0:
		push_error("Missile smoke trail did not develop a visible turbulent cross-section")
		quit(1)
		return
	var aged_opacity := smoke.current_opacity_ratio
	await _wait_seconds(2.0)
	_save_capture("/tmp/airscain_missile_smoke_fading.png")
	var fading_opacity := smoke.current_opacity_ratio
	await _wait_seconds(2.0)
	_save_capture("/tmp/airscain_missile_smoke_near_end.png")
	var near_end_opacity := smoke.current_opacity_ratio
	if not (aged_opacity > fading_opacity and fading_opacity > near_end_opacity and near_end_opacity > 0.0):
		push_error("Missile smoke trail opacity did not decrease continuously")
		quit(1)
		return
	await _wait_seconds(2.05)
	_save_capture("/tmp/airscain_missile_smoke_transparent_tail.png")
	if not is_instance_valid(smoke) or smoke.current_opacity_ratio > 0.001 or smoke.release_remaining <= 0.0:
		push_error("Missile smoke trail was not fully transparent before cleanup")
		quit(1)
		return
	await _wait_seconds(smoke.transparent_cleanup_delay + 0.1)
	if is_instance_valid(smoke):
		push_error("Fully transparent missile smoke trail was not cleaned up")
		quit(1)
		return
	var self_destruct := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(self_destruct)
	var lost_track := PlayerTrack.new()
	lost_track.track_id = 9902
	lost_track.state = PlayerTrack.State.LOST
	lost_track.estimated_position = midpoint
	self_destruct.global_position = midpoint + Vector3(0.0, 15.0, 0.0)
	self_destruct.configure(lost_track, ThreatRegistry.new(), battery_definition.munitions[0], Vector3.FORWARD, 9902)
	self_destruct.gameplay_tick(0.05)
	for index: int in 3:
		await process_frame
	var detonation := main.projectile_parent.get_node_or_null("Explosion") as ExplosionEffect
	if detonation == null or detonation.effect_radius < 7.0:
		push_error("Interceptor self-destruct did not leave a visible detonation")
		quit(1)
		return
	_save_capture("/tmp/airscain_interceptor_self_destruct.png")
	await _capture_countermeasure_defeat(midpoint)
	main.hud.visible = true
	main.altitude_profile.visible = true
	main.camera_rig.global_position = previous_camera_position
	main.camera_rig.zoom_distance = previous_zoom
	main.camera_rig._update_camera()

func _capture_countermeasure_defeat(center: Vector3, capture_resolved_after: bool = true) -> void:
	for effect: Node in main.projectile_parent.get_children():
		if effect.name == "Explosion" or effect.name == "InterceptorMiss":
			effect.queue_free()
	await process_frame
	var strike_definition := main.scenario.threat_entries[11].threat_definition as AttackUavDefinition
	var strike := strike_definition.scene.instantiate() as AttackUav
	main.threat_parent.add_child(strike)
	strike.setup(9950, strike_definition)
	strike.global_position = center + Vector3(48.0, 12.0, 0.0)
	main.registry.add(strike)
	var track := PlayerTrack.new()
	track.track_id = 9950
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = strike.global_position
	track.estimated_velocity = Vector3(96.0, 0.0, 0.0)
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = strike.global_position + Vector3(-100.0, 0.0, 0.0)
	var long_range := main.scenario.available_defenses[7] as MissileBatteryDefinition
	interceptor.configure(track, main.registry, long_range.munitions[0], Vector3.RIGHT, 9950)
	var test_rng := RandomNumberGenerator.new()
	var successful_seed := 1
	while successful_seed < 1000:
		test_rng.seed = successful_seed
		if test_rng.randf() < strike_definition.chaff_effectiveness * long_range.munitions[0].radar_sensitivity:
			break
		successful_seed += 1
	interceptor.rng.seed = successful_seed
	interceptor.gameplay_tick(0.01)
	for index: int in 10:
		await process_frame
	var burst := main.projectile_parent.get_node_or_null("CountermeasureBurst") as Node3D
	if burst == null or burst.get_node_or_null("Reason") != null or not (burst.get_node("Chaff") as GPUParticles3D).emitting or not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
		push_error("Chaff did not create a label-free cloud and delayed interceptor diversion")
		quit(1)
		return
	_save_capture("/tmp/airscain_chaff_cloud.png")
	for tick: int in 40:
		if not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
			break
		interceptor.gameplay_tick(0.05)
		await process_frame
	var miss := main.projectile_parent.get_node_or_null("InterceptorMiss") as InterceptorMissEffect
	if is_instance_valid(interceptor) or miss == null or (miss.get_node("Reason") as Label3D).text != "유도 이탈":
		push_error("Chaff-diverted interceptor did not miss after flying toward the decoy cloud")
		quit(1)
		return
	_save_capture("/tmp/airscain_countermeasure_defeat.png")
	main.registry.remove(strike)
	strike.queue_free()
	if capture_resolved_after:
		await _capture_resolved_target_interceptor(center)

func _capture_resolved_target_interceptor(center: Vector3) -> void:
	for effect: Node in main.projectile_parent.get_children():
		if effect.name == "Explosion" or effect.name == "InterceptorMiss" or effect.name == "CountermeasureBurst":
			effect.queue_free()
	await process_frame
	var threat_definition := main.scenario.threat_entries[0].threat_definition
	var threat := threat_definition.scene.instantiate() as ThreatUnit
	main.threat_parent.add_child(threat)
	threat.setup(9960, threat_definition)
	threat.global_position = center + Vector3(110.0, 18.0, 0.0)
	main.registry.add(threat)
	main._on_threat_spawned(threat)
	var track := PlayerTrack.new()
	track.track_id = 9960
	track.state = PlayerTrack.State.CONFIRMED
	track.classification = threat_definition.signature_class
	track.estimated_position = threat.global_position
	track.position_uncertainty = 8.0
	var interceptor := preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate() as HomingInterceptor
	main.projectile_parent.add_child(interceptor)
	interceptor.global_position = threat.global_position + Vector3(-260.0, 0.0, 0.0)
	var battery_definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	interceptor.configure(track, main.registry, battery_definition.munitions[0], Vector3.RIGHT, 9960)
	for index: int in 5:
		interceptor.gameplay_tick(0.05)
		await process_frame
	var position_at_resolution := interceptor.global_position
	threat.receive_damage(10000.0)
	interceptor.gameplay_tick(0.05)
	if not interceptor.is_queued_for_deletion() or not interceptor.global_position.is_equal_approx(position_at_resolution):
		push_error("Interceptor advanced after its correlated target was destroyed")
		quit(1)
		return
	await _wait_simulation_seconds(0.12)
	var miss := main.projectile_parent.get_node_or_null("InterceptorMiss") as InterceptorMissEffect
	if miss == null or (miss.get_node("Reason") as Label3D).text != "표적 격추":
		push_error("Resolved target interceptor did not explain its immediate self-destruct")
		quit(1)
		return
	_save_capture("/tmp/airscain_target_resolved_interceptor.png")

func _place_asset(definition: DefenseDefinition, direction: float) -> void:
	for offset: int in range(0, 180, 10):
		var position := Vector3(direction * (210.0 + float(offset)), 0.0, 0.0)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		if main.battlefield.placement_result(position, definition.placement_profile).valid:
			main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			return

func _save_capture(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save visual capture: %s" % error_string(error))

func _wait_seconds(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _wait_simulation_seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await process_frame
		elapsed += minf(main.get_process_delta_time(), 0.1)
