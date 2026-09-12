extends Node
## Export this scene as the temporary main scene to measure native/WebGL events.

var main: AirscainMain
var event_results: Array[Dictionary] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Missile hitch probe requires a rendered viewport")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	AirscainApp.apply_global_font()
	var started := Time.get_ticks_usec()
	var warmup := CombatVfxWarmup.new()
	add_child(warmup)
	await warmup.completed
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	main = preload("res://main/main.tscn").instantiate() as AirscainMain
	add_child(main)
	while not main.combat_effect_pool.prepared:
		await get_tree().process_frame
	if main.combat_effect_pool.available.size() != CombatEffectPool.CAPACITY:
		push_error("Warmup did not return every explosion slot")
		return
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.combat_audio.enabled = true
	main.ui_audio.enabled = false
	print("HITCH_PREPARE ms=%.3f" % ((Time.get_ticks_usec() - started) / 1000.0))
	await sample_missiles()
	await sample_secondary_effects()
	print("HITCH_RESULTS " + JSON.stringify(event_results))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.airscainHitchResults = " + JSON.stringify(event_results), true)
	print("HITCH_DONE missile")

func sample_event(label: String, action: Callable, frame_count: int = 12, settle_frames: int = 10) -> void:
	for frame: int in settle_frames:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	action.call()
	var cpu := Time.get_ticks_usec() - start
	var frames: Array[float] = []
	for frame: int in frame_count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec() - start) / 1000.0)
		start = Time.get_ticks_usec()
	event_results.append({"event": label, "cpu_ms": cpu / 1000.0, "frames_ms": frames})
	print("HITCH %s cpu_ms=%.3f first_ms=%.3f max_ms=%.3f frames=%s" % [label, cpu / 1000.0, frames[0], frames.max(), frames])

func sample_missiles() -> void:
	var definition := main.scenario.available_defenses[0] as MissileBatteryDefinition
	var battery := definition.scene.instantiate() as MissileBattery
	main.defense_parent.add_child(battery)
	battery.setup(9900, definition)
	battery.position = Vector3(0, 90, 0)
	battery.configure_combat(main.registry, main.projectile_parent)
	if not OS.get_cmdline_user_args().has("--no-audio"):
		main.combat_audio.enabled = true
		battery.projectile_launched.connect(main._on_projectile_launched_audio)
	var track := PlayerTrack.new()
	track.track_id = 9900
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = Vector3(250, 180, 0)
	await sample_event("missile_idle", func() -> void: pass)
	for repeat: int in 3:
		await sample_event("missile_launch_%d" % repeat, func() -> void:
			battery._fire_round(track, definition.munitions[0]))
		var interceptor: HomingInterceptor = battery.interceptors.back()
		var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
		await sample_event("missile_smoke_%d" % repeat, func() -> void:
			smoke.sample_world_segment(interceptor.global_position, interceptor.global_position + Vector3.RIGHT * 40))
		await sample_event("missile_end_%d" % repeat, func() -> void:
			interceptor.self_destruct())
		await sample_event("missile_decay_%d" % repeat, func() -> void: pass, 180, 0)
		battery.interceptors.clear()
	await sample_event("missile_idle_after", func() -> void: pass)

func sample_secondary_effects() -> void:
	for repeat: int in 2:
		for kind: String in ["miss", "laser", "flare", "chaff"]:
			var nodes: Array[Node3D] = []
			await sample_event("%s_%d" % [kind, repeat], func() -> void:
				var effect: Node3D
				match kind:
					"miss":
						effect = CombatVfxWarmup.MISS_SCENE.instantiate() as Node3D
						main.effects_parent.add_child(effect)
						effect.position = Vector3(0, 80, 0)
						effect.call("setup", Color.ORANGE, "표적 소실")
					"laser":
						var laser := CombatVfxWarmup.LASER_SCENE.instantiate() as LaserPulse
						main.effects_parent.add_child(laser)
						laser.setup(Vector3(0, 80, 0), Vector3(40, 80, 0))
						effect = laser
					_:
						effect = CombatVfxWarmup.COUNTERMEASURE_SCENE.instantiate() as Node3D
						main.effects_parent.add_child(effect)
						effect.position = Vector3(0, 80, 0)
						effect.call("setup", StringName(kind))
				nodes.append(effect))
			for effect: Node3D in nodes:
				if is_instance_valid(effect):
					effect.queue_free()
