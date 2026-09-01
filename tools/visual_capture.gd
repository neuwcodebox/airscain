extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")

var main: AirscainMain

func _init() -> void:
	call_deferred("run")

func run() -> void:
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	for index: int in 20:
		await process_frame
	_save_capture("/tmp/airscain_initial.png")
	main.placement.select(main.scenario.available_defenses[1])
	Input.warp_mouse(Vector2(330.0, 460.0))
	for index: int in 20:
		await process_frame
	if not main.placement.candidate_valid or not main.placement.preview.visible:
		push_error("Placement preview did not acquire a valid terrain point")
		quit(1)
		return
	_save_capture("/tmp/airscain_placement.png")
	main.placement.cancel()
	_place_initial_assets()
	for defense: DefenseUnit in main.defenses:
		if defense is MissileBattery:
			main.placement.pick_asset_at(defense.global_position)
			break
	main.session.start_defense()
	main.director.enabled = false
	for index: int in 8:
		var threat := main.director.spawn_one()
		var angle := TAU * float(index) / 8.0
		var target_position := Vector3(cos(angle) * 230.0, 72.0, sin(angle) * 230.0)
		threat.global_position = target_position
	_spawn_swarm_near_close_in_gun()
	for index: int in 30:
		await process_frame
	_save_capture("/tmp/airscain_layered_defense.png")
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
	print("VISUAL_CAPTURE_OK initial placement layered_defense combat coasting game_over")
	quit(0)

func _place_initial_assets() -> void:
	main.session.budget += 250
	_place_asset(main.scenario.available_defenses[0], -1.0)
	_place_asset(main.scenario.available_defenses[1], 1.0)
	_place_asset(main.scenario.available_defenses[2], 1.0)
	_place_asset(main.scenario.available_defenses[3], -1.0)
	_place_asset(main.scenario.available_defenses[4], 1.0)
	_place_asset(main.scenario.available_defenses[5], -1.0)

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
