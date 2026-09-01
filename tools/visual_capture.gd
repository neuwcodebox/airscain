extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func _init() -> void:
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
	for entry_index: int in range(9, 12):
		var advanced_threat := main.director._spawn_entry(main.scenario.threat_entries[entry_index], PI + float(entry_index - 9) * 0.16, 0.0)
		advanced_threat.global_position = Vector3(-520.0, 35.0 + float(entry_index - 9) * 55.0, -150.0 + float(entry_index - 9) * 150.0)
	_spawn_swarm_near_close_in_gun()
	for index: int in 30:
		await process_frame
	_save_capture("/tmp/airscain_layered_defense.png")
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
	if not main.hud.selected_track_label.text.contains("T-"):
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
	main.objective.apply_mission_damage(100)
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_game_over.png")
	print("VISUAL_CAPTURE_OK initial placement layered_defense tactical_selection combat coasting game_over")
	quit(0)

func _apply_requested_seed() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			AirscainMain.requested_seed = int(argument.trim_prefix("--seed="))

func _place_initial_assets() -> void:
	main.session.budget += 900
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
