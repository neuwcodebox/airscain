extends SceneTree
## Renders a fixed gallery of world, model and effect views for visual review.
## Usage: godot --audio-driver Dummy --path . --script res://tools/visual_review.gd -- --out=/tmp/review [--seed=73129]

const MAIN_SCENE := preload("res://main/main.tscn")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")

var main: AirscainMain
var output_directory: String = "/tmp/airscain_review"

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	PlayerSettings.instance().values.briefings = false
	AirscainMain.requested_seed = 73129
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_directory = argument.trim_prefix("--out=")
		elif argument.begins_with("--seed="):
			AirscainMain.requested_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--layout="):
			AirscainMain.requested_layout_id = StringName(argument.trim_prefix("--layout="))
	DirAccess.make_dir_recursive_absolute(output_directory)
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
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tonemap="):
			environment.tonemap_mode = int(argument.trim_prefix("--tonemap=")) as Environment.ToneMapper
		elif argument.begins_with("--exposure="):
			environment.tonemap_exposure = float(argument.trim_prefix("--exposure="))
	main.hud.hide()
	main.altitude_profile.hide()
	main.tactical_screen_overlay.hide()
	_place_initial_assets()
	main.hud.show()
	main.tactical_screen_overlay.show()
	await _capture_rig("gameplay_hud", main.objective.global_position, 0.0, main.camera_rig.pitch_radians, main.camera_rig.zoom_distance * 0.6)
	main.hud.hide()
	main.tactical_screen_overlay.hide()
	for defense: DefenseUnit in main.defenses:
		defense.identity_marker.hide()
		defense.status_marker.hide()
	var city := main.objective.global_position
	await _capture_rig("gameplay", city, 0.0, main.camera_rig.pitch_radians, main.camera_rig.zoom_distance)
	await _capture_rig("overview", city, deg_to_rad(28.0), deg_to_rad(63.0), main.camera_rig.maximum_zoom * 0.78)
	await _capture_rig("city_close", city, deg_to_rad(32.0), deg_to_rad(38.0), 230.0)
	var hill := _find_hill(city)
	await _capture_look("terrain_low", hill + Vector3(-260.0, 90.0, 240.0), hill)
	await _capture_look("city_street", city + Vector3(-120.0, 32.0, 150.0), city + Vector3(0.0, 20.0, 0.0))
	await _capture_defense_lineup()
	await _capture_threat_lineup()
	await _capture_explosion()
	if main.harbor_port != null:
		var harbor := main.harbor_port.global_position
		await _capture_look("harbor", harbor + Vector3(140.0, 90.0, 160.0), harbor)
	for entry: Array in [["dusk", 17.6], ["night", 23.0]]:
		main.day_night.apply_time((float(entry[1]) - DayNightCycle.START_HOUR) / 24.0 * DayNightCycle.CYCLE_SECONDS, true)
		await _capture_rig(String(entry[0]), city, 0.0, main.camera_rig.pitch_radians, main.camera_rig.zoom_distance)
		await _capture_rig("%s_close" % entry[0], city, deg_to_rad(32.0), deg_to_rad(38.0), 260.0)
	print("VISUAL_REVIEW_OK %s" % output_directory)
	main.queue_free()
	await process_frame
	quit(0)

func _place_initial_assets() -> void:
	main.session.budget = 50000
	main._on_pressure_changed(30)
	var direction := 1.0
	for definition: DefenseDefinition in main.scenario.available_defenses:
		for offset: int in range(0, 240, 10):
			var position := Vector3(direction * (210.0 + float(offset)), 0.0, float(offset) * 0.4 - 40.0)
			position.y = main.battlefield.terrain_height(position.x, position.z)
			if main.battlefield.placement_result(position, definition.placement_profile).valid:
				main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
				break
		direction = -direction

func _find_hill(city: Vector3) -> Vector3:
	var best := city
	var best_height := -INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for index: int in 400:
		var x := city.x + rng.randf_range(-900.0, 900.0)
		var z := city.z + rng.randf_range(-900.0, 900.0)
		var height := main.battlefield.terrain_height(x, z)
		if height > best_height and Vector2(x - city.x, z - city.z).length() > 350.0:
			best_height = height
			best = Vector3(x, height, z)
	return best

func _flat_site(city: Vector3) -> Vector3:
	for radius: float in [420.0, 520.0, 620.0, 720.0]:
		for step: int in 24:
			var angle := TAU * float(step) / 24.0
			var point := city + Vector3(cos(angle), 0.0, sin(angle)) * radius
			point.y = main.battlefield.terrain_height(point.x, point.z)
			var flat := true
			for probe: Vector2 in [Vector2(-70, 0), Vector2(70, 0), Vector2(0, -30), Vector2(0, 30)]:
				if absf(main.battlefield.terrain_height(point.x + probe.x, point.z + probe.y) - point.y) > 4.0:
					flat = false
			if flat and point.y > 2.0:
				return point
	return city + Vector3(400.0, 0.0, 0.0)

