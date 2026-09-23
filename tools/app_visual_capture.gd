extends SceneTree

const APP_SCENE := preload("res://main/app.tscn")

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	# Diagnostic runs advance the simulation without modal phase briefings.
	PlayerSettings.instance().values.briefings = false
	_apply_requested_locale()
	var app: Node = APP_SCENE.instantiate()
	root.add_child(app)
	var backdrop := (app as AirscainApp).main_menu.get_node("Background")
	var demo := backdrop.get("demo") as AirscainMain
	for index: int in 30:
		await process_frame
	_save_capture("/tmp/airscain_main_menu_loading.png")
	while not (app as AirscainApp).combat_vfx_warmup_completed or not demo.combat_effect_pool.prepared:
		await process_frame
	if OS.get_cmdline_user_args().has("--demo-only"):
		var started := Time.get_ticks_msec()
		while demo.session.weapon_fire_count < 2 and Time.get_ticks_msec() - started < 60000:
			await process_frame
		_save_capture("/tmp/airscain_menu_live_defense.png")
		while demo.session.neutralized_count == 0 and Time.get_ticks_msec() - started < 60000:
			await process_frame
		_save_capture("/tmp/airscain_menu_intercept.png")
		print("MENU_DEMO_CAPTURE shots=%d neutralized=%d" % [demo.session.weapon_fire_count, demo.session.neutralized_count])
		var succeeded := demo.session.weapon_fire_count > 0 and demo.session.neutralized_count > 0
		app.queue_free()
		await process_frame
		quit(0 if succeeded else 1)
		return
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_main_menu.png")
	if OS.get_cmdline_user_args().has("--training-only"):
		(app as AirscainApp).call("_on_training_pressed")
		while not (app as AirscainApp).gameplay.combat_effect_pool.prepared:
			await process_frame
		for index: int in 20:
			await process_frame
		_save_capture("/tmp/airscain_training.png")
		print("TRAINING_CAPTURE_OK")
		quit(0)
		return
	((app as AirscainApp).main_menu.get_node("Panel/VBox/SustainedButton") as Button).pressed.emit()
	(app as AirscainApp).battlefield_selection.card_for_layout(&"valley_corridor").grab_focus()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	_save_capture("/tmp/airscain_battlefield_selection.png")
	(app as AirscainApp).battlefield_selection.card_for_layout(&"rugged_harbor").pressed.emit()
	while not (app as AirscainApp).gameplay.combat_effect_pool.prepared:
		await process_frame
	for index: int in 20:
		await process_frame
	var operation := (app as AirscainApp).gameplay
	assert(operation.session.phase == GameSession.Phase.RUNNING)
	assert(operation.registry.hostile_count() > 0)
	assert(operation.scenario.battlefield_layout().id == &"rugged_harbor")
	assert(not operation.hud.start_button.visible)
	_save_capture("/tmp/airscain_operation_started.png")
	print("OPERATION_STARTED time=%.2f hostiles=%d" % [operation.session.survival_time, operation.registry.hostile_count()])
	app.call("set_pause_menu", true)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_pause_menu.png")
	app.call("set_pause_menu", false)
	operation.session.end_game()
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_game_over.png")
	print("APP_VISUAL_CAPTURE_OK main_menu battlefield_selection gameplay pause_menu game_over")
	quit(0)

func _save_capture(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save app capture: %s" % error_string(error))
		quit(1)

func _apply_requested_locale() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			PlayerSettings.instance().set_value("language", argument.trim_prefix("--locale="))
