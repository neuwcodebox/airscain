extends GutTest

const APP_SCENE := preload("res://main/app.tscn")

func after_each() -> void:
	AirscainMain.requested_seed = -1
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED

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
	var first_seed := gameplay.scenario.world_seed
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
	await get_tree().process_frame
	app.call("start_game", AirscainMain.GameMode.SANDBOX)
	await get_tree().process_frame
	var next_gameplay := app.get("gameplay") as AirscainMain
	assert_not_null(next_gameplay)
	assert_ne(next_gameplay.scenario.world_seed, first_seed)

func test_game_over_restart_replaces_gameplay_without_showing_main_menu() -> void:
	var app: AirscainApp = add_child_autofree(APP_SCENE.instantiate()) as AirscainApp
	await get_tree().process_frame
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	await get_tree().process_frame
	var first_gameplay := app.gameplay
	var first_seed := first_gameplay.scenario.world_seed
	first_gameplay._on_restart_requested(true)
	await get_tree().process_frame
	assert_not_same(app.gameplay, first_gameplay)
	assert_eq(app.gameplay.scenario.world_seed, first_seed)
	assert_eq(app.gameplay.game_mode, AirscainMain.GameMode.SUSTAINED)
	assert_false(app.main_menu.visible)
	var same_seed_gameplay := app.gameplay
	same_seed_gameplay._on_restart_requested(false)
	await get_tree().process_frame
	assert_not_same(app.gameplay, same_seed_gameplay)
	assert_ne(app.gameplay.scenario.world_seed, first_seed)
	assert_false(app.main_menu.visible)

func test_save_and_load_controls_belong_to_main_and_pause_menus() -> void:
	var test_save_path := "user://app_menu_save_test_%d.json" % get_instance_id()
	_cleanup_save_path(test_save_path)
	var app := APP_SCENE.instantiate() as AirscainApp
	app.save_path = test_save_path
	add_child_autofree(app)
	await get_tree().process_frame
	assert_true(app.main_load_button.disabled)
	app.start_game(AirscainMain.GameMode.SUSTAINED)
	await get_tree().process_frame
	assert_null(app.gameplay.hud.get_node_or_null("%SaveButton"))
	assert_null(app.gameplay.hud.get_node_or_null("%LoadButton"))
	app.gameplay.session.budget = 317
	app.set_pause_menu(true)
	assert_false(app.pause_save_button.disabled)
	assert_true(app.pause_load_button.disabled)
	app.pause_save_button.pressed.emit()
	assert_eq(app.pause_feedback_label.text, "저장 완료")
	assert_false(app.pause_load_button.disabled)
	app.gameplay.session.budget = 999
	app.pause_load_button.pressed.emit()
	assert_eq(app.pause_feedback_label.text, "불러오기 완료")
	assert_eq(app.gameplay.session.budget, 317)
	assert_eq(app.gameplay.session.simulation_speed, 0.0)
	app.return_to_main_menu()
	assert_false(app.main_load_button.disabled)
	app.main_load_button.pressed.emit()
	await get_tree().process_frame
	assert_not_null(app.gameplay)
	assert_eq(app.gameplay.session.budget, 317)
	assert_false(app.main_menu.visible)
	_cleanup_save_path(test_save_path)

func _cleanup_save_path(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
