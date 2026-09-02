class_name AirscainApp
extends Node

const GAMEPLAY_SCENE := preload("res://main/main.tscn")

var gameplay: AirscainMain
var previous_simulation_speed: float = 1.0

@onready var main_menu: Control = %MainMenu
@onready var pause_menu: Control = %PauseMenu
@onready var pause_save_button: Button = %PauseSaveButton

func _ready() -> void:
	main_menu.visible = true
	pause_menu.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if gameplay != null and event.is_action_pressed("ui_cancel"):
		set_pause_menu(not pause_menu.visible)
		get_viewport().set_input_as_handled()

func start_game(mode: AirscainMain.GameMode) -> void:
	if gameplay != null:
		return
	AirscainMain.requested_mode = mode
	gameplay = GAMEPLAY_SCENE.instantiate() as AirscainMain
	add_child(gameplay)
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
	else:
		gameplay.session.set_simulation_speed(previous_simulation_speed)

func return_to_main_menu() -> void:
	if gameplay != null:
		gameplay.queue_free()
		gameplay = null
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	pause_menu.visible = false
	main_menu.visible = true

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
		gameplay._on_save_requested()

func _on_main_menu_pressed() -> void:
	return_to_main_menu()

func _on_quit_pressed() -> void:
	get_tree().quit()
