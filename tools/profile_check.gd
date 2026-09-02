extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")
const STEP := 0.05
const PROFILE_DURATION := 20.0
const THREATS_PER_TYPE := 10

var main: AirscainMain
var samples_usec: Array[int] = []
var peak_contacts: int = 0
var peak_tracks: int = 0
var peak_projectiles: int = 0

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
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
	var steps := int(PROFILE_DURATION / STEP)
	for index: int in steps:
		var started_at := Time.get_ticks_usec()
		main._process(STEP)
		samples_usec.append(Time.get_ticks_usec() - started_at)
		peak_contacts = maxi(peak_contacts, main.registry.count())
		peak_tracks = maxi(peak_tracks, (main.player_knowledge.get("tracks") as Array).size())
		peak_projectiles = maxi(peak_projectiles, main.projectile_parent.get_child_count())
		if index % 10 == 0:
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
