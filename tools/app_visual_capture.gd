extends SceneTree

const APP_SCENE := preload("res://main/app.tscn")

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	var app: Node = APP_SCENE.instantiate()
	root.add_child(app)
	for index: int in 10:
		await process_frame
	_save_capture("/tmp/airscain_main_menu.png")
	app.call("start_game", AirscainMain.GameMode.SUSTAINED)
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
