extends SceneTree

const APP_SCENE := preload("res://main/app.tscn")

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	var app: Node = APP_SCENE.instantiate()
	root.add_child(app)
	var backdrop := (app as AirscainApp).main_menu.get_node("Background")
	var demo := backdrop.get("demo") as AirscainMain
	while not (app as AirscainApp).combat_vfx_warmup_completed or not demo.combat_effect_pool.prepared:
		await process_frame
	if OS.get_cmdline_user_args().has("--demo-only"):
		var started := Time.get_ticks_msec()
		while demo.session.weapon_fire_count < 2 and Time.get_ticks_msec() - started < 60000:
			await process_frame
		_save_capture("/tmp/airscain_menu_live_defense.png")
		print("MENU_DEMO_CAPTURE shots=%d neutralized=%d" % [demo.session.weapon_fire_count, demo.session.neutralized_count])
		var succeeded := demo.session.weapon_fire_count > 0
		app.queue_free()
		await process_frame
		quit(0 if succeeded else 1)
		return
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_main_menu.png")
	app.call("start_game", AirscainMain.GameMode.SUSTAINED)
	while not (app as AirscainApp).gameplay.combat_effect_pool.prepared:
		await process_frame
	for index: int in 20:
		await process_frame
	app.call("set_pause_menu", true)
	for index: int in 5:
		await process_frame
	_save_capture("/tmp/airscain_pause_menu.png")
	print("APP_VISUAL_CAPTURE_OK main_menu gameplay pause_menu")
	quit(0)

func _save_capture(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save app capture: %s" % error_string(error))
		quit(1)
