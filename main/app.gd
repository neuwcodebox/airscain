class_name AirscainApp
extends Node

const GAMEPLAY_SCENE := preload("res://main/main.tscn")

var gameplay: AirscainMain
var previous_simulation_speed: float = 1.0
var save_path: String = SaveStore.DEFAULT_PATH

@onready var main_menu: Control = %MainMenu
@onready var pause_menu: Control = %PauseMenu
@onready var main_load_button: Button = %MainLoadButton
@onready var pause_save_button: Button = %PauseSaveButton
@onready var pause_load_button: Button = %PauseLoadButton
@onready var menu_feedback_label: Label = %MenuFeedbackLabel
@onready var pause_feedback_label: Label = %PauseFeedbackLabel

func _ready() -> void:
	main_menu.visible = true
	pause_menu.visible = false
	_refresh_main_load_button()

func _unhandled_input(event: InputEvent) -> void:
	if gameplay != null and event.is_action_pressed("ui_cancel"):
		set_pause_menu(not pause_menu.visible)
		get_viewport().set_input_as_handled()

func start_game(mode: AirscainMain.GameMode) -> void:
	if gameplay != null:
		return
	_create_gameplay(mode, AirscainMain.generate_world_seed())

func restart_game(mode: AirscainMain.GameMode, world_seed: int) -> void:
	if gameplay != null:
		var previous_gameplay := gameplay
		gameplay = null
		remove_child(previous_gameplay)
		previous_gameplay.queue_free()
	_create_gameplay(mode, world_seed)

func _create_gameplay(mode: AirscainMain.GameMode, world_seed: int) -> void:
	AirscainMain.requested_mode = mode
	AirscainMain.requested_seed = world_seed
	gameplay = GAMEPLAY_SCENE.instantiate() as AirscainMain
	add_child(gameplay)
	gameplay.save_path = save_path
	gameplay.restart_game_requested.connect(restart_game)
	main_menu.visible = false
	pause_menu.visible = false

func set_pause_menu(open: bool) -> void:
	if gameplay == null:
		return
	pause_menu.visible = open
	if open:
		previous_simulation_speed = gameplay.session.simulation_speed
		gameplay.session.set_simulation_speed(0.0)
		pause_save_button.disabled = gameplay.game_mode != AirscainMain.GameMode.SUSTAINED
		pause_load_button.disabled = gameplay.game_mode != AirscainMain.GameMode.SUSTAINED or not FileAccess.file_exists(save_path)
		pause_feedback_label.text = ""
	else:
		gameplay.session.set_simulation_speed(previous_simulation_speed)

func return_to_main_menu() -> void:
	if gameplay != null:
		gameplay.queue_free()
		gameplay = null
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	pause_menu.visible = false
	main_menu.visible = true
	_refresh_main_load_button()

func _on_sustained_pressed() -> void:
	start_game(AirscainMain.GameMode.SUSTAINED)

func _on_training_pressed() -> void:
	start_game(AirscainMain.GameMode.TRAINING)

func _on_sandbox_pressed() -> void:
	start_game(AirscainMain.GameMode.SANDBOX)

func _on_resume_pressed() -> void:
	set_pause_menu(false)

func _on_pause_save_pressed() -> void:
	if gameplay != null:
		gameplay.session.set_simulation_speed(previous_simulation_speed)
		var error := gameplay.save_operation()
		gameplay.session.set_simulation_speed(0.0)
		pause_feedback_label.text = "저장 완료" if error.is_empty() else "저장 실패 · %s" % error
		pause_load_button.disabled = gameplay.game_mode != AirscainMain.GameMode.SUSTAINED or not FileAccess.file_exists(save_path)

func _on_pause_load_pressed() -> void:
	if gameplay == null:
		return
	var error := gameplay.load_operation()
	if error.is_empty():
		previous_simulation_speed = gameplay.session.simulation_speed
		gameplay.session.set_simulation_speed(0.0)
	pause_feedback_label.text = "불러오기 완료" if error.is_empty() else "불러오기 실패 · %s" % error

func _on_main_load_pressed() -> void:
	var result := SaveStore.read(save_path)
	var error: String = result.error
	if not error.is_empty():
		menu_feedback_label.text = "불러오기 실패 · %s" % error
		_refresh_main_load_button()
		return
	var document: Dictionary = result.document
	var world_seed := int(document.payload.scenario.world_seed)
	_create_gameplay(AirscainMain.GameMode.SUSTAINED, world_seed)
	error = gameplay.restore_from_document(document)
	if error.is_empty():
		gameplay.hud.set_feedback("불러오기 완료")
		return
	var failed_gameplay := gameplay
	gameplay = null
	remove_child(failed_gameplay)
	failed_gameplay.queue_free()
	main_menu.visible = true
	menu_feedback_label.text = "불러오기 실패 · %s" % error

func _refresh_main_load_button() -> void:
	main_load_button.disabled = not FileAccess.file_exists(save_path)

func _on_main_menu_pressed() -> void:
	return_to_main_menu()

func _on_quit_pressed() -> void:
	get_tree().quit()
