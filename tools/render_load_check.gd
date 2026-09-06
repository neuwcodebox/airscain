extends SceneTree
## Stationary, fixed-seed rendering fixture; no gameplay or audio benchmark.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 600, 900)
	camera.look_at(Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("577587")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("80909a")
	environment.environment.ambient_light_energy = 0.5
	world.add_child(environment)
	var definitions: Array[ThreatDefinition] = [preload("res://enemy/attack_uav/attack_uav.tres"), preload("res://enemy/strike_aircraft/strike_aircraft.tres")]
	var first: ThreatUnit
	for index: int in 192:
		var definition := definitions[index % 2]
		var unit := definition.scene.instantiate() as ThreatUnit
		world.add_child(unit)
		unit.setup(index + 1, definition)
		if first == null:
			first = unit
		unit.position = Vector3((index % 16 - 7.5) * 40, 0, (index / 16 - 5.5) * 45)
		for node: Node in unit.find_children("*", "GPUParticles3D", true, false):
			(node as GPUParticles3D).hide()
		for node: Node in unit.find_children("*", "Light3D", true, false):
			(node as Light3D).hide()
	var samples: Array[int] = []
	for frame: int in 140:
		var start := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if frame >= 40:
			samples.append(Time.get_ticks_usec() - start)
	samples.sort()
	var total := 0
	for value: int in samples:
		total += value
	print("RENDER_LOAD aircraft=192 avg_ms=%.3f p95_ms=%.3f draws=%d primitives=%d" % [float(total) / samples.size() / 1000, samples[int(samples.size() * 0.95)] / 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	root.get_texture().get_image().save_png("/tmp/airscain_aircraft_load.png")
	# Separate close-up after timing so inspection cannot affect the benchmark.
	if first != null:
		camera.position = first.position + Vector3(30, 22, 35)
		camera.look_at(first.position)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/airscain_aircraft_closeup.png")
	world.free()
	quit()
