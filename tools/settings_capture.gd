extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var app := load("res://main/app.tscn").instantiate() as AirscainApp
	root.add_child(app)
	while not app.combat_vfx_warmup_completed:
		await process_frame
	while not app.main_menu.get_node("Background").demo.combat_effect_pool.prepared:
		await process_frame
	await process_frame
	app.settings_menu.open()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_settings_audio.png")
	var tabs := app.settings_menu.find_children("*", "TabContainer", true, false)[0] as TabContainer
	for index: int in [1, 2]:
		tabs.current_tab = index
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/airscain_settings_tab%d.png" % index)
	tabs.current_tab = 0
	app.settings_menu.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_settings_main.png")
	app.start_game(AirscainMain.GameMode.SANDBOX)
	while not app.gameplay.combat_effect_pool.prepared:
		await process_frame
	await process_frame
	app.set_pause_menu(true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_settings_pause.png")
	app.settings_menu.open()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/airscain_settings_ingame.png")
	print("SETTINGS_CAPTURE_OK")
	quit()
