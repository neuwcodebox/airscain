extends SceneTree
## Exercises the curriculum with live sensing/combat and real action signals.

const MAIN := preload("res://main/main.tscn")
var main: AirscainMain

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	AirscainApp.apply_global_font()
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.TRAINING
	main = MAIN.instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.camera_rig.set_process(false)
	await capture("start")
	if OS.get_cmdline_user_args().has("--review-ui"):
		main.hud.set_catalog_expanded(true)
		await capture("review_catalog")
		main.hud.set_catalog_expanded(false)
		var radar := place(1, Vector3(150, 0, 100))
		main._on_asset_selected(radar)
		await capture("review_ranges")
		main.hud.overlay_option.show_popup()
		await capture("review_dropdown")
		main.hud.overlay_option.get_popup().hide()
		main._on_asset_selected(null)
		main.hud.hide()
		main.day_night.apply_time(255.0, true)
		main.camera_rig.yaw_radians = deg_to_rad(main.day_night._sun.rotation_degrees.y) + PI
		main.camera_rig.pitch_radians = CameraRig.MINIMUM_ORBIT_PITCH
		main.camera_rig._update_camera()
		await capture("camera_horizon")
		main.camera_rig.rotating = true
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0.0, -2.0)
		for frame: int in 110:
			main.camera_rig._unhandled_input(motion)
			await process_frame
			if frame == 30:
				await capture("camera_sky")
		await capture("camera_sky_high")
		main.queue_free()
		await process_frame
		quit()
		return
	main.hud.training_next_button.pressed.emit()
	var guidance := main.hud.get_node("TrainingGuidance") as TrainingGuidance
	main.hud.set_catalog_expanded(true)
	await capture("radar_menu")
	assert(guidance.target_control == main.hud.defense_buttons[1])
	main.hud.defense_buttons[1].pressed.emit()
	guidance.refresh()
	Input.warp_mouse(root.get_final_transform() * main.camera_rig.camera.unproject_position(guidance.suggestion))
	await capture("radar_placement")
	assert(guidance.suggestion.is_finite())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = main.camera_rig.camera.unproject_position(guidance.suggestion)
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	assert(main.training_controller.step == TrainingController.Step.WEAPON)
	var battery := await place_recommended(0)
	main._refresh_tactical_ui()
	if not await until_step(TrainingController.Step.SELECT_TRACK):
		return
	print("TRAINING_DETECTION_SECONDS=%.1f" % main.session.survival_time)
	assert(main.session.survival_time <= 10.0)
	var tracks: Array[PlayerTrack] = main.player_knowledge.call("get_active_tracks")
	var target: PlayerTrack
	for track: PlayerTrack in tracks:
		if track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.state == PlayerTrack.State.CONFIRMED:
			target = track
			break
	if target == null:
		fail("No confirmed training contact")
		return
	var marker: Vector2 = main.tactical_screen_overlay.call("track_marker_screen_position", target)
	main._on_world_selected(Vector3.INF, marker)
	main._on_asset_selected(battery)
	await capture("fire_permission")
	main._on_asset_selected(battery)
	main.hud.hold_fire_requested.emit(false)
	if not await until_step(TrainingController.Step.SUPPORT):
		return
	await place_recommended(5)
	main._on_asset_selected(battery)
	main.hud.resupply_button.pressed.emit()
	if not await until_support_read():
		return
	main._on_asset_selected(battery)
	await capture("repair")
	main.hud.repair_button.pressed.emit()
	if not await until_support_read():
		return
	main.hud.set_city_menu_expanded(true)
	await capture("city")
	main.hud.city_restoration_button.pressed.emit()
	if main.training_controller.step != TrainingController.Step.COMPLETE:
		fail("Curriculum did not finish")
		return
	print("TRAINING_QUALITY_OK live_detection fire_permission interception resupply repair restoration budget=%d" % main.session.budget)
	main.queue_free()
	await process_frame
	quit(0)

func until_support_read() -> bool:
	for tick: int in 300:
		main._process(0.1)
		if main.training_controller.support_lesson_completed:
			var current_step := main.training_controller.step
			await capture("support_completed_%d" % current_step)
			main._process(10.0)
			assert(main.training_controller.step == current_step)
			assert(main.session.simulation_speed == 1.0)
			main.hud.training_next_button.pressed.emit()
			return true
		if tick % 15 == 0:
			await process_frame
	fail("Support lesson did not complete")
	return false

func place_recommended(index: int) -> DefenseUnit:
	main.hud.set_catalog_expanded(true)
	await capture("menu_%d" % index)
	var guidance := main.hud.get_node("TrainingGuidance") as TrainingGuidance
	assert(guidance.target_control == main.hud.defense_buttons[index])
	main.hud.defense_buttons[index].pressed.emit()
	for frame: int in 3:
		await process_frame
	assert(guidance.suggestion.is_finite())
	return place(index, guidance.suggestion)

func place(index: int, near: Vector3) -> DefenseUnit:
	var definition := main.scenario.available_defenses[index]
	var position := valid_position(definition, near)
	main.placement.select(definition)
	main.placement.candidate_position = position
	var before := main.defenses.size()
	if not main.placement.request_selected_defense_placement() or main.defenses.size() != before + 1:
		fail("Cannot place %s" % definition.id)
		return null
	return main.defenses.back()

func valid_position(definition: DefenseDefinition, near: Vector3) -> Vector3:
	for index: int in 160:
		var position := near + Vector3(cos(index * 0.8), 0, sin(index * 0.8)) * float(index)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		if main.battlefield.placement_result(position, definition.placement_profile).valid:
			return position
	return Vector3.INF

func until_step(expected: TrainingController.Step) -> bool:
	for tick: int in 2400:
		if main.training_controller.step == expected:
			return true
		main._process(0.1)
		if tick % 15 == 0:
			await process_frame
	fail("Expected step %s, got %s" % [expected, main.training_controller.step])
	return false

func capture(label: String) -> void:
	for index: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("/tmp/airscain_training_%s.png" % label)
	if error != OK:
		fail("Could not save training capture")

func fail(message: String) -> void:
	push_error(message)
	quit(1)
