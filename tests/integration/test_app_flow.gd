extends GutTest

const APP_SCENE := preload("res://main/app.tscn")

func test_main_menu_starts_modes_and_escape_menu_returns_home() -> void:
	var app: Node = add_child_autofree(APP_SCENE.instantiate())
	await get_tree().process_frame
	var main_menu := app.get("main_menu") as Control
	var pause_menu := app.get("pause_menu") as Control
	assert_true(main_menu.visible)
	assert_false(pause_menu.visible)
	assert_null(app.get("gameplay"))
	app.call("start_game", AirscainMain.GameMode.TRAINING)
	await get_tree().process_frame
	var gameplay := app.get("gameplay") as AirscainMain
	assert_not_null(gameplay)
	assert_eq(gameplay.game_mode, AirscainMain.GameMode.TRAINING)
	assert_false(main_menu.visible)
	assert_null(gameplay.hud.get_node_or_null("%ModeOption"))
	app.call("set_pause_menu", true)
	assert_true(pause_menu.visible)
	assert_eq(gameplay.session.simulation_speed, 0.0)
	assert_true((app.get("pause_save_button") as Button).disabled)
	app.call("set_pause_menu", false)
	assert_false(pause_menu.visible)
	assert_eq(gameplay.session.simulation_speed, 1.0)
	app.call("return_to_main_menu")
	assert_true(main_menu.visible)
	assert_null(app.get("gameplay"))
