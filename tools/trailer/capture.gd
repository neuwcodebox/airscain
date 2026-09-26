extends SceneTree
## Staged camera takes using the real game economy, placement and combat runtime.
## No content definitions, damage, tracking or weapon performance are modified.

const MAIN := preload("res://main/main.tscn")
var main: AirscainMain
var shot := "overview"
var language := "ko"
var seconds := 18.0
var output := "res://build/trailer/review"
var frame := 0
var first_movie_frame := 0
var units: Dictionary[StringName, Array] = {}
var events: Array[Dictionary] = []
var peak_threats := 0
var focus: DefenseUnit
var site := Vector3(350, 0, 0)
var last_spawn := -100.0
var camera_start := Vector3.ZERO
var camera_target := Vector3.ZERO
var early := false
var observed_support: Dictionary[int, bool] = {}

func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--lang="): language = arg.trim_prefix("--lang=")
		elif arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
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
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
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
	# Exclude recordings without a source/license record from promotional media.
	main.combat_audio.uav_loops.free()
	main.combat_audio.uav_loops = null
	main.combat_audio.approaches.free()
	main.combat_audio.approaches = null
	main.combat_audio.cruise_approaches.free()
	main.combat_audio.cruise_approaches = null
	main.day_night.apply_time(0.0, true)
	early = shot in ["opening", "placement", "network"]
	main.session.start_defense()
	# A prebuilt later-operation fixture: finite funds and real purchases.
	if not early:
		main.session.survival_time = 1440.0
		main.session.next_support_at = 1530.0
		main.session.update_pressure(14)
		main.hud.set_pressure(14)
		main.director.pressure_level = 14
		for payment: int in 65:
			main.session.grant_regular_support(main.scenario.support_amount)
	_build_fixture()
	if DisplayServer.get_name() == "headless":
		print("TRAILER_FIXTURE assets=%d budget=%d pressure=%d" % [main.defenses.size(), main.session.budget, main.session.current_pressure])
		focus = null
		units.clear()
		main.queue_free()
		await process_frame
		main = null
		quit(0)
		return
	if focus == null:
		push_error("TRAILER: no focus asset for " + shot)
		quit(2)
		return
	main.session.start_defense()
	main.hud.set_feedback("", false)
	main.director.enabled = false
	main.director.elapsed = 0.0
	main.camera_rig.input_blocked = true
	_set_camera()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for settle: int in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	first_movie_frame = Engine.get_frames_drawn()
	print("TRAILER_START shot=%s frame=%d focus=%s" % [shot, first_movie_frame, focus.global_position])
	for index: int in int(seconds * 60.0):
		frame = index
		var t := float(frame) / 60.0
		_direct(t)
		await process_frame
		await RenderingServer.frame_post_draw
		peak_threats = maxi(peak_threats, main.registry.hostile_count())
		for unit: DefenseUnit in main.defenses:
			if is_instance_valid(unit) and not observed_support.has(unit.runtime_id) and main.support_manager.task_status(unit) != "":
				observed_support[unit.runtime_id] = true
				events.append({"frame": frame, "event": "support", "asset": unit.definition.id, "task": main.support_manager.task_status(unit)})
		if index % 120 == 60:
			root.get_texture().get_image().save_png("%s/%s_%s_%04d.png" % [output, shot, language, index])
	var report := {
		"shot": shot, "language": language, "first_movie_frame": first_movie_frame,
		"frames": frame + 1, "peak_threats": peak_threats,
		"kills": main.session.neutralized_count, "city_integrity": main.objective.current_integrity,
		"events": events, "assets": [], "fixture": "staged finite-budget capture; real runtime rules",
	}
	for unit: DefenseUnit in main.defenses:
		if is_instance_valid(unit):
			report.assets.append({"id": unit.definition.id, "position": [unit.position.x, unit.position.y, unit.position.z]})
	var file := FileAccess.open("%s/%s_%s.json" % [output, shot, language], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TRAILER_DONE shot=%s threats=%d kills=%d integrity=%d events=%d" % [shot, peak_threats, main.session.neutralized_count, main.objective.current_integrity, events.size()])
	focus = null
	units.clear()
	main.queue_free()
	await process_frame
	main = null
	await process_frame
	quit(0)

func _build_fixture() -> void:
	_buy(&"command_post", Vector3(230, 0, 0))
	if shot != "placement": _buy(&"search_radar", Vector3(330, 0, 90))
	if early:
		focus = _buy(&"missile_battery", Vector3(350, 0, -60))
		_buy(&"close_in_gun", Vector3(270, 0, -140))
		return
	_buy(&"tracking_radar", Vector3(300, 0, 170))
	_buy(&"support_facility", Vector3(310, 0, -30))
	_buy(&"support_facility", Vector3(360, 0, 70))
	if shot in ["overview", "crisis", "closing", "support"]:
		for sector: int in 3:
			var z := float(sector - 1) * 240.0
			_buy(&"command_post", Vector3(220, 0, z))
			_buy(&"search_radar", Vector3(340, 0, z + 40))
			_buy(&"tracking_radar", Vector3(290, 0, z + 90))
			_buy(&"support_facility", Vector3(330, 0, z - 20))
			_buy(&"support_facility", Vector3(270, 0, z - 60))
			var ids: Array[StringName] = [&"missile_battery", &"long_range_missile", &"short_range_missile", &"close_in_gun", &"high_energy_laser", &"high_power_microwave", &"interceptor_drone_defense"]
			for k: int in ids.size():
				var u := _buy(ids[k], Vector3(410 + (k % 2) * 55, 0, z - 70 + k * 23))
				if focus == null and u != null: focus = u
		_buy(&"radar_decoy", Vector3(600, 0, -120))
		_buy(&"weapon_decoy", Vector3(610, 0, 130))
	else:
		var id: StringName = StringName(shot)
		if shot == "radar": id = &"long_range_missile"
		focus = _buy(id, Vector3(410, 0, -70))
	if shot == "support": focus = _first(&"support_facility")

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

func _set_camera() -> void:
	var wide := early or shot in ["overview", "crisis", "closing", "radar", "support"]
	main.hud.visible = wide and shot != "closing"
	main.altitude_profile.visible = shot in ["overview", "crisis", "radar"]
	main.tactical_screen_overlay.visible = wide and shot != "closing"
	main.track_display.visible = wide and shot != "closing"
	for unit: DefenseUnit in main.defenses:
		unit.identity_marker.visible = wide and shot != "closing"
		unit.status_marker.visible = wide and shot != "closing"
	if wide:
		camera_start = Vector3(310, 560, -840)
		camera_target = Vector3(260, 50, 0)
		if not early:
			camera_start = Vector3(390, 820, -1210)
			camera_target = Vector3(350, 100, 0)
		if shot == "radar":
			var radar := _first(&"tracking_radar")
			camera_start = radar.global_position + Vector3(-65, 60, -140)
			camera_target = radar.global_position + Vector3(25, 12, 0)
	else:
		camera_start = focus.global_position + Vector3(-85, 68, -160)
		camera_target = focus.global_position + Vector3(65, 25, 0)
		if shot == "long_range_missile":
			camera_start = focus.global_position + Vector3(-105, 120, -235)
			camera_target = focus.global_position + Vector3(100, 35, 0)
	main.camera_rig.camera.global_position = camera_start
	main.camera_rig.camera.look_at(camera_target)

func _direct(t: float) -> void:
	# Preserve original game frame stepping; only schedule spawns, input and camera.
	if not is_instance_valid(focus): return
	if shot == "placement":
		_placement_take(t)
		return
	if shot == "network":
		if frame == 0: main.placement.asset_selected.emit(_first(&"command_post"))
	if shot == "radar" and frame == 0:
		main.placement.asset_selected.emit(_first(&"tracking_radar"))
	if shot in ["overview", "crisis", "closing", "support"]:
		if t - last_spawn >= 1.0 and main.registry.hostile_count() < 95:
			last_spawn = t
			for k: int in 10:
				var ids: Array[StringName] = [&"attack_uav", &"swarm_uav", &"cruise_missile", &"attack_uav", &"swarm_uav"]
				var p := Vector3(780 + (k % 3) * 130, 0, float(k - 5) * 86 + sin(t) * 50)
				_spawn(ids[k % ids.size()], p)
			if int(t) % 3 == 0:
				_spawn(&"ballistic_missile", Vector3(1350, 0, 160))
				_spawn(&"strike_aircraft", Vector3(1400, 0, -220))
		if shot == "support" and frame == 300:
			main.placement.asset_selected.emit(focus)
			main.hud.overlay_option.select(3)
			main.hud.overlay_option.item_selected.emit(3)
			main.camera_rig.camera.global_position = focus.global_position + Vector3(-140, 130, -250)
			main.camera_rig.camera.look_at(focus.global_position + Vector3(50, 10, 10))
		if shot == "support" and frame >= 360 and frame % 60 == 0:
			for unit: DefenseUnit in main.defenses:
				if unit.can_request_resupply():
					unit.request_resupply()
		if shot == "crisis":
			main.camera_rig.camera.global_position = camera_start.lerp(camera_start + Vector3(0, 80, -110), t / seconds)
			main.camera_rig.camera.look_at(camera_target)
	else:
		if t - last_spawn >= (3.5 if early else 2.0):
			last_spawn = t
			var id: StringName = &"attack_uav"
			var distance := 220.0
			var count := 2
			if shot in ["close_in_gun", "high_energy_laser", "high_power_microwave", "short_range_missile"]:
				id = &"swarm_uav"
				distance = 185.0
				count = 5
			elif shot in ["long_range_missile", "radar"]:
				id = &"strike_aircraft"
				distance = 900.0
			elif shot in ["radar_decoy", "weapon_decoy"]:
				id = &"radar_strike_aircraft" if shot == "radar_decoy" else &"battery_strike_uav"
				distance = 400.0
				count = 1
			for k: int in count:
				var p := focus.global_position + Vector3(distance + k * 15, 0, (k - count / 2) * 20)
				_spawn(id, p, focus if shot in ["radar_decoy", "weapon_decoy"] else null)
			if shot == "radar" and int(t) % 4 == 0:
				_spawn(&"ballistic_missile", focus.global_position + Vector3(1100, 0, 180))

func _placement_take(t: float) -> void:
	if frame == 30: main.hud.set_catalog_expanded(true)
	if frame == 100:
		main.placement.select(_definition(&"search_radar"))
		main.hud.set_catalog_expanded(false)
	if frame >= 100 and frame < 240:
		var p := Vector3(330, 0, 90)
		p.y = main.battlefield.terrain_height(p.x, p.z)
		main.placement.candidate_position = p
		main.placement.preview.global_position = p
		main.placement.preview.visible = true
		var valid := bool(main.battlefield.placement_result(p, _definition(&"search_radar").placement_profile).valid)
		main.placement.preview_material.albedo_color = Color(0.18, 0.95, 0.42, 0.48) if valid else Color(1.0, 0.18, 0.12, 0.52)
		main.placement.placement_preview_changed.emit(_definition(&"search_radar"), p, true)
	if frame == 240:
		if not main.placement.request_selected_defense_placement(): push_error("TRAILER placement interaction failed")
		main.placement.cancel()
	if frame == 300: main.placement.asset_selected.emit(_first(&"command_post"))
	if frame == 450: main.placement.world_selected.emit(Vector3.INF, Vector2.INF)
	if t > 8.0 and t - last_spawn > 3.0:
		last_spawn = t
		_spawn(&"attack_uav", Vector3(630, 0, -50))

func _spawn(id: StringName, position: Vector3, target: DefenseUnit = null) -> void:
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id != id: continue
		var threat := main.director.spawn_entry_at(entry, position, target)
		if threat != null:
			threat.resolved.connect(_resolved)
		return
	push_error("TRAILER missing threat " + id)

func _fired(unit: DefenseUnit, _low: bool) -> void:
	events.append({"frame": frame, "event": "fire", "asset": unit.definition.id})

func _resolved(threat: ThreatUnit, neutralized: bool, _reward: int) -> void:
	events.append({"frame": frame, "event": "kill" if neutralized else "impact_or_exit", "threat": threat.definition.id})
