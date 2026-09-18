extends SceneTree
## Captures the tactical HUD in a live sandbox: asset selection, track selection,
## purchase catalog, altitude profile and the game-over result.

const APP_SCENE := preload("res://main/app.tscn")

var app: AirscainApp
var main: AirscainMain

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	app = APP_SCENE.instantiate() as AirscainApp
	root.add_child(app)
	while not app.combat_vfx_warmup_completed:
		await process_frame
	app.start_game(AirscainMain.GameMode.SANDBOX)
	main = app.gameplay
	while not main.combat_effect_pool.prepared:
		await process_frame
	var battery: DefenseUnit = null
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if String(definition.id).contains("radar") or definition.id in [&"missile_battery", &"close_in_gun"]:
			var unit := _place_near_city(definition, main.defenses.size())
			if definition.id == &"missile_battery":
				battery = unit
	main.hud._on_start_pressed()
	var threats := main._sandbox_threat_definitions()
	for index: int in 3:
		main._on_sandbox_threat_placement_requested(threats[0], Vector3(520.0 + index * 40.0, 0.0, -380.0 + index * 30.0))
	await _wait_seconds(4.0)
	main._on_asset_selected(battery)
	await _wait_seconds(0.4)
	await _save_capture("/tmp/airscain_hud_asset.png")
	var tracks := main.player_knowledge.get_active_tracks()
	if not tracks.is_empty():
		main._on_world_selected(tracks[0].estimated_position)
		await _wait_seconds(0.4)
		await _save_capture("/tmp/airscain_hud_track.png")
	main._clear_selection()
	main.hud.set_catalog_expanded(true)
	await _wait_seconds(0.3)
	await _save_capture("/tmp/airscain_hud_catalog.png")
	main.hud.set_catalog_expanded(false)
	main.session.end_game()
	await _wait_seconds(0.4)
	await _save_capture("/tmp/airscain_hud_game_over.png")
	print("HUD_VISUAL_CAPTURE_OK tracks=%d" % tracks.size())
	quit(0)

func _place_near_city(definition: DefenseDefinition, slot: int) -> DefenseUnit:
	var angle := 0.6 + slot * 0.9
	for step: int in 30:
		var distance := 220.0 + step * 12.0
		var position := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		position.y = main.battlefield.terrain_height(position.x, position.z)
		if main.battlefield.placement_result(position, definition.placement_profile).valid:
			main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			return main.defenses.back() as DefenseUnit
	return null

func _wait_seconds(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _save_capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save HUD capture: %s" % error_string(error))
