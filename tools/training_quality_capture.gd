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
	main.hud.training_next_button.pressed.emit()
	place(1, Vector3(340, 0, 0))
	place(2, Vector3(240, 0, -90))
	var battery := place(0, Vector3(270, 0, 90))
	main.hud.start_requested.emit()
	if not await until_step(TrainingController.Step.SELECT_TRACK):
		return
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
	main._on_world_selected(Vector3.INF, marker)
	await capture("priority")
	main.hud.priority_target_button.pressed.emit()
	main._on_asset_selected(battery)
	main.hud.hold_fire_requested.emit(false)
	if not await until_step(TrainingController.Step.SUPPORT):
		return
	place(5, battery.global_position + Vector3(0, 0, 65))
	main._on_asset_selected(battery)
	main.hud.resupply_button.pressed.emit()
	if not await until_step(TrainingController.Step.REPAIR):
		return
	main._on_asset_selected(battery)
	await capture("repair")
	main.hud.repair_button.pressed.emit()
	if not await until_step(TrainingController.Step.CITY_RESTORE):
		return
	main.hud.set_city_menu_expanded(true)
	await capture("city")
	main.hud.city_restoration_button.pressed.emit()
	for index: int in 6:
		if main.training_controller.step == TrainingController.Step.ALTITUDE:
			break
		main.hud.overlay_button.pressed.emit()
	var sensor := place(3, Vector3(340, 0, -75))
	var energy := place(6, Vector3(320, 0, 110))
	main._on_asset_selected(energy)
	await capture("energy")
	main.hud.training_next_button.pressed.emit()
	main._on_asset_selected(sensor)
	main.hud.relocation_button.pressed.emit()
	var destination := valid_position(sensor.definition, sensor.global_position + Vector3(50, 0, 40))
	main.placement.candidate_position = destination
	main.placement.request_selected_defense_placement()
	if not await until_step(TrainingController.Step.OPERATIONS):
		return
	main.hud.training_next_button.pressed.emit()
	await capture("complete")
	if main.training_controller.step != TrainingController.Step.COMPLETE:
		fail("Curriculum did not finish")
		return
	print("TRAINING_QUALITY_OK live_detection priority interception resupply repair restoration energy relocation budget=%d" % main.session.budget)
	main.queue_free()
	await process_frame
	quit(0)

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
