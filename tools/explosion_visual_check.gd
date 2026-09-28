extends SceneTree
## Compatibility rendering check: day/night, air/ground, frame sequence and light budget.
## Run with a real OpenGL context: godot --audio-driver Dummy --path . --script res://tools/explosion_visual_check.gd -- --out=/tmp/explosion-review

const MAIN_SCENE := preload("res://main/main.tscn")
var output_directory := "/tmp/explosion-review"
var main: AirscainMain

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_directory = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output_directory)
	PlayerSettings.instance().values.briefings = false
	AirscainMain.requested_seed = 73129
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	main.combat_audio.stop_all()
	main.ui_audio.stop_all()
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.hud.hide()
	main.altitude_profile.hide()
	main.tactical_screen_overlay.hide()
	var center := _visible_site()
	print("EXPLOSION_VISUAL_SITE ", center)
	var camera := main.camera_rig.camera
	camera.global_position = center + Vector3(29.0, 52.0, 97.0)
	camera.look_at(center + Vector3.UP * 15.0, Vector3.UP)
	for period: String in ["day", "night"]:
		var hour := 9.0 if period == "day" else 0.0
		main.day_night.apply_time((hour - DayNightCycle.START_HOUR) / 24.0 * DayNightCycle.CYCLE_SECONDS, true)
		await _settle()
		for profile: String in ["air", "ground"]:
			var position := center + (Vector3.UP * 32.0 if profile == "air" else Vector3.ZERO)
			var effect := ExplosionEffect.spawn(main.effects_parent, position, Color("ff9b48"), 12.0, profile == "ground", Vector3(15.0, 0.0, 4.0))
			for sample: int in [40, 120, 450, 1250]:
				while effect.elapsed < float(sample) / 1000.0:
					await process_frame
				await RenderingServer.frame_post_draw
				_save("%s_%s_%04d" % [period, profile, sample])
			effect.deactivate()
			await _settle()
	# Warm the camera before measuring, then record an idle/multiple-impact pair.
	main.day_night.apply_time((0.0 - DayNightCycle.START_HOUR) / 24.0 * DayNightCycle.CYCLE_SECONDS, true)
	await _settle()
	var idle := await _frame_ms()
	var effects: Array[ExplosionEffect] = []
	for index: int in 8:
		var point := center + Vector3(float(index % 4) * 20.0 - 30.0, 18.0, float(index / 4) * 22.0)
		effects.append(ExplosionEffect.spawn(main.effects_parent, point, Color("ff9b48"), 12.0))
	var active_lights := 0
	for effect: ExplosionEffect in effects:
		if effect.blast_light.visible:
			active_lights += 1
	await RenderingServer.frame_post_draw
	_save("night_eight_flash")
	var peak := 0.0
	for index: int in 10:
		peak = maxf(peak, await _frame_ms())
	_save("night_eight_explosions")
	print("EXPLOSION_VISUAL_CHECK idle_ms=%.2f impact_peak_ms=%.2f lights=%d draws=%d" % [idle, peak, active_lights, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if active_lights > ExplosionEffect.MAX_LIGHTS:
		push_error("Explosion light budget exceeded")
		quit(1)
		return
	main.queue_free()
	await process_frame
	print("EXPLOSION_VISUAL_CHECK_OK %s" % output_directory)
	quit(0)

func _frame_ms() -> float:
	var start := Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - start) / 1000.0

func _settle() -> void:
	for index: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw

func _save(label: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [output_directory, label])
	if error != OK:
		push_error("Explosion capture failed %s: %s" % [label, error_string(error)])

func _visible_site() -> Vector3:
	var city := main.objective.global_position
	var camera_offset := Vector3(29.0, 52.0, 97.0)
	for radius: float in [85.0, 120.0, 165.0, 210.0, 270.0]:
		for index: int in 24:
			var angle := TAU * float(index) / 24.0
			var point := city + Vector3(cos(angle), 0.0, sin(angle)) * radius
			point.y = main.battlefield.terrain_height(point.x, point.z) + 2.0
			if not main.battlefield.building_segment_impact(point, point + Vector3.UP * 30.0).is_empty():
				continue
			if not main.battlefield.building_segment_impact(point + camera_offset, point + Vector3.UP * 12.0).is_empty():
				continue
			return point
	push_error("No unoccluded city site for explosion review")
	return city + Vector3.UP * 2.0
