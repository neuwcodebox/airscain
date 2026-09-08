extends SceneTree
## Muted real-window diagnostic for sector search and shared coverage.

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	AirscainMain.requested_seed = 73129
	var main := preload("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	main.hud.hide()
	main.altitude_profile.hide()
	main.track_display.hide()
	main.camera_rig.set_process(false)
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2600.0
	camera.position = Vector3(0, 2600, 1)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.make_current()
	var entry: ThreatSpawnEntry
	for candidate: ThreatSpawnEntry in main.scenario.threat_entries:
		if candidate.threat_definition.mission_definition() != null and candidate.threat_definition.mission_definition().area_recon:
			entry = candidate
	var aircraft: Array[AttackUav] = []
	var trails: Array[PackedVector3Array] = []
	var displays: Array[MeshInstance3D] = []
	var visits: Array[int] = [0, 0, 0]
	var colors: Array[Color] = [Color.CYAN, Color.ORANGE, Color.MAGENTA]
	for index: int in 3:
		var angle := TAU * index / 3.0
		var unit := main.director._spawn_entry(entry, angle, 0.0) as AttackUav
		unit.global_position = Vector3(cos(angle) * 950.0, 220.0, sin(angle) * 950.0)
		aircraft.append(unit)
		trails.append(PackedVector3Array())
		var display := MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colors[index]
		display.material_override = material
		main.add_child(display)
		displays.append(display)
	for frame: int in 360:
		for step: int in 6:
			main.enemy_knowledge.gameplay_tick(0.1)
			for unit: AttackUav in aircraft:
				if is_instance_valid(unit):
					unit.gameplay_tick(0.1)
		for index: int in aircraft.size():
			if not is_instance_valid(aircraft[index]):
				continue
			visits[index] = aircraft[index].reconnaissance.completed_sectors
			trails[index].append(aircraft[index].global_position + Vector3.UP * 20.0)
			if trails[index].size() < 2:
				continue
			var mesh := ImmediateMesh.new()
			mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for point: Vector3 in trails[index]:
				mesh.surface_add_vertex(point)
			mesh.surface_end()
			displays[index].mesh = mesh
		await process_frame
		if frame in [99, 359]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/airscain_recon_search_%d.png" % frame)
			print("RECON_SEARCH time=", main.enemy_knowledge.simulation_time, " sectors=", main.enemy_knowledge.search.seen.size(), " reservations=", main.enemy_knowledge.search.assignments, " visited=", visits)
	quit()
