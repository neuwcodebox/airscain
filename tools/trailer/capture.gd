extends SceneTree
## Two continuous gameplay takes. All attacking aircraft exist before frame zero.
const MAIN := preload("res://main/main.tscn")
var main: AirscainMain
var shot := "intro"
var language := "ko"
var seconds := 16.0
var output := "res://build/trailer_v2/review"
var probe := false
var camera_preview := false
var frame := -1
var first_movie_frame := 0
var units: Dictionary[StringName, Array] = {}
var events: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var births: Array[Dictionary] = []
var initial_assets: Array[Dictionary] = []
var peak_threats := 0
var recording := false
var camera_cut := -1

func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--lang="): language = arg.trim_prefix("--lang=")
		elif arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg == "--probe": probe = true
		elif arg == "--camera-preview": camera_preview = true
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var prefs := PlayerSettings.instance()
	prefs.values.briefings = false
	prefs.values.language = language
	prefs.values.antialiasing = 2
	prefs.apply_language()
	prefs.apply_rendering()
	AirscainApp.apply_global_font()
	Engine.max_fps = 0
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_layout_id = &"island_city"
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	main = MAIN.instantiate() as AirscainMain
	main.auto_start_sustained = false
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.camera_rig.set_process(false)
	main.placement.set_process(false)
	main.director.enabled = false
	# Only verified CC0 game samples are captured; unknown-source approach loops are excluded.
	main.combat_audio.uav_loops.free()
	main.combat_audio.uav_loops = null
	main.combat_audio.approaches.free()
	main.combat_audio.approaches = null
	main.combat_audio.cruise_approaches.free()
	main.combat_audio.cruise_approaches = null
	main.day_night.apply_time(0.0, true)
	main.session.start_defense()
	if shot == "raid":
		main.session.survival_time = 1440.0
		main.session.next_support_at = 1530.0
		main.session.update_pressure(14)
		main.hud.set_pressure(14)
		main.director.pressure_level = 14
		for payment: int in 65:
			main.session.grant_regular_support(main.scenario.support_amount)
	_build_fixture()
	initial_assets = _asset_state()
	main.director.enabled = false
	main.camera_rig.input_blocked = true
	_hud(shot == "intro")
	if shot == "intro":
		_pose(Vector3(310, 560, -840), Vector3(260, 50, 0), 65)
	else:
		_raid_camera(0)
	_preflight_attack()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for settle: int in 30:
		await process_frame
		if not probe: await RenderingServer.frame_post_draw
	first_movie_frame = Engine.get_frames_drawn()
	if camera_preview:
		for moment: float in [22.0, 25.0, 29.5, 30.75, 31.75, 32.5, 33.25, 34.0]:
			_raid_camera(moment)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/camera_%02d.png" % [output, camera_cut])
		units.clear()
		main.queue_free()
		await process_frame
		main = null
		await process_frame
		quit(0)
		return
	recording = true
	print("TRAILER_START shot=%s frame=%d aircraft=%d" % [shot, first_movie_frame, births.size()])
	for index: int in int(seconds * 60.0):
		frame = index
		var t := float(frame) / 60.0
		if shot == "intro": _intro(t)
		else: _raid_camera(t)
		await process_frame
		if not probe: await RenderingServer.frame_post_draw
		peak_threats = maxi(peak_threats, main.registry.hostile_count())
		if index % 60 == 0:
			var positions: Array[Dictionary] = []
			for threat: ThreatUnit in main.registry.get_active():
				positions.append({"id": threat.runtime_id, "type": threat.definition.id, "p": [threat.position.x, threat.position.y, threat.position.z]})
			samples.append({"frame": frame, "city": main.objective.current_integrity, "kills": main.session.neutralized_count, "active": main.registry.hostile_count(), "camera": camera_cut, "threats": positions})
		if not probe and index % 120 == 60:
			root.get_texture().get_image().save_png("%s/%s_%s_%04d.png" % [output, shot, language, index])
	var report := {"shot": shot, "language": language, "first_movie_frame": first_movie_frame,
		"frames": frame + 1, "peak_threats": peak_threats, "kills": main.session.neutralized_count,
		"city_integrity": main.objective.current_integrity, "events": events, "births": births,
		"initial_assets": initial_assets, "assets": _asset_state(), "samples": samples,
		"continuous_take": true, "scripted_spawns_during_capture": 0,
		"fixture": "finite-budget deployment; unchanged combat; all aircraft pre-spawned"}
	var suffix := "_probe" if probe else ""
	var file := FileAccess.open("%s/%s_%s%s.json" % [output, shot, language, suffix], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TRAILER_DONE shot=%s threats=%d kills=%d integrity=%d" % [shot, peak_threats, main.session.neutralized_count, main.objective.current_integrity])
	units.clear()
	main.queue_free()
	await process_frame
	main = null
	await process_frame
	quit(0)

func _asset_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: DefenseUnit in main.defenses:
		if is_instance_valid(unit): result.append({"id": unit.runtime_id, "type": unit.definition.id, "p": [unit.position.x, unit.position.y, unit.position.z]})
	return result

func _build_fixture() -> void:
	_buy(&"command_post", Vector3(230, 0, 0))
	if shot == "intro":
		_buy(&"missile_battery", Vector3(350, 0, -60))
		_buy(&"close_in_gun", Vector3(270, 0, -140))
		return
	for sector: int in 3:
		var z := float(sector - 1) * 240.0
		_buy(&"command_post", Vector3(220, 0, z))
		_buy(&"search_radar", Vector3(340, 0, z + 40))
		_buy(&"tracking_radar", Vector3(290, 0, z + 90))
		_buy(&"support_facility", Vector3(330, 0, z - 20))
		_buy(&"support_facility", Vector3(270, 0, z - 60))
		var ids: Array[StringName] = [&"missile_battery", &"long_range_missile", &"short_range_missile", &"close_in_gun", &"high_energy_laser", &"high_power_microwave", &"interceptor_drone_defense"]
		for k: int in ids.size():
			_buy(ids[k], Vector3(410 + (k % 2) * 55, 0, z - 70 + k * 23))

func _preflight_attack() -> void:
	if shot == "intro":
		for k: int in 3: _spawn(&"attack_uav", Vector3(1020 + k * 40, 0, -80 + k * 35))
		return
	# Depth-separated waves naturally arrive at different times. No new aircraft are
	# instantiated during the visible raid, including cuts and the final title.
	for row: int in 6:
		for column: int in 14:
			var id: StringName = &"attack_uav" if column % 4 == 0 else &"swarm_uav"
			_spawn(id, Vector3(1350 + row * 220 + (column % 3) * 24, 0, -390 + column * 60))
	for k: int in 8:
		_spawn(&"strike_aircraft", Vector3(2650 + (k / 4) * 360, 0, -330 + (k % 4) * 220))
	for k: int in 8:
		_spawn(&"cruise_missile", Vector3(1920 + k * 110, 0, -320 + (k % 4) * 205))

func _intro(_t: float) -> void:
	if frame == 45: main.hud.set_catalog_expanded(true)
	if frame == 180:
		main.placement.select(_definition(&"search_radar"))
		main.hud.set_catalog_expanded(false)
	if frame >= 180 and frame < 330:
		var p := Vector3(330, main.battlefield.terrain_height(330, 90), 90)
		main.placement.candidate_position = p
		main.placement.preview.global_position = p
		main.placement.preview.visible = true
		var valid := bool(main.battlefield.placement_result(p, _definition(&"search_radar").placement_profile).valid)
		main.placement.preview_material.albedo_color = Color(0.18, 0.95, 0.42, 0.48) if valid else Color(1.0, 0.18, 0.12, 0.52)
		main.placement.placement_preview_changed.emit(_definition(&"search_radar"), p, true)
	if frame == 330:
		if not main.placement.request_selected_defense_placement(): push_error("TRAILER placement interaction failed")
		main.placement.cancel()
		events.append({"frame": frame, "event": "radar_placed", "assets": _asset_state()})
	if frame == 420: main.placement.asset_selected.emit(_first(&"command_post"))
	if frame == 600: main.placement.world_selected.emit(Vector3.INF, Vector2.INF)

func _hud(enabled: bool) -> void:
	main.hud.visible = enabled
	main.altitude_profile.visible = false
	main.tactical_screen_overlay.visible = enabled
	main.track_display.visible = enabled
	for unit: DefenseUnit in main.defenses:
		unit.identity_marker.visible = enabled
		unit.status_marker.visible = enabled

func _pose(position: Vector3, target: Vector3, fov: float) -> void:
	main.camera_rig.camera.global_position = position
	main.camera_rig.camera.fov = fov
	main.camera_rig.camera.look_at(target)

func _ground_pose(x: float, z: float, height: float, target: Vector3, fov: float = 70) -> void:
	_pose(Vector3(x, main.battlefield.terrain_height(x, z) + height, z), target, fov)

func _raid_camera(t: float) -> void:
	var cuts: Array[float] = [0, 2, 6, 10, 13, 16, 19, 22, 25, 28, 29.5, 30.75, 31.75, 32.5, 33.25, 34]
	var selected := 0
	for k: int in cuts.size():
		if t >= cuts[k]: selected = k
	if selected == camera_cut: return
	camera_cut = selected
	match selected:
		0: _pose(Vector3(200, 180, -620), Vector3(850, 120, 0), 60)
		1: _pose(Vector3(780, 145, -500), Vector3(1630, 140, 0), 48)
		2: _pose(Vector3(650, 115, -360), Vector3(1300, 100, 100), 55)
		3: _pose(Vector3(170, 135, -470), Vector3(650, 100, 0), 65)
		4: _pose(Vector3(270, 70, -340), Vector3(650, 85, -40), 65)
		5: _pose(Vector3(410, 90, -400), Vector3(800, 80, 0), 65)
		6: _ground_pose(300, -330, 35, Vector3(580, 70, -80))
		7: _ground_pose(435, -30, 6, Vector3(620, 70, 50), 68)
		8: _ground_pose(405, -105, 8, Vector3(640, 70, 60), 68)
		9: _pose(Vector3(450, 100, -500), Vector3(780, 90, 40), 60)
		10: _ground_pose(400, 140, 25, Vector3(650, 75, 210), 70)
		11: _ground_pose(350, 50, 8, Vector3(650, 65, 140), 70)
		12: _ground_pose(415, 145, 8, Vector3(700, 90, 220), 72)
		13: _ground_pose(180, -140, 30, Vector3(450, 55, 30), 65)
		14: _ground_pose(380, 0, 8, Vector3(630, 70, 100), 72)
		15: _pose(Vector3(110, 65, -320), Vector3(560, 100, 0), 65)
	events.append({"frame": frame, "event": "camera", "cut": selected, "p": [main.camera_rig.camera.position.x, main.camera_rig.camera.position.y, main.camera_rig.camera.position.z]})

func _definition(id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id == id: return definition
	return null

func _buy(id: StringName, preferred: Vector3) -> DefenseUnit:
	var definition := _definition(id)
	if definition == null: return null
	var failure := ""
	for ring: int in 20:
		for step: int in (1 if ring == 0 else 16):
			var angle := TAU * float(step) / 16.0
			var p := preferred + Vector3(cos(angle), 0, sin(angle)) * float(ring) * 12.0
			p.y = main.battlefield.terrain_height(p.x, p.z)
			var result := main.session.request_placement(definition, p, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if not bool(result.success):
				failure = str(result.reason)
				continue
			var unit := result.unit as DefenseUnit
			if not units.has(id): units[id] = []
			units[id].append(unit)
			unit.weapon_fired.connect(_fired)
			return unit
	push_error("TRAILER: placement failed %s reason=%s budget=%d pressure=%d" % [id, failure, main.session.budget, main.session.current_pressure])
	return null

func _first(id: StringName) -> DefenseUnit:
	return units[id][0] as DefenseUnit if units.has(id) and not units[id].is_empty() else null


func _spawn(id: StringName, position: Vector3) -> void:
	if recording:
		push_error("TRAILER: aircraft spawn attempted during capture")
		return
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id != id: continue
		var threat := main.director.spawn_entry_at(entry, position)
		if threat != null:
			threat.resolved.connect(_resolved)
			births.append({"frame": -1, "id": threat.runtime_id, "type": id, "p": [threat.position.x, threat.position.y, threat.position.z]})
		return
	push_error("TRAILER missing threat " + id)

func _fired(unit: DefenseUnit, _low: bool) -> void:
	events.append({"frame": frame, "event": "fire", "asset": unit.definition.id, "id": unit.runtime_id})

func _resolved(threat: ThreatUnit, neutralized: bool, _reward: int) -> void:
	events.append({"frame": frame, "event": "kill" if neutralized else "impact_or_exit", "threat": threat.definition.id, "id": threat.runtime_id})
