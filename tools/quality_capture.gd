extends SceneTree

const MAIN := preload("res://main/main.tscn")
const LASER := preload("res://effects/laser_pulse/laser_pulse.tscn")
var main: AirscainMain

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	AirscainApp.apply_global_font()
	AirscainMain.requested_seed = 73129
	main = MAIN.instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.hud.visible = false
	main.altitude_profile.visible = false
	main.camera_rig.set_process(false)
	main.camera_rig.camera.position = Vector3(90, 125, 155)
	main.camera_rig.camera.look_at(Vector3(0, 10, 0))
	await capture("streets")
	main.camera_rig.camera.position = Vector3(1050, 400, 1250)
	main.camera_rig.camera.look_at(Vector3(1350, 0, 1000))
	await capture("ocean")
	var center := Vector3(0, 0, 360)
	var showcase := Node3D.new()
	main.effects_parent.add_child(showcase)
	var definitions: Array[DefenseDefinition] = [main.scenario.available_defenses[1], main.scenario.available_defenses[3], main.scenario.available_defenses[2], main.scenario.available_defenses[5]]
	for index: int in definitions.size():
		var unit := definitions[index].scene.instantiate() as DefenseUnit
		showcase.add_child(unit)
		unit.setup(-100 - index, definitions[index])
		unit.position = center + Vector3((index - 1.5) * 26, 0, 0)
		unit.position.y = main.battlefield.terrain_height(unit.position.x, unit.position.z)
		unit.identity_marker.visible = false
		unit.status_marker.visible = false
	center.y = main.battlefield.terrain_height(center.x, center.z) + 6
	main.camera_rig.camera.position = center + Vector3(40, 38, -90)
	main.camera_rig.camera.look_at(center)
	await capture("installations")
	showcase.queue_free()
	await process_frame
	showcase = Node3D.new()
	main.effects_parent.add_child(showcase)
	for index: int in 2:
		var path := "res://enemy/attack_uav/attack_uav.tscn" if index == 0 else "res://enemy/strike_aircraft/strike_aircraft.tscn"
		var craft := (load(path) as PackedScene).instantiate() as Node3D
		showcase.add_child(craft)
		craft.position = center + Vector3((index - 0.5) * 26, 75, 0)
	main.camera_rig.camera.position = center + Vector3(28, 107, -56)
	main.camera_rig.camera.look_at(center + Vector3(0, 75, 0))
	await capture("airframes")
	showcase.queue_free()
	await process_frame
	var laser := LASER.instantiate() as LaserPulse
	main.effects_parent.add_child(laser)
	laser.lifetime = 2.0
	laser.setup(center + Vector3(-28, 0, 0), center + Vector3(25, 28, 0))
	laser.set_process(false)
	main.camera_rig.camera.position = center + Vector3(15, 43, -90)
	main.camera_rig.camera.look_at(center + Vector3(0, 12, 0))
	await capture("laser")
	laser.queue_free()
	var hpm := (load("res://defense/high_power_microwave/high_power_microwave.tscn") as PackedScene).instantiate() as HighPowerMicrowave
	main.effects_parent.add_child(hpm)
	hpm.position = center
	hpm.pulse_visual.global_position = center + Vector3(0, 23, 0)
	hpm.pulse_visual.play(22.0)
	hpm.pulse_visual._process(0.2)
	hpm.pulse_visual.set_process(false)
	await capture("field")
	hpm.queue_free()
	main.placement.select(main.scenario.available_defenses[1])
	main.placement.set_process(false)
	main.placement.preview.position = center
	main.placement.preview_material.albedo_color = Color(0.2, 0.9, 0.55, 0.48)
	main.camera_rig.camera.position = center + Vector3(24, 19, -42)
	main.camera_rig.camera.look_at(center + Vector3.UP * 5)
	await capture("placement")
	main.queue_free()
	await process_frame
	print("QUALITY_CAPTURE_OK installations airframes laser field")
	quit()

func capture(label: String) -> void:
	for frame: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("/tmp/airscain_quality_%s.png" % label)
	if error != OK:
		push_error("Capture failed: %s" % error_string(error))
		quit(1)
