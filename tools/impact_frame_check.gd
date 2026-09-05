extends SceneTree
## Measures event CPU and real rendered frame latency; never a headless FPS claim.

const APP := preload("res://main/app.tscn")
var app: AirscainApp

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	app = APP.instantiate() as AirscainApp
	root.add_child(app)
	while not app.combat_vfx_warmup_completed:
		await process_frame
	app._create_gameplay(AirscainMain.GameMode.SANDBOX, 73129)
	var main := app.gameplay
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.hud.visible = false
	main.altitude_profile.visible = false
	main.camera_rig.set_process(false)
	main.camera_rig.camera.position = Vector3(150, 170, 220)
	main.camera_rig.camera.look_at(Vector3(0, 20, 0))
	for frame: int in 45:
		await process_frame
	var baseline: Array[float] = []
	for frame: int in 45:
		baseline.append(await frame_ms())
	baseline.sort()
	print("IMPACT_BASELINE median_ms=%.2f p95_ms=%.2f" % [baseline[22], baseline[42]])
	for index: int in 6:
		var point := Vector3(-35 + index * 12, 35, 30)
		var started := Time.get_ticks_usec()
		if not OS.get_cmdline_user_args().has("--explosion-only"):
			main.objective.apply_building_impact(1, point, 40)
		if not OS.get_cmdline_user_args().has("--smoke-only"):
			main._spawn_explosion(point, Color(1, 0.35, 0.06), 12)
		var cpu := (Time.get_ticks_usec() - started) / 1000.0
		var peak := 0.0
		for frame: int in 8:
			peak = maxf(peak, await frame_ms())
		print("IMPACT_EVENT index=%d event_cpu_ms=%.2f next8_peak_ms=%.2f" % [index, cpu, peak])
		for frame: int in 35:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_impact_frame_check.png")
	app.queue_free()
	await process_frame
	await process_frame
	quit()

func frame_ms() -> float:
	var started := Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - started) / 1000.0
