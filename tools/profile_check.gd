extends SceneTree
## Fixed mixed raid CPU/render workload, without combat audio playback.
## --breakdown attributes simulation costs; --geometry counts terrain/collision queries;
## --render also measures full frames in an actual window; --night starts at midnight.
## --detail adds nested targeting/C2 timings; --render-probe uses paired exclusions.
## Timings are inclusive. Nested measurements must not be added to parent costs.

const MAIN_SCENE := preload("res://main/main.tscn")
const STEP := 0.05
const PROFILE_DURATION := 20.0
const THREATS_PER_TYPE := 10

class NestedCosts:
	extends RefCounted
	static var usec: Dictionary[String, int] = {}
	static var calls: Dictionary[String, int] = {}
	static var candidates: Dictionary[String, int] = {}

	static func record(label: String, start: int, count: int = 0) -> void:
		usec[label] = usec.get(label, 0) + Time.get_ticks_usec() - start
		calls[label] = calls.get(label, 0) + 1
		candidates[label] = candidates.get(label, 0) + count

class ProfiledGun:
	extends CloseInGun
	func setup(id_value: int, definition_value: DefenseDefinition) -> void:
		super.setup(id_value, definition_value)
		# The fresh runtime has no rounds or external audio connections yet.
		gunfire.free()
		gunfire = ProfiledGunfire.new()
		gunfire.name = "Gunfire"
		add_child(gunfire)
		gunfire.round_fired.connect(_on_round_fired)

	func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
		var start := Time.get_ticks_usec()
		var result := super.select_track(tracks, protected_position)
		NestedCosts.record("gun_select", start, tracks.size())
		return result

