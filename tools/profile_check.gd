extends SceneTree
## Fixed mixed raid CPU workload. --breakdown attributes simulation costs;
## --render also measures full frames in an actual window; --night starts at midnight.

const MAIN_SCENE := preload("res://main/main.tscn")
const STEP := 0.05
const PROFILE_DURATION := 20.0
const THREATS_PER_TYPE := 10

class ProfiledMain:
	extends AirscainMain
	var costs: Dictionary[String, int] = {}

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
		costs[label] = costs.get(label, 0) + Time.get_ticks_usec() - start

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

var main: AirscainMain
var samples_usec: Array[int] = []
var peak_contacts: int = 0
var peak_tracks: int = 0
var peak_projectiles: int = 0
var frame_samples_usec: Array[int] = []

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	main = MAIN_SCENE.instantiate() as AirscainMain
	if OS.get_cmdline_user_args().has("--breakdown"):
		main.set_script(ProfiledMain)
	main.set_process(false)
	root.add_child(main)
	await process_frame
	while not main.combat_effect_pool.prepared:
		await process_frame
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	main.set_process(false)
	main.combat_audio.call("stop_all")
	main.objective.definition.maximum_integrity = 10000
	main.objective.current_integrity = 10000
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
	var render := OS.get_cmdline_user_args().has("--render")
	var steps := int(PROFILE_DURATION / STEP)
	for index: int in steps:
		var started_at := Time.get_ticks_usec()
		main._process(STEP)
		samples_usec.append(Time.get_ticks_usec() - started_at)
		peak_contacts = maxi(peak_contacts, main.registry.count())
		peak_tracks = maxi(peak_tracks, (main.player_knowledge.get("tracks") as Array).size())
		peak_projectiles = maxi(peak_projectiles, main.projectile_parent.get_child_count())
		if render:
			await process_frame
			await RenderingServer.frame_post_draw
			if index >= 20:
				frame_samples_usec.append(Time.get_ticks_usec() - started_at)
		elif index % 10 == 0:
			await process_frame
	samples_usec.sort()
	var total_usec := 0
	for sample: int in samples_usec:
		total_usec += sample
	var average_ms := float(total_usec) / float(samples_usec.size()) / 1000.0
	var p95_index := mini(samples_usec.size() - 1, int(floor(float(samples_usec.size()) * 0.95)))
	var p95_ms := float(samples_usec[p95_index]) / 1000.0
	var maximum_ms := float(samples_usec.back()) / 1000.0
	print("PROFILE_OK samples=%d avg_ms=%.3f p95_ms=%.3f max_ms=%.3f contacts=%d tracks=%d projectiles=%d defenses=%d" % [samples_usec.size(), average_ms, p95_ms, maximum_ms, peak_contacts, peak_tracks, peak_projectiles, main.session.defense_count])
	if main is ProfiledMain:
		for label: String in main.costs:
			print("PROFILE_COST %s avg_ms=%.3f" % [label, float(main.costs[label]) / samples_usec.size() / 1000.0])
	if render:
		frame_samples_usec.sort()
		var total_frames := 0
		for sample: int in frame_samples_usec:
			total_frames += sample
		print("PROFILE_RENDER avg_ms=%.3f p95_ms=%.3f" % [float(total_frames) / frame_samples_usec.size() / 1000.0, frame_samples_usec[int(frame_samples_usec.size() * 0.95)] / 1000.0])
		root.get_texture().get_image().save_png("/tmp/airscain_profile_combat.png")
	if OS.get_cmdline_user_args().has("--render-probe"):
		await _render_probe()
	main.combat_audio.call("stop_all")
	main.free()
	main = null
	for index: int in 3:
		await process_frame
	quit(0)

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
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		for type_index: int in THREATS_PER_TYPE:
			var angle := TAU * float(spawn_index) / float(main.scenario.threat_entries.size() * THREATS_PER_TYPE)
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
	await _sample_render("all")
	var sun := main.get_node("Sun") as DirectionalLight3D
	sun.shadow_enabled = false
	await _sample_render("no_sun_shadows")
	sun.shadow_enabled = true
	var trails: Array[Node3D] = []
	var particles: Array[Node3D] = []
	var lights: Array[Node3D] = []
	var models: Array[Node3D] = []
	for node: Node in main.find_children("*", "Node3D", true, false):
		if not (node as Node3D).visible:
			continue
		if node is LingeringSmokeTrail:
			trails.append(node)
		elif node is GPUParticles3D:
			particles.append(node)
		elif node is OmniLight3D:
			lights.append(node)
		elif node is MeshInstance3D and main.threat_parent.is_ancestor_of(node):
			models.append(node)
	for group: Array[Node3D] in [trails, particles, lights, models]:
		for node: Node3D in group:
			node.hide()
		await _sample_render(["no_trails", "no_particles", "no_omnis", "no_threat_meshes"][[trails, particles, lights, models].find(group)])
		for node: Node3D in group:
			node.show()
	main.battlefield.city_visuals.hide()
	await _sample_render("no_city")
	main.battlefield.city_visuals.show()

func _freeze(node: Node) -> void:
	node.set_process(false)
	if node is GPUParticles3D:
		(node as GPUParticles3D).speed_scale = 0.0
	for child: Node in node.get_children():
		_freeze(child)

func _sample_render(label: String) -> void:
	var samples: Array[int] = []
	for index: int in 50:
		var start := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if index >= 10:
			samples.append(Time.get_ticks_usec() - start)
	var total := 0
	for sample: int in samples:
		total += sample
	print("PROFILE_PROBE %s avg_ms=%.3f draws=%d primitives=%d" % [label, float(total) / samples.size() / 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