func _capture_defense_lineup() -> void:
	var site := _flat_site(main.objective.global_position)
	var units: Array[DefenseUnit] = []
	var definitions := main.scenario.available_defenses
	for index: int in definitions.size():
		var unit := definitions[index].scene.instantiate() as DefenseUnit
		main.effects_parent.add_child(unit)
		unit.setup(-500 - index, definitions[index])
		var row := index / 6
		var column := index % 6
		var position := site + Vector3((float(column) - 2.5) * 24.0, 0.0, float(row) * 30.0 - 15.0)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		unit.global_position = position
		unit.rotation.y = -0.5
		unit.identity_marker.hide()
		unit.status_marker.hide()
		units.append(unit)
	await _capture_look("defenses", site + Vector3(70.0, 55.0, 110.0), site + Vector3(0.0, 4.0, 0.0))
	if OS.get_cmdline_user_args().has("--closeups"):
		for unit: DefenseUnit in units:
			var reach := maxf(12.0, unit.definition.placement_profile.footprint_radius * 2.2)
			await _capture_look("defense_%s" % unit.definition.id, unit.global_position + Vector3(reach * 0.9, reach * 0.55, reach * 1.1), unit.global_position + Vector3.UP * 3.0)
	await _capture_look("defenses_close", site + Vector3(-40.0, 14.0, 20.0), site + Vector3(-50.0, 4.0, -15.0))
	for unit: DefenseUnit in units:
		unit.queue_free()
	await process_frame

func _capture_threat_lineup() -> void:
	var site := _flat_site(main.objective.global_position) + Vector3(0.0, 70.0, 0.0)
	var scenes: Dictionary[PackedScene, ThreatDefinition] = {}
	for entry: ThreatSpawnEntry in main.scenario.threat_entries:
		if not scenes.has(entry.threat_definition.scene):
			scenes[entry.threat_definition.scene] = entry.threat_definition
	var units: Array[Node3D] = []
	var index := 0
	for scene: PackedScene in scenes:
		var definition := scenes[scene]
		var unit := scene.instantiate() as ThreatUnit
		main.effects_parent.add_child(unit)
		unit.setup(-900 - index, definition)
		unit.set_process(false)
		unit.set_physics_process(false)
		unit.global_position = site + Vector3((float(index) - float(scenes.size() - 1) * 0.5) * 22.0, 0.0, 0.0)
		unit.rotation = Vector3(0.0, 0.7, 0.0)
		units.append(unit)
		index += 1
	await _capture_look("threats", site + Vector3(20.0, 30.0, 85.0), site)
	await _capture_look("threats_below", site + Vector3(-10.0, -35.0, 60.0), site)
	for unit: Node3D in units:
		unit.queue_free()
	await process_frame

func _capture_explosion() -> void:
	var center := _flat_site(main.objective.global_position) + Vector3(0.0, 60.0, 0.0)
	main.camera_rig.camera.global_position = center + Vector3(0.0, 14.0, 70.0)
	main.camera_rig.camera.look_at(center, Vector3.UP)
	var explosion := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	main.effects_parent.add_child(explosion)
	explosion.global_position = center
	explosion.setup(Color(1.0, 0.32, 0.04), 10.0)
	for moment: float in [0.12, 0.45, 1.6]:
		var deadline := Time.get_ticks_msec() + int(moment * 1000.0)
		while Time.get_ticks_msec() < deadline:
			await process_frame
		await RenderingServer.frame_post_draw
		_save("explosion_%03d" % int(moment * 100.0))

func _capture_rig(label: String, focus: Vector3, yaw: float, pitch: float, zoom: float) -> void:
	main.camera_rig.focus_on(focus)
	main.camera_rig.yaw_radians = yaw
	main.camera_rig.pitch_radians = pitch
	main.camera_rig.zoom_distance = zoom
	main.camera_rig._update_camera()
	await _settle()
	_save(label)

func _capture_look(label: String, from: Vector3, target: Vector3) -> void:
	main.camera_rig.camera.global_position = from
	main.camera_rig.camera.look_at(target, Vector3.UP)
	await _settle()
	_save(label)

func _settle() -> void:
	for frame: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw

func _save(label: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [output_directory, label])
	if error != OK:
		push_error("Could not save review capture %s: %s" % [label, error_string(error)])