class ProfiledGunfire:
	extends GunfireRuntime
	func _step(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._step(delta)
		NestedCosts.record("gun_ballistics", start)

	func _sync_visuals() -> void:
		var start := Time.get_ticks_usec()
		super._sync_visuals()
		NestedCosts.record("gun_visual_buffers", start)

class ProfiledBattery:
	extends MissileBattery
	func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
		var start := Time.get_ticks_usec()
		var result := super.select_track(tracks, protected_position)
		NestedCosts.record("missile_select", start, tracks.size())
		return result

class ProfiledC2:
	extends C2Network
	func available_tracks_for(unit: DefenseUnit, tracks: Array[PlayerTrack]) -> Array[PlayerTrack]:
		var start := Time.get_ticks_usec()
		var result := super.available_tracks_for(unit, tracks)
		NestedCosts.record("c2_available_tracks", start, tracks.size())
		return result

	func _refresh_cache_if_topology_changed() -> void:
		var start := Time.get_ticks_usec()
		super._refresh_cache_if_topology_changed()
		NestedCosts.record("c2_topology_check", start)

class ProfiledKnowledge:
	extends PlayerKnowledge
	var association_usec: int = 0
	var submission_usec: int = 0
	var observation_count: int = 0
	var association_candidates: int = 0

	func _associate(observation: SensorObservation) -> PlayerTrack:
		var start := Time.get_ticks_usec()
		var result := super._associate(observation)
		association_usec += Time.get_ticks_usec() - start
		association_candidates += tracks.size()
		return result

	func submit_observation(observation: SensorObservation) -> PlayerTrack:
		var start := Time.get_ticks_usec()
		var result := super.submit_observation(observation)
		submission_usec += Time.get_ticks_usec() - start
		observation_count += 1
		return result

class ProfiledBattlefield:
	extends Battlefield
	var query_costs: Dictionary[String, int] = {}
	var query_counts: Dictionary[String, int] = {}

	func terrain_height(x: float, z: float) -> float:
		var start := Time.get_ticks_usec()
		var result := super.terrain_height(x, z)
		_record("terrain_height", start)
		return result

	func terrain_segment_impact(from_position: Vector3, to_position: Vector3) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result := super.terrain_segment_impact(from_position, to_position)
		_record("terrain_impact", start)
		return result

	func building_segment_impact(from_position: Vector3, to_position: Vector3) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result := super.building_segment_impact(from_position, to_position)
		_record("building_impact", start)
		return result

	func building_blocks_segment(from_position: Vector3, to_position: Vector3) -> bool:
		var start := Time.get_ticks_usec()
		var result := super.building_blocks_segment(from_position, to_position)
		_record("building_occlusion", start)
		return result

	func _record(label: String, start: int) -> void:
		query_costs[label] = query_costs.get(label, 0) + Time.get_ticks_usec() - start
		query_counts[label] = query_counts.get(label, 0) + 1

class ProfiledMain:
	extends AirscainMain
	var costs: Dictionary[String, int] = {}
	var tick_costs: Dictionary[String, int] = {}

	func _process(delta: float) -> void:
		if combat_effect_pool != null and not combat_effect_pool.prepared:
			return
		tactical_ui_refresh_remaining -= delta
		if tactical_ui_refresh_remaining <= 0.0:
			tactical_ui_refresh_remaining += 0.2
			_refresh_tactical_ui()
		var start := Time.get_ticks_usec()
		var simulation_delta := session.gameplay_delta(delta)
		costs["session"] = costs.get("session", 0) + Time.get_ticks_usec() - start
		_measure("day_night", day_night.apply_time, session.survival_time)
		combat_audio.simulation_paused = simulation_delta <= 0.0
		combat_audio.simulation_rate = session.simulation_speed
		if simulation_delta <= 0.0:
			return
		var step_count := ceili(simulation_delta / MAXIMUM_GAMEPLAY_STEP)
		for index: int in step_count:
			_gameplay_step(simulation_delta / float(step_count))

	func _refresh_tactical_ui() -> void:
		var start := Time.get_ticks_usec()
		super._refresh_tactical_ui()
		costs["tactical_ui"] = costs.get("tactical_ui", 0) + Time.get_ticks_usec() - start

	func _measure(label: String, action: Callable, delta: float) -> void:
		var start := Time.get_ticks_usec()
		action.call(delta)
		var elapsed := Time.get_ticks_usec() - start
		costs[label] = costs.get(label, 0) + elapsed
		tick_costs[label] = tick_costs.get(label, 0) + elapsed

	func _gameplay_step(delta: float) -> void:
		_measure("director", director.gameplay_tick, delta)
		_measure("tracking", player_knowledge.gameplay_tick, delta)
		_measure("c2", c2_network.gameplay_tick, delta)
		_measure("reservations", engagement_coordinator.gameplay_tick, delta)
		_measure("support", support_manager.gameplay_tick, delta)
		_measure("relocation", relocation_manager.gameplay_tick, delta)
		_measure("enemy_knowledge", enemy_knowledge.gameplay_tick, delta)
		power_manager.begin_tick()
		for defense: DefenseUnit in defenses:
			if is_instance_valid(defense):
				_measure("defense/" + String(defense.definition.id), defense.gameplay_tick, delta)
		for threat: ThreatUnit in registry.get_active():
			_measure("threat/" + String(threat.definition.id), threat.gameplay_tick, delta)
		for munition: AirStrikeMunition in get_tree().get_nodes_in_group(AirStrikeMunition.SIMULATION_GROUP):
			if munition.get_parent() == threat_parent and not munition.is_queued_for_deletion():
				_measure("strike_munitions", munition.gameplay_tick, delta)

var main: AirscainMain
var samples_usec: Array[int] = []
var peak_contacts: int = 0
var peak_tracks: int = 0
var peak_projectiles: int = 0
var frame_samples_usec: Array[int] = []
var peak_rounds: int = 0
var tick_rows: Array[Dictionary] = []

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	# Override only in memory so saved user preferences cannot cap or resize a run.
	var settings := PlayerSettings.instance()
	settings.values = PlayerSettings.DEFAULTS.duplicate()
	settings.apply_display()
	settings.apply_rendering()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if OS.get_cmdline_user_args().has("--gpu-timing"):
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("PROFILE_ENV godot=%s display=%s renderer=%s adapter=%s max_fps=%d" % [Engine.get_version_info().string, DisplayServer.get_name(), RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), Engine.max_fps])
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	main = MAIN_SCENE.instantiate() as AirscainMain
	if OS.get_cmdline_user_args().has("--breakdown"):
		# Replacing the root script recreates its unparented composition nodes.
		main.day_night.free()
		main.set_script(ProfiledMain)
		main.get_node("PlayerKnowledge").set_script(ProfiledKnowledge)
	if OS.get_cmdline_user_args().has("--detail"):
		main.get_node("C2Network").set_script(ProfiledC2)
	if OS.get_cmdline_user_args().has("--geometry"):
		main.get_node("Battlefield").set_script(ProfiledBattlefield)
	main.set_process(false)
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	await process_frame
	while not main.combat_effect_pool.prepared:
		await process_frame
	print("PROFILE_VIEW size=%s msaa=%d scale=%.2f" % [root.size, root.msaa_3d, root.scaling_3d_scale])
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	main.set_process(false)
	main.combat_audio.call("stop_all")
	main.objective.definition.maximum_integrity = 10000
	main.objective.current_integrity = 10000
	if OS.get_cmdline_user_args().has("--detail"):
		_profile_defense_scenes()
	_place_representative_network()
	if OS.get_cmdline_user_args().has("--large"):
		for copy: int in 3:
			_place_representative_network()
	if main.session.defense_count < main.scenario.available_defenses.size() or not main.session.start_defense():
		var deployed: Array[String] = []
		for defense: DefenseUnit in main.defenses:
			deployed.append(String(defense.definition.id))
		_fail("representative defense network could not be created: %d %s" % [main.session.defense_count, deployed])
		return
	_spawn_representative_attack()
	if OS.get_cmdline_user_args().has("--night"):
		main.session.survival_time = 450.0
		main.session.next_support_at += 450.0
	if main.battlefield is ProfiledBattlefield:
		(main.battlefield as ProfiledBattlefield).query_costs.clear()
		(main.battlefield as ProfiledBattlefield).query_counts.clear()
	var render := OS.get_cmdline_user_args().has("--render")
	if main is ProfiledMain:
		(main as ProfiledMain).costs.clear()
	var steps := int(PROFILE_DURATION / STEP)
	for index: int in steps:
		if main is ProfiledMain:
			(main as ProfiledMain).tick_costs.clear()
		var started_at := Time.get_ticks_usec()
		main._process(STEP)
		samples_usec.append(Time.get_ticks_usec() - started_at)
		if main is ProfiledMain:
			tick_rows.append({"step": index, "cpu_usec": samples_usec.back(), "costs_usec": (main as ProfiledMain).tick_costs.duplicate()})
		peak_contacts = maxi(peak_contacts, main.registry.count())
		peak_tracks = maxi(peak_tracks, (main.player_knowledge.get("tracks") as Array).size())
		peak_projectiles = maxi(peak_projectiles, main.projectile_parent.get_child_count())
		var rounds := 0
		for defense: DefenseUnit in main.defenses:
			if defense is CloseInGun:
				rounds += (defense as CloseInGun).gunfire.rounds.size()
		peak_rounds = maxi(peak_rounds, rounds)
		if render:
			await process_frame
			await RenderingServer.frame_post_draw
			if index >= 20:
				frame_samples_usec.append(Time.get_ticks_usec() - started_at)
				if main is ProfiledMain:
					tick_rows.back()["frame_usec"] = frame_samples_usec.back()
		elif index % 10 == 0:
			await process_frame
		if index % 100 == 99:
			print("PROFILE_PROGRESS steps=%d contacts=%d tracks=%d" % [index + 1, main.registry.count(), main.player_knowledge.tracks.size()])
	samples_usec.sort()
	var total_usec := 0
	for sample: int in samples_usec:
		total_usec += sample
	var average_ms := float(total_usec) / float(samples_usec.size()) / 1000.0
	var p95_index := mini(samples_usec.size() - 1, int(floor(float(samples_usec.size()) * 0.95)))
	var p95_ms := float(samples_usec[p95_index]) / 1000.0
	var maximum_ms := float(samples_usec.back()) / 1000.0
	print("PROFILE_OK samples=%d avg_ms=%.3f p95_ms=%.3f max_ms=%.3f contacts=%d tracks=%d projectiles=%d defenses=%d" % [samples_usec.size(), average_ms, p95_ms, maximum_ms, peak_contacts, peak_tracks, peak_projectiles, main.session.defense_count])
	print("PROFILE_WORKLOAD peak_gun_rounds=%d" % peak_rounds)
	print("PROFILE_RESULT remaining_contacts=%d remaining_tracks=%d city_integrity=%d" % [main.registry.count(), main.player_knowledge.tracks.size(), main.objective.current_integrity])
	if main is ProfiledMain:
		var knowledge := main.player_knowledge as ProfiledKnowledge
		print("PROFILE_NESTED association_ms=%.3f observation_ms=%.3f" % [float(knowledge.association_usec) / samples_usec.size() / 1000.0, float(knowledge.submission_usec) / samples_usec.size() / 1000.0])
		print("PROFILE_ASSOCIATION observations=%d candidate_visits=%d" % [knowledge.observation_count, knowledge.association_candidates])
		for label: String in main.costs:
			print("PROFILE_COST %s avg_ms=%.3f" % [label, float(main.costs[label]) / samples_usec.size() / 1000.0])
		var trace := FileAccess.open("/tmp/airscain_profile_steps.json", FileAccess.WRITE)
		trace.store_string(JSON.stringify(tick_rows))
	for label: String in NestedCosts.usec:
		print("PROFILE_DETAIL %s avg_ms=%.3f calls=%d candidates=%d" % [label, float(NestedCosts.usec[label]) / samples_usec.size() / 1000.0, NestedCosts.calls[label], NestedCosts.candidates[label]])
	if main.battlefield is ProfiledBattlefield:
		var world := main.battlefield as ProfiledBattlefield
		for label: String in world.query_costs:
			print("PROFILE_GEOMETRY %s avg_ms=%.3f calls=%d" % [label, float(world.query_costs[label]) / samples_usec.size() / 1000.0, world.query_counts[label]])
	if render:
		frame_samples_usec.sort()
		var total_frames := 0
		for sample: int in frame_samples_usec:
			total_frames += sample
		print("PROFILE_RENDER avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f" % [float(total_frames) / frame_samples_usec.size() / 1000.0, frame_samples_usec[frame_samples_usec.size() / 2] / 1000.0, frame_samples_usec[int(frame_samples_usec.size() * 0.95)] / 1000.0, frame_samples_usec.back() / 1000.0])
		root.get_texture().get_image().save_png("/tmp/airscain_profile_combat.png")
	if OS.get_cmdline_user_args().has("--render-probe"):
		await _render_probe()
	main.combat_audio.call("stop_all")
	main.free()
	main = null
	for index: int in 3:
		await process_frame
	quit(0)

