extends SceneTree

const MAIN := preload("res://main/main.tscn")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	AirscainMain.requested_seed = 73129
	var main := MAIN.instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.set_process(false)
	(main.get_node("UI") as CanvasLayer).visible = false
	main.camera_rig.set_process(false)
	if OS.get_cmdline_user_args().has("--repair-stages"):
		await _capture_repair_stages(main)
		return
	var index := 0
	for candidate: int in main.battlefield.city_buildings.size():
		if main.battlefield.city_buildings[candidate].basis.get_scale().y < main.battlefield.city_buildings[index].basis.get_scale().y:
			index = candidate
	var bounds := main.battlefield.city_building_bounds(index)
	var roof := bounds.get_center()
	roof.y = bounds.end.y
	var impact := main.battlefield.building_segment_impact(roof + Vector3.UP * 100, roof - Vector3.UP)
	main.objective.apply_building_impact(10, impact.position, impact.building_height)
	# Exercise the same preallocated emitter through repair and save restoration.
	var saved_sites := main.objective.capture_damage_smoke_state()
	main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	main.objective.restore_damage_smoke_state(saved_sites)
	main.objective.restore_integrity(main.objective.definition.maximum_integrity - 10)
	var effect := main.objective.damage_smoke_effects[0]
	main.camera_rig.camera.global_position = roof + Vector3(70, 65, 105)
	main.camera_rig.camera.look_at(roof + Vector3.UP * 16)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 7000:
		await process_frame
	effect.smoke.speed_scale = 0
	effect.fire.speed_scale = 0
	effect.smoke._sync_shadow_state()
	for frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var with_shadow := root.get_texture().get_image()
	with_shadow.save_png("/tmp/airscain_roof_smoke.png")
	effect.smoke.shadow_particles.visible = false
	for frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var without_shadow := root.get_texture().get_image()
	without_shadow.save_png("/tmp/airscain_roof_no_shadow.png")
	var changed := 0
	# This crop contains the terrain to the right of the source, not the plume,
	# flame or animated water. Freeze both emitters before the A/B comparison.
	for y: int in range(with_shadow.get_height() / 2, with_shadow.get_height() * 2 / 3):
		for x: int in range(with_shadow.get_width() * 3 / 5, with_shadow.get_width()):
			if with_shadow.get_pixel(x,y).get_luminance() + 0.025 < without_shadow.get_pixel(x,y).get_luminance():
				changed += 1
	print("ROOF_SMOKE impact=%s roof_y=%.2f source=%s seed=%d shadow_seed=%d shadow_pixels=%d" % [impact.position, roof.y, effect.smoke.global_position, effect.smoke.seed, effect.smoke.shadow_particles.seed, changed])
	main.queue_free()
	await process_frame
	quit(0 if changed > 1000 else 1)

func _capture_repair_stages(main: AirscainMain) -> void:
	for index: int in [0, 8, 16, 24]:
		var bounds := main.battlefield.city_building_bounds(index)
		var roof := bounds.get_center()
		roof.y = bounds.end.y
		main.objective.apply_building_impact(10, roof, bounds.size.y)
	main.camera_rig.camera.global_position = Vector3(350, 280, 430)
	main.camera_rig.camera.look_at(Vector3(0, 25, 0))
	await create_timer(5.0).timeout
	var ok := true
	for integrity: int in [60, 70, 80, 99, 100]:
		main.objective.restore_integrity(integrity)
		for frame: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/airscain_city_repair_%d.png" % integrity)
		var count := main.objective.damage_smoke_effects.size()
		ok = ok and count == ceili(float(100 - integrity) / 10.0)
		print("CITY_REPAIR integrity=%d smoke=%d pooled=%d" % [integrity, count, main.objective.prepared_smoke_effects.size()])
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
