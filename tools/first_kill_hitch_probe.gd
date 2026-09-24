extends SceneTree
## Real-window probe for first-kill stalls: a missile battery shoots down
## successive attack UAVs outside the city and every kill reports its frame
## time plus later frames over the stall threshold (for example a debris
## lighting variant when the blast light ends). Headless timings are not valid.

const APP := preload("res://main/app.tscn")
const KILLS := 4
const FOLLOW_FRAMES := 160
const STALL_MS := 110.0

var app: AirscainApp
var main: AirscainMain

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	app = APP.instantiate() as AirscainApp
	root.add_child(app)
	while not app.combat_vfx_warmup_completed:
		await process_frame
	app._create_gameplay(AirscainMain.GameMode.SANDBOX, 73129)
	main = app.gameplay
	while not main.combat_effect_pool.prepared:
		await process_frame
	for id: StringName in [&"search_radar", &"missile_battery"]:
		_place_near_city(_defense(id), main.defenses.size())
	main.hud._on_start_pressed()
	main.camera_rig.focus_on(Vector3(600, 0, 0))
	for frame: int in 60:
		await process_frame
	var entry := _threat_entry(&"attack_uav")
	for index: int in KILLS:
		var threat := main.director.spawn_entry_at(entry, Vector3(600 + index * 20, 0, index * 20))
		var resolved := [false]
		threat.resolved.connect(func(_threat: ThreatUnit, _neutralized: bool, _reward: int) -> void: resolved[0] = true)
		var kill_ms := 0.0
		var started := Time.get_ticks_msec()
		while not resolved[0] and Time.get_ticks_msec() - started < 60000:
			kill_ms = await _frame_ms()
		var stalls: Array[String] = []
		for frame: int in FOLLOW_FRAMES:
			var ms := await _frame_ms()
			if ms > STALL_MS:
				stalls.append("%d:%.0f" % [frame, ms])
		print("FIRST_KILL_PROBE index=%d resolved=%s kill_frame_ms=%.0f later_stalls=%s" % [index, resolved[0], kill_ms, stalls])
	quit()

func _frame_ms() -> float:
	var started := Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - started) / 1000.0

func _defense(id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id == id:
			return definition
	push_error("missing defense %s" % id)
	return null

func _threat_entry(id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	push_error("missing threat %s" % id)
	return null

func _place_near_city(definition: DefenseDefinition, slot: int) -> void:
	var angle := 0.2 + slot * 0.5
	for step: int in 40:
		var distance := 220.0 + step * 12.0
		var position := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		if main.battlefield.placement_result(position, definition.placement_profile).valid:
			main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			return
	push_error("could not place %s" % definition.id)