func _profile_defense_scenes() -> void:
	# Pack instrumented subclasses before setup/ready; never replace live state.
	for definition: DefenseDefinition in main.scenario.available_defenses:
		var source: Script
		if definition is CloseInGunDefinition:
			source = ProfiledGun
		elif definition is MissileBatteryDefinition:
			source = ProfiledBattery
		else:
			continue
		var unit := definition.scene.instantiate() as DefenseUnit
		var exports: Dictionary[StringName, Variant] = {}
		for property: Dictionary in unit.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
				exports[property.name] = unit.get(property.name)
		unit.set_script(source)
		for key: StringName in exports:
			unit.set(key, exports[key])
		var packed := PackedScene.new()
		var pack_result := packed.pack(unit)
		assert(pack_result == OK)
		unit.free()
		definition.scene = packed

func _place_representative_network() -> void:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		var placed := false
		var last_reason := ""
		for z: int in range(-600, 601, 30):
			for x: int in range(-600, 601, 30):
				var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
				var result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
				last_reason = result.reason
				if result.success:
					placed = true
					break
			if placed:
				break
		if not placed:
			print("PROFILE_PLACEMENT_SKIPPED id=%s reason=%s pressure=%d unlimited=%s" % [definition.id, last_reason, main.session.current_pressure, main.session.unlimited_budget])

