extends SceneTree
## Staged gameplay takes. Fleet pre-positioned; ballistic launch stays offscreen.
const MAIN := preload("res://main/main.tscn")
var main: AirscainMain
var shot := "intro"
var language := "ko"
var seconds := 12.0
var output := "res://build/trailer_v7/review"
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
var camera_frames: Array[Dictionary] = []
var ballistic: AttackUav
var warning_phase := ""
var cinematic_speed := 1.0
var ballistic_origin := Vector3(-10600, 0, 80)
var ballistic_seed := 123
var opening_uav: ThreatUnit
var hero_interceptor: HomingInterceptor

func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--lang="): language = arg.trim_prefix("--lang=")
		elif arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg.begins_with("--ballistic-seed="): ballistic_seed = int(arg.trim_prefix("--ballistic-seed="))
		elif arg.begins_with("--ballistic-z="): ballistic_origin.z = float(arg.trim_prefix("--ballistic-z="))
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
	if shot != "intro":
		main.session.survival_time = 1440.0
		main.session.next_support_at = 1530.0
		main.session.update_pressure(14)
		main.hud.set_pressure(14)
		main.director.pressure_level = 14
		for payment: int in 65:
			main.session.grant_regular_support(main.scenario.support_amount)
	if shot != "intro":
		main.player_knowledge.track_created.disconnect(main._on_track_contact_audio)
	_build_fixture()
	initial_assets = _asset_state()
	main.session.defense_placed.connect(_placed)
	main.director.enabled = false
	main.camera_rig.input_blocked = true
	_hud(shot == "intro")
	if shot == "intro":
		_pose(Vector3(310, 430, -670), Vector3(260, 45, 0), 65)
	else:
		_direct_camera(0)
	_preflight_attack()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for settle: int in 30:
		await process_frame
		if not probe: await RenderingServer.frame_post_draw
	first_movie_frame = Engine.get_frames_drawn()
	if camera_preview:
		for moment: float in [0.0, 3.0, 6.0, 10.0, 14.0, 18.0, 22.0, 26.0]:
			_raid_camera(moment)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/camera_%04d.png" % [output, int(moment * 60)])
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
		if shot == "raid":
			if frame == 570:
				main.director.rng.seed = ballistic_seed
				_spawn(&"ballistic_missile", ballistic_origin)
				events.append({"frame": frame, "event": "ballistic_launch"})
			cinematic_speed = 0.5 if t >= 41.5 else 1.0
			Engine.time_scale = cinematic_speed
			if t >= 41.5: t = 41.5 + (t-41.5)*0.5
		if shot == "intro": _intro(t)
		else: _direct_camera(t)
		var camera_position := main.camera_rig.camera.global_position
		camera_frames.append({"frame": frame, "p": [camera_position.x, camera_position.y, camera_position.z], "fov": main.camera_rig.camera.fov, "time_scale": cinematic_speed, "simulation_second": t})
		await process_frame
		if not probe: await RenderingServer.frame_post_draw
		if is_instance_valid(ballistic):
			var phase := str(ballistic.mover.ballistic_phase())
			if phase != warning_phase:
				warning_phase = phase
				events.append({"frame":frame,"event":"ballistic_phase","phase":phase})
			if t >= 39.0:
				var screen := main.camera_rig.camera.unproject_position(ballistic.global_position)
				camera_frames.back()["missile_clearance"] = ballistic.global_position.y - main.battlefield.flight_surface_height(ballistic.global_position.x, ballistic.global_position.z)
				if is_instance_valid(hero_interceptor):
					var q := hero_interceptor.global_position
					var screen_q := main.camera_rig.camera.unproject_position(q)
					var viewport_size := main.camera_rig.camera.get_viewport().get_visible_rect().size
					camera_frames.back()["interceptor_screen"] = [screen_q.x/viewport_size.x,screen_q.y/viewport_size.y]
					camera_frames.back()["interceptor_distance"] = q.distance_to(ballistic.global_position)
					camera_frames.back()["interceptor_position"] = [q.x,q.y,q.z]
					camera_frames.back()["interceptor_visible"] = not main.battlefield.building_blocks_segment(camera_position,q)
				camera_frames.back()["missile_position"] = [ballistic.global_position.x, ballistic.global_position.y, ballistic.global_position.z]
				camera_frames.back()["missile_screen"] = [screen.x / main.camera_rig.camera.get_viewport().get_visible_rect().size.x, screen.y / main.camera_rig.camera.get_viewport().get_visible_rect().size.y]
		peak_threats = maxi(peak_threats, main.registry.hostile_count())
		if index % 60 == 0:
			var positions: Array[Dictionary] = []
			for threat: ThreatUnit in main.registry.get_active():
				positions.append({"id": threat.runtime_id, "type": threat.definition.id, "p": [threat.position.x, threat.position.y, threat.position.z]})
			samples.append({"frame": frame, "city": main.objective.current_integrity, "kills": main.session.neutralized_count, "active": main.registry.hostile_count(), "camera": camera_cut, "threats": positions})
		if not probe and (index % 120 == 60 or index in [0,90,210,420,540,660,2340,2460] or (shot == "raid" and index >= 2480 and index % 2 == 0)):
			root.get_texture().get_image().save_png("%s/%s_%s_%04d.png" % [output, shot, language, index])
	var report := {"shot": shot, "language": language, "first_movie_frame": first_movie_frame,
		"frames": frame + 1, "peak_threats": peak_threats, "kills": main.session.neutralized_count,
		"city_integrity": main.objective.current_integrity, "events": events, "births": births,
		"initial_assets": initial_assets, "assets": _asset_state(), "samples": samples,
		"camera_frames": camera_frames, "continuous_take": true, "scripted_spawns_during_capture": 1 if shot == "raid" else 0,
		"contact_audio_events": main.combat_audio.played_count(CombatAudio.CONTACT),
		"fixture": "finite-budget deployment; unchanged combat; fleet pre-spawned; ballistic launch outside camera"}
	var suffix := "_probe" if probe else ""
	var file := FileAccess.open("%s/%s_%s%s.json" % [output, shot, language, suffix], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TRAILER_DONE shot=%s threats=%d kills=%d integrity=%d" % [shot, peak_threats, main.session.neutralized_count, main.objective.current_integrity])
	Engine.time_scale = 1.0
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
	if shot == "intro": return
	_buy(&"search_radar", Vector3(330, 0, 90))
	_buy(&"missile_battery", Vector3(358.4853, 0, -51.5147))
	_buy(&"close_in_gun", Vector3(270, 0, -140))
	if shot == "expansion": return
	for sector: int in 3: _sector(sector)

func _sector(sector: int) -> void:
	var z := float(sector - 1) * 240.0
	_buy(&"command_post", Vector3(220, 0, z))
	_buy(&"search_radar", Vector3(340, 0, z + 40))
	_buy(&"tracking_radar", Vector3(290, 0, z + 90))
	_buy(&"support_facility", Vector3(330, 0, z - 20))
	_buy(&"support_facility", Vector3(270, 0, z - 60))
	var ids: Array[StringName] = [&"missile_battery", &"long_range_missile", &"short_range_missile", &"close_in_gun", &"high_energy_laser", &"high_power_microwave", &"interceptor_drone_defense"]
	for k: int in ids.size():
		_buy(ids[k], Vector3(410 + (k % 2) * 55, 0, z - 70 + k * 23))

func _direct_camera(t: float) -> void:
	if shot == "expansion":
		if frame in [0, 120, 240]:
			_sector(frame / 120)
			_hud(false)
			events.append({"frame": frame, "event": "expansion", "count": main.defenses.size()})
		_expansion_camera(t)
	else:
		if t >= 39.0: _ballistic_camera(t)
		else: _raid_camera(t)

func _expansion_camera(t: float) -> void:
	_travel(clampf(t / 6.0, 0.0, 1.0), Vector3(230,260,-400), Vector3(230,260,160), Vector3(360,0,-240), Vector3(360,0,240),50,50)

func _closing_interceptor() -> HomingInterceptor:
	var nearest: HomingInterceptor
	var distance := INF
	for child: Node in main.projectile_parent.get_children():
		var candidate := child as HomingInterceptor
		if candidate == null or candidate.target_track == null: continue
		if candidate.target_track.estimated_position.distance_to(ballistic.global_position) > 150: continue
		var d := candidate.global_position.distance_to(ballistic.global_position)
		if d < distance:
			nearest = candidate
			distance = d
	return nearest

func _ballistic_camera(t: float) -> void:
	if not is_instance_valid(ballistic): return # Full take may include outcome; edit stops beforehand.
	var p := ballistic.global_position
	var forward := Vector3(ballistic.target_point.x-p.x,0,ballistic.target_point.z-p.z).normalized()
	var chase := p-forward*55.0+forward.cross(Vector3.UP)*33.0+Vector3.UP*69.0
	var aim := p+forward*25.0+Vector3.DOWN*85.0
	hero_interceptor = _closing_interceptor()
	var lens := 60.0
	if is_instance_valid(hero_interceptor):
		var q := hero_interceptor.global_position
		var separation := p.distance_to(q)
		var blend := smoothstep(40.8,41.6,t) * (1.0-smoothstep(450.0,700.0,separation))
		var toward := Vector3(q.x-p.x,0,q.z-p.z).normalized()
		# Clear the intervening city roofs so the low interceptor remains visible.
		var pair_position := p-toward*50.0-toward.cross(Vector3.UP)*100.0+Vector3.UP*250.0
		var pair_aim := p+toward*90.0+Vector3.DOWN*5.0
		chase = chase.lerp(pair_position,blend)
		aim = aim.lerp(pair_aim,blend)
		lens = lerpf(60.0,55.0,blend)
	_pose(chase,aim,lens)
	if frame == 2340: events.append({"frame":frame,"event":"camera","hard_cut":true,"cut":"ballistic"})

func _preflight_attack() -> void:
	if shot == "expansion": return
	if shot == "intro":
		for k: int in 3: _spawn(&"attack_uav", Vector3(1020 + k * 40, 0, -80 + k * 35))
		return
	# Depth-separated fleet waves naturally arrive at different times.
	# The ballistic launch is scheduled separately, outside the camera frustum.
	for row: int in 6:
		for column: int in 14:
			var id: StringName = &"attack_uav" if column % 4 == 0 else &"swarm_uav"
			_spawn(id, Vector3(1518 + row * 220 + (column % 3) * 24, 0, -390 + column * 60))
	for k: int in 8:
		_spawn(&"strike_aircraft", Vector3(4018 + (k / 4) * 600, 0, -330 + (k % 4) * 220))
	for k: int in 8:
		_spawn(&"cruise_missile", Vector3(2488 + k * 160, 0, -320 + (k % 4) * 205))

func _placed(unit: DefenseUnit) -> void:
	if not units.has(unit.definition.id): units[unit.definition.id] = []
	units[unit.definition.id].append(unit)
	unit.weapon_fired.connect(_fired)

func _placement_action(id: StringName, begin: int, end: int, location: Vector3) -> void:
	if frame == begin:
		main.placement.select(_definition(id))
		main.hud.set_catalog_expanded(false)
	if frame >= begin and frame < end:
		var p := location
		p.y = main.battlefield.terrain_height(p.x, p.z)
		main.placement.candidate_position = p
		main.placement.preview.global_position = p
		main.placement.preview.visible = true
		var valid := bool(main.battlefield.placement_result(p, _definition(id).placement_profile).valid)
		main.placement.preview_material.albedo_color = Color(0.18, 0.95, 0.42, 0.48) if valid else Color(1.0, 0.18, 0.12, 0.52)
		main.placement.placement_preview_changed.emit(_definition(id), p, true)
	if frame == end:
		if not main.placement.request_selected_defense_placement():
			push_error("TRAILER placement interaction failed: " + id)
			return
		main.placement.cancel()
		events.append({"frame": frame, "event": "radar_placed" if id == &"search_radar" else "asset_placed", "asset": id, "assets": _asset_state()})

func _intro(t: float) -> void:
	if t < 5.0:
		_hud(false)
		var p := opening_uav.global_position
		_travel(clampf((t-1.5)/3.5,0.0,1.0),p+Vector3(-20,12,-28),Vector3(290,90,-30),p,Vector3(330,15,90),50,50)
		return
	if frame == 300: _hud(true)
	if frame == 320: main.hud.set_catalog_expanded(true)
	_placement_action(&"search_radar",360,420,Vector3(330,0,90))
	_placement_action(&"missile_battery",456,540,Vector3(358.4853,0,-51.5147))
	_placement_action(&"close_in_gun",576,660,Vector3(270,0,-140))
	if frame == 690: main.placement.asset_selected.emit(_first(&"command_post"))
	if frame == 780: main.placement.world_selected.emit(Vector3.INF,Vector2.INF)
	if frame == 900: main.hud.visible=false
	main.track_display.visible=true
	for marker: TrackMarker in main.track_display.markers.values():
		marker.icon.fixed_size=true
		marker.icon.pixel_size=0.001
	for unit: DefenseUnit in main.defenses:
		unit.identity_marker.visible=true
		unit.identity_marker.icon.pixel_size=0.001
	if t<7.0: _pose(Vector3(290,90,-30),Vector3(330,15,90),50)
	elif t<9.0: _travel((t-7)/1.5,Vector3(290,90,-30),Vector3(310,105,-210),Vector3(330,15,90),Vector3(350,15,-40),50,50)
	elif t<11.0: _travel((t-9)/1.5,Vector3(310,105,-210),Vector3(230,90,-260),Vector3(350,15,-40),Vector3(270,15,-140),50,50)
	elif t<15.0: _travel((t-11)/4.0,Vector3(230,90,-260),Vector3(260,180,-340),Vector3(270,15,-140),Vector3(350,25,-100),50,50)
	else: _travel((t-15)/2.0,Vector3(260,180,-340),Vector3(230,260,-400),Vector3(350,25,-100),Vector3(360,0,-240),50,50)

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

func _ground(x: float, z: float, height: float) -> Vector3:
	return Vector3(x, main.battlefield.terrain_height(x, z) + height, z)

func _travel(progress: float, start: Vector3, end: Vector3, aim_start: Vector3, aim_end: Vector3, lens_start: float, lens_end: float) -> void:
	var u := smoothstep(0.0, 1.0, progress)
	_pose(start.lerp(end, u), aim_start.lerp(aim_end, u), lerpf(lens_start, lens_end, u))

func _raid_camera(t: float) -> void:
	var cuts: Array[float] = [0, 6, 14, 20.5, 27, 33.5, 39]
	var selected := 0
	for k: int in cuts.size() - 1:
		if t >= cuts[k]: selected = k
	var u := clampf((t - cuts[selected]) / (cuts[selected + 1] - cuts[selected]), 0.0, 1.0)
	var changed := selected != camera_cut
	camera_cut = selected
	match selected:
		0: _expansion_camera(t)
		1: _travel(u, Vector3(230,260,160), Vector3(880,130,-260), Vector3(360,0,240), Vector3(1540,115,0), 50,43)
		2: _travel(u, Vector3(310, 105, -210), Vector3(340, 95, -180), Vector3(650, 85, 70), Vector3(680, 85, 70), 65, 60)
		3: _travel(u, Vector3(430, 90, -380), Vector3(465, 80, -350), Vector3(790, 90, 30), Vector3(790, 90, 50), 65, 60)
		4: _travel(u, Vector3(370, 52, -115), Vector3(385, 45, -95), Vector3(680, 95, 30), Vector3(680, 95, 50), 62, 60)
		5: _travel(u, _ground(435, -30, 6), _ground(440, -24, 6), Vector3(640, 80, 60), Vector3(640, 80, 70), 68, 63)
	if changed:
		events.append({"frame": frame, "event": "camera", "cut": selected, "hard_cut": selected > 1})

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
			if not units[id].has(unit): units[id].append(unit)
			if not unit.weapon_fired.is_connected(_fired): unit.weapon_fired.connect(_fired)
			return unit
	push_error("TRAILER: placement failed %s reason=%s budget=%d pressure=%d" % [id, failure, main.session.budget, main.session.current_pressure])
	return null

func _first(id: StringName) -> DefenseUnit:
	return units[id][0] as DefenseUnit if units.has(id) and not units[id].is_empty() else null


func _spawn(id: StringName, position: Vector3) -> void:
	if recording and id != &"ballistic_missile":
		push_error("TRAILER: aircraft spawn attempted during capture")
		return
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id != id: continue
		var threat := main.director.spawn_entry_at(entry, position)
		if threat != null:
			if shot == "intro" and not is_instance_valid(opening_uav): opening_uav = threat
			if id == &"ballistic_missile":
				ballistic = threat as AttackUav
			threat.resolved.connect(_resolved)
			births.append({"frame": frame, "outside_view": not main.camera_rig.camera.is_position_in_frustum(threat.global_position), "id": threat.runtime_id, "type": id, "p": [threat.position.x, threat.position.y, threat.position.z]})
		return
	push_error("TRAILER missing threat " + id)

func _fired(unit: DefenseUnit, _low: bool) -> void:
	events.append({"frame": frame, "event": "fire", "asset": unit.definition.id, "id": unit.runtime_id})

func _resolved(threat: ThreatUnit, neutralized: bool, _reward: int) -> void:
	events.append({"frame": frame, "event": "kill" if neutralized else "impact_or_exit", "threat": threat.definition.id, "id": threat.runtime_id})
