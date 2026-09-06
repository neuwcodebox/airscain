extends SceneTree
## Deterministic, silent visual check of the observed-target strike flow.

var capture_prefix := "airscain_battery_strike"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AirscainApp.apply_global_font()
	AirscainMain.requested_seed = 73129
	var main := load("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	main.combat_audio.stop_all()
	main.ui_audio.stop_all()
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.altitude_profile.hide()
	var requested: StringName = &"battery_strike_uav"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--threat="):
			requested = StringName(argument.trim_prefix("--threat="))
			capture_prefix = "airscain_%s" % requested
	var entry: ThreatSpawnEntry
	for candidate: ThreatSpawnEntry in main.scenario.threat_entries:
		if candidate.threat_definition.id == requested:
			entry = candidate
	assert(entry != null)
	var role := entry.threat_definition.adaptive_knowledge_role
	var definition_index := {&"weapon": 0, &"sensor": 1, &"command": 2, &"support": 5}[role] as int
	var definition: DefenseDefinition = main.scenario.available_defenses[definition_index]
	main._on_pressure_changed(definition.unlock_pressure_level)
	var target: DefenseUnit
	for x: int in range(280, 601, 30):
		var position := Vector3(x, main.battlefield.terrain_height(x, 180), 180)
		var result := main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
		if result.success:
			target = result.unit
			break
	assert(target != null)
	target.receive_damage(40.0)
	main.enemy_knowledge.record_recon(target)
	var hunter := main.director._spawn_entry(entry, 0.5, 0.0) as AttackUav
	for tick: int in 3600:
		hunter.gameplay_tick(1.0 / 30.0)
		if hunter.global_position.distance_to(target.global_position) < maxf(190.0, hunter.mission_runtime.profile.action_distance * 1.4):
			break
	main.hud.hide()
	main.camera_rig.camera.global_position = hunter.global_position + Vector3(35, 28, 42)
	main.camera_rig.camera.look_at(hunter.global_position)
	await capture("model")
	main.hud.show()
	main._on_asset_selected(target)
	main.camera_rig.camera.global_position = target.global_position + Vector3(230, 230, 290)
	main.camera_rig.camera.look_at(target.global_position + Vector3.UP * 45.0)
	Input.warp_mouse(Vector2(20, 20))
	await capture("approach")
	for tick: int in 900:
		hunter.gameplay_tick(1.0 / 30.0)
		if hunter.mission_runtime.effect_applied:
			break
	assert(hunter.mission_runtime.effect_applied)
	if hunter.mission_runtime.profile.type == ThreatMissionDefinition.Type.IMPACT:
		target._process(0.0)
		main._on_asset_selected(target)
		assert(target.integrity == maxf(0.0, 60.0 - hunter.mission_runtime.profile.damage))
		await capture("impact")
		main.free()
		await process_frame
		quit()
		return
	var munition: Node3D
	for child: Node in main.threat_parent.get_children():
		if child.get_script() == SessionSnapshot.AIR_STRIKE_MUNITION_SCRIPT:
			munition = child as Node3D
			munition.set_process(false)
	assert(munition != null)
	munition.call("_process", 0.06)
	await capture("release")
	var city_before := main.objective.current_integrity
	munition.call("_process", 1.0)
	target._process(0.0)
	main._on_asset_selected(target)
	assert(not target.active and target.integrity == maxf(0.0, 60.0 - hunter.mission_runtime.profile.damage))
	assert(main.objective.current_integrity == city_before)
	await capture("impact")
	print("STRIKE verified: observed approach, one release, asset integrity 60 -> %.0f, city unchanged" % target.integrity)
	main.free()
	await process_frame
	quit()

func capture(label: String) -> void:
	for frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "/tmp/%s_%s.png" % [capture_prefix, label]
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
