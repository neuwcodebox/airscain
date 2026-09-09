extends SceneTree
## Silent event-window probe after the same global/world warmup used by play.

var main: AirscainMain
var spawned: Array[ExplosionEffect] = []

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	if not OS.get_cmdline_user_args().has("--fallback-font"):
		AirscainApp.apply_global_font()
	var start := Time.get_ticks_usec()
	var warmup := CombatVfxWarmup.new()
	root.add_child(warmup)
	await warmup.completed
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	main = preload("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	main.combat_audio.stop_all()
	main.ui_audio.stop_all()
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.camera_rig.set_process(false)
	print("HITCH_PREPARE ms=%.3f pool=%d" % [(Time.get_ticks_usec() - start) / 1000.0, main.combat_effect_pool.available.size()])
	if OS.get_cmdline_user_args().has("--city-only"):
		if OS.get_cmdline_user_args().has("--no-city-hud"):
			main.objective.integrity_changed.disconnect(main.hud._on_integrity_changed)
		if OS.get_cmdline_user_args().has("--no-city-windows"):
			main.objective.integrity_changed.disconnect(main.battlefield._sync_city_power)
		for repeat: int in 2:
			await sample_event("city_impact_%d" % repeat, func() -> void:
				main.objective.apply_building_impact(1, Vector3(0, 45, 0), 45))
			main.objective.restore_integrity(main.objective.definition.maximum_integrity)
		main.queue_free()
		await process_frame
		quit()
		return
	await sample_event("idle", func() -> void: pass)
	if not OS.get_cmdline_user_args().has("--spawn-only"):
		for count: int in [1, 16, 32]:
			for repeat: int in 2:
				await sample_event("explosions_%d_%d" % [count, repeat], func() -> void:
					for index: int in count:
						var point := Vector3((index % 8 - 3.5) * 22, 70, (index / 8 - 1.5) * 22)
						spawned.append(ExplosionEffect.spawn(main.effects_parent, point, Color.ORANGE, 12)))
				for effect: ExplosionEffect in spawned:
					effect._process(effect.duration)
				spawned.clear()
		for repeat: int in 2:
			await sample_event("city_impact_%d" % repeat, func() -> void:
				main.objective.apply_building_impact(1, Vector3(0, 45, 0), 45))
			assert(main.objective.current_integrity > 0, "Impact probe must not open the game-over UI")
			main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if OS.get_cmdline_user_args().has("--brief") and entry.threat_definition.id not in [&"attack_uav", &"strike_aircraft", &"radar_strike_aircraft"]:
			continue
		for repeat: int in 2:
			var units: Array[ThreatUnit] = []
			await sample_event("spawn_%s_%d" % [entry.threat_definition.id, repeat], func() -> void:
				var unit := main.director._spawn_entry(entry, 0.0, 0.0)
				unit.position = Vector3(3500, 80, 0)
				units.append(unit)
				# Exercise the transparent variant that first appears in the haze.
				for child: Node in unit.get_children():
					if child is DistantContactHaze:
						(child as DistantContactHaze).refresh()
						(child as DistantContactHaze).set_process(false)
				unit.position = Vector3(0, 80, 0))
			for unit: ThreatUnit in units:
				main.registry.remove(unit)
				unit.queue_free()
	await sample_event("city_defeat", func() -> void:
		main.objective.apply_building_impact(main.objective.current_integrity, Vector3(0, 45, 0), 45))
	root.get_texture().get_image().save_png("/tmp/airscain_hitch_check.png")
	main.queue_free()
	await process_frame
	quit()

func sample_event(label: String, action: Callable) -> void:
	for frame: int in 10:
		await process_frame
		await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	action.call()
	var cpu := Time.get_ticks_usec() - start
	var frames: Array[float] = []
	for frame: int in 12:
		await process_frame
		await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec() - start) / 1000.0)
		start = Time.get_ticks_usec()
	print("HITCH %s cpu_ms=%.3f first_ms=%.3f max_ms=%.3f frames=%s" % [label, cpu / 1000.0, frames[0], frames.max(), frames])
	if label == "city_impact_0":
		root.get_texture().get_image().save_png("/tmp/airscain_hitch_city.png")
