extends SceneTree
## Captures sustained-operation phase briefings in a live window: the opening phase,
## a dense mid-game phase, the final phase without new assets and the Esc archive.
## Usage: godot --path . --script res://tools/briefing_capture.gd -- [--locale=en]

const APP_SCENE := preload("res://main/app.tscn")

var app: AirscainApp
var main: AirscainMain

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	var locale := "ko"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			locale = argument.trim_prefix("--locale=")
	PlayerSettings.instance().set_value("language", locale)
	PlayerSettings.instance().values.briefings = true
	app = APP_SCENE.instantiate() as AirscainApp
	root.add_child(app)
	while not app.combat_vfx_warmup_completed:
		await process_frame
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	main = app.gameplay
	while not main.combat_effect_pool.prepared:
		await process_frame
	await _wait_seconds(0.8)
	await _save_capture("/tmp/airscain_briefing_%s_phase1.png" % locale)
	main.briefing_panel.close()
	main.director.pressure_changed.emit(3)
	await _wait_seconds(0.8)
	await _save_capture("/tmp/airscain_briefing_%s_phase3.png" % locale)
	main.briefing_panel.deploy_button.pressed.emit()
	await _wait_seconds(0.5)
	await _save_capture("/tmp/airscain_briefing_%s_catalog.png" % locale)
	main.hud.set_catalog_expanded(false)
	main.director.pressure_changed.emit(11)
	await _wait_seconds(0.8)
	await _save_capture("/tmp/airscain_briefing_%s_phase7.png" % locale)
	main.briefing_panel.close()
	app.set_pause_menu(true)
	await _wait_seconds(0.4)
	await _save_capture("/tmp/airscain_briefing_%s_pause.png" % locale)
	app._on_pause_briefings_pressed()
	main.briefing_panel.show_page(3)
	await _wait_seconds(0.6)
	await _save_capture("/tmp/airscain_briefing_%s_archive.png" % locale)
	print("BRIEFING_CAPTURE_OK delivered=%d speed=%.1f" % [main.briefing_controller.delivered_ids.size(), main.session.simulation_speed])
	quit(0)

func _wait_seconds(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _save_capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save briefing capture: %s" % error_string(error))
