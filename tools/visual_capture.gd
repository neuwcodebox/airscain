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
	print("VISUAL_CAPTURE_OK initial placement combat_vfx layered_defense sensor_overlay electronic_overlay tactical_selection combat coasting city_damage game_over")
	quit(0)

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