func _spawn_representative_attack() -> void:
	var spawn_index := 0
	var per_type := THREATS_PER_TYPE * (2 if OS.get_cmdline_user_args().has("--large") else 1)
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		for type_index: int in per_type:
			var angle := TAU * float(spawn_index) / float(main.scenario.threat_entries.size() * per_type)
			var threat := main.director._spawn_entry(entry, angle, 0.0)
			if threat != null:
				var radius := 780.0 + float(type_index % 4) * 28.0
				var altitude := 70.0
				if entry.threat_definition is AttackUavDefinition:
					altitude = (entry.threat_definition as AttackUavDefinition).movement.cruise_altitude
				threat.global_position = Vector3(cos(angle) * radius, main.battlefield.terrain_height(cos(angle) * radius, sin(angle) * radius) + altitude, sin(angle) * radius)
			spawn_index += 1

func _fail(message: String) -> void:
	push_error("PROFILE_FAILED: %s" % message)
	quit(1)

func _render_probe() -> void:
	_freeze(main)
	var sun := main.get_node("Sun") as DirectionalLight3D
	var trails: Array[Node3D] = []
	var particles: Array[Node3D] = []
	var lights: Array[Node3D] = []
	var models: Array[Node3D] = []
	var smoke_puffs := 0
	var particle_slots := 0
	for node: Node in main.find_children("*", "Node3D", true, false):
		if not (node as Node3D).is_visible_in_tree():
			continue
		if node is LingeringSmokeTrail:
			trails.append(node)
			smoke_puffs += (node as LingeringSmokeTrail).active_puff_count()
		elif node is GPUParticles3D:
			particles.append(node)
			particle_slots += (node as GPUParticles3D).amount
		elif node is OmniLight3D:
			lights.append(node)
		elif node is MeshInstance3D and main.threat_parent.is_ancestor_of(node):
			models.append(node)
	var shadow := main.battlefield.smoke_shadow_projection
	var shadow_mode := shadow.viewport.render_target_update_mode
	# The scene is stationary: cache its shadow map once, leaving receiver shading intact.
	# This isolates repeated map rendering from receiving the cached map.
	print("PROFILE_SCENE contacts=%d tracks=%d trails=%d puffs=%d particle_nodes=%d particle_slots=%d omnis=%d threat_meshes=%d shadow_update=%d" % [main.registry.count(), main.player_knowledge.tracks.size(), trails.size(), smoke_puffs, particles.size(), particle_slots, lights.size(), models.size(), shadow_mode])
	var groups: Dictionary[String, Array] = {"no_trails": trails, "no_particles": particles, "no_omnis": lights, "no_threat_meshes": models, "no_city": [main.battlefield.city_visuals]}
	var combined: Array = particles.duplicate()
	combined.append_array(lights)
	groups["no_particles_or_omnis"] = combined
	var cases: Array[String] = ["no_particles", "no_omnis", "no_particles_or_omnis", "no_trails", "cached_smoke_map", "no_threat_meshes", "no_city", "no_sun_shadows", "half_resolution", "no_ui"]
	# Reverse the second pass and remeasure the full scene around every exclusion.
	for repeat: int in 2:
		if repeat == 1:
			cases.reverse()
		await _sample_render("all/r%d/start" % repeat)
		for label: String in cases:
			if groups.has(label):
				for node: Node3D in groups[label]:
					node.hide()
			elif label == "cached_smoke_map":
				shadow.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			elif label == "no_sun_shadows":
				sun.shadow_enabled = false
			elif label == "half_resolution":
				root.scaling_3d_scale = 0.5
			elif label == "no_ui":
				(main.get_node("UI") as CanvasLayer).hide()
			await _sample_render("%s/r%d" % [label, repeat])
			if groups.has(label):
				for node: Node3D in groups[label]:
					node.show()
			elif label == "cached_smoke_map":
				shadow.viewport.render_target_update_mode = shadow_mode
			elif label == "no_sun_shadows":
				sun.shadow_enabled = true
			elif label == "half_resolution":
				root.scaling_3d_scale = 1.0
			elif label == "no_ui":
				(main.get_node("UI") as CanvasLayer).show()
			await _sample_render("all/r%d/after_%s" % [repeat, label])

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is GPUParticles3D:
		(node as GPUParticles3D).speed_scale = 0.0
	for child: Node in node.get_children():
		_freeze(child)

func _sample_render(label: String) -> void:
	var samples: Array[int] = []
	var render_cpu := 0.0
	var render_gpu := 0.0
	for index: int in 40:
		var start := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if index >= 10:
			samples.append(Time.get_ticks_usec() - start)
			render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
			render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	var total := 0
	for sample: int in samples:
		total += sample
	samples.sort()
	print("PROFILE_PROBE %s avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f draws=%d primitives=%d" % [label, float(total) / samples.size() / 1000.0, samples[samples.size() / 2] / 1000.0, samples[int(samples.size() * 0.95)] / 1000.0, samples.back() / 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	if OS.get_cmdline_user_args().has("--gpu-timing"):
		print("PROFILE_VIEWPORT %s cpu_ms=%.3f gpu_ms=%.3f" % [label, render_cpu / samples.size(), render_gpu / samples.size()])
