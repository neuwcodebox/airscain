class_name AirscainApp
extends Node

const GAMEPLAY_SCENE := preload("res://main/main.tscn")
const GLOBAL_FONT_PATH := "res://ui/fonts/NanumSquareB.ttf"

var gameplay: AirscainMain
var previous_simulation_speed: float = 1.0
var save_path: String = SaveStore.DEFAULT_PATH
var prepared_combat_stream_count: int = 0
var combat_vfx_warmup_started: bool = false
var combat_vfx_warmup_completed: bool = false
var settings_menu: SettingsMenu

@onready var main_menu: Control = %MainMenu
@onready var pause_menu: Control = %PauseMenu
@onready var main_load_button: MenuListButton = %MainLoadButton
@onready var pause_save_button: MenuListButton = %PauseSaveButton
@onready var pause_load_button: MenuListButton = %PauseLoadButton
@onready var menu_feedback_label: Label = %MenuFeedbackLabel
@onready var menu_description_label: Label = %MenuDescriptionLabel
@onready var loading_status: Control = %LoadingStatus
@onready var loading_label: Label = %LoadingLabel
@onready var loading_bar: ProgressBar = %LoadingBar
@onready var pause_feedback_label: Label = %PauseFeedbackLabel
@onready var build_version_label: Label = %BuildVersionLabel
@onready var ui_audio: UiAudio = $UiAudio

func _enter_tree() -> void:
	apply_global_font()

static func apply_global_font() -> FontFile:
	var font := load(GLOBAL_FONT_PATH) as FontFile
	if font == null:
		push_error("Failed to load global UI font: %s" % GLOBAL_FONT_PATH)
		return null
	ThemeDB.get_default_theme().default_font = font
	ThemeDB.fallback_font = font
	return font

func _ready() -> void:
	build_version_label.text = BuildVersion.display_text()
	settings_menu = SettingsMenu.new()
	add_child(settings_menu)
	prepared_combat_stream_count = CombatAudio.prepare_samples()
	main_menu.visible = true
	pause_menu.visible = false
	ui_audio.connect_buttons(main_menu)
	ui_audio.connect_buttons(pause_menu)
	for node: Node in main_menu.find_children("*", "MenuListButton", true, false):
		(node as MenuListButton).focus_entered.connect(_show_menu_description.bind(node))
	_refresh_main_load_button()
	_set_preparation_ui(false)
	_reveal_main_menu()
	get_tree().process_frame.connect(_start_combat_vfx_warmup, CONNECT_ONE_SHOT)

func _show_menu_description(button: MenuListButton) -> void:
	menu_description_label.text = button.description

## Staggers the title and entries in, then selects the first available entry for keyboard play.
func _reveal_main_menu() -> void:
	var items: Array[Control] = []
	for node: Node in main_menu.get_node("Panel/VBox").get_children():
		var item := node as Control
		if item != null and item.visible:
			items.append(item)
	for index: int in items.size():
		var item := items[index]
		item.modulate.a = 0.0
		var tween := item.create_tween()
		tween.tween_interval(0.035 * index)
		tween.tween_property(item, "modulate:a", 1.0, 0.28)
	if combat_vfx_warmup_completed:
		_focus_first_available(main_menu.get_node("Panel/VBox"))

func _focus_first_available(container: Node) -> void:
	for node: Node in container.find_children("*", "MenuListButton", true, false):
		var button := node as MenuListButton
		if not button.disabled and button.is_visible_in_tree():
			button.grab_focus()
			return

func _start_combat_vfx_warmup() -> void:
	if combat_vfx_warmup_started:
		return
	combat_vfx_warmup_started = true
	var warmup := CombatVfxWarmup.new()
	warmup.progress_changed.connect(func(fraction: float) -> void:
		loading_bar.value = fraction
		loading_label.text = "로딩 중  %d%%" % roundi(fraction * 100.0))
	warmup.completed.connect(_on_combat_vfx_warmup_completed)
	add_child(warmup)

func _on_combat_vfx_warmup_completed() -> void:
	combat_vfx_warmup_completed = true
	_set_preparation_ui(true)
	loading_bar.value = 1.0
	var tween := loading_status.create_tween()
	tween.tween_property(loading_status, "modulate:a", 0.0, 0.4)
	tween.tween_callback(loading_status.hide)
	if main_menu.visible:
		_focus_first_available(main_menu.get_node("Panel/VBox"))

func _set_preparation_ui(ready: bool) -> void:
	for path: String in ["Panel/VBox/SustainedButton", "Panel/VBox/TrainingButton", "Panel/VBox/SandboxButton"]:
		(main_menu.get_node(path) as MenuListButton).set_available(ready)
	main_load_button.set_available(ready and _has_save_candidate())

func _input(event: InputEvent) -> void:
	if settings_menu != null and settings_menu.visible and event.is_action_pressed("ui_cancel"):
		settings_menu.close()
		get_viewport().set_input_as_handled()

func _on_settings_pressed() -> void:
	settings_menu.open()

func _unhandled_input(event: InputEvent) -> void:
	if gameplay != null and gameplay.session.phase != GameSession.Phase.GAME_OVER and event.is_action_pressed("ui_cancel"):
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

func _create_gameplay(mode: AirscainMain.GameMode, world_seed: int, auto_start: bool = true) -> void:
	AirscainMain.requested_mode = mode
	AirscainMain.requested_seed = world_seed
	gameplay = GAMEPLAY_SCENE.instantiate() as AirscainMain
	gameplay.auto_start_sustained = auto_start
	add_child(gameplay)
	gameplay.save_path = save_path
	gameplay.restart_game_requested.connect(restart_game)
	gameplay.main_menu_requested.connect(return_to_main_menu)
	main_menu.visible = false
	pause_menu.visible = false

func set_pause_menu(open: bool) -> void:
	if gameplay == null:
		return
	if open and gameplay.session.phase == GameSession.Phase.GAME_OVER:
		pause_menu.visible = false
		return
	pause_menu.visible = open
	gameplay.camera_rig.input_blocked = open
	if open:
		previous_simulation_speed = gameplay.session.simulation_speed
		gameplay.session.set_simulation_speed(0.0)
		pause_save_button.set_available(gameplay.game_mode == AirscainMain.GameMode.SUSTAINED)
		pause_load_button.set_available(gameplay.game_mode == AirscainMain.GameMode.SUSTAINED and _has_save_candidate())
		pause_feedback_label.text = ""
		_focus_first_available(pause_menu)
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
	_reveal_main_menu()

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
		_show_pause_persistence_result(PersistenceFeedback.Action.SAVE, error)
		pause_load_button.set_available(gameplay.game_mode == AirscainMain.GameMode.SUSTAINED and _has_save_candidate())

func _on_pause_load_pressed() -> void:
	if gameplay == null:
		return
	var error := gameplay.load_operation()
	if error.is_empty():
		previous_simulation_speed = gameplay.session.simulation_speed
		gameplay.session.set_simulation_speed(0.0)
	_show_pause_persistence_result(PersistenceFeedback.Action.LOAD, error)

func _on_main_load_pressed() -> void:
	var candidates: Array[Dictionary] = [SaveStore.read(save_path), SaveStore.read_backup(save_path)]
	var errors: Array[String] = []
	for candidate_index: int in candidates.size():
		var result: Dictionary = candidates[candidate_index]
		var error := String(result.error)
		if not error.is_empty():
			errors.append(error)
			continue
		var document: Dictionary = result.document
		var world_seed := int(document.payload.scenario.world_seed)
		_create_gameplay(AirscainMain.GameMode.SUSTAINED, world_seed, false)
		while not gameplay.combat_effect_pool.prepared:
			await get_tree().process_frame
		error = gameplay.restore_from_document(document)
		if error.is_empty():
			if candidate_index == 1:
				gameplay.record_backup_recovery()
			gameplay.hud.set_feedback(gameplay.persistence_success_message(PersistenceFeedback.Action.LOAD))
			ui_audio.play_event(UiAudio.ACTION_COMPLETE)
			return
		errors.append(error)
		var failed_gameplay := gameplay
		gameplay = null
		failed_gameplay.queue_free()
		await get_tree().process_frame
	main_menu.visible = true
	var primary_error := errors[0] if not errors.is_empty() else SaveStore.ERROR_MISSING
	var backup_error := errors[1] if errors.size() > 1 else SaveStore.ERROR_MISSING
	var diagnostic := SaveStore.combined_read_error(primary_error, backup_error)
	_report_persistence_failure(PersistenceFeedback.Action.LOAD, diagnostic)
	menu_feedback_label.text = PersistenceFeedback.failure_message(PersistenceFeedback.Action.LOAD, diagnostic)
	ui_audio.play_event(UiAudio.ACTION_REJECTED)
	_refresh_main_load_button()

func _show_pause_persistence_result(action: PersistenceFeedback.Action, error: String) -> void:
	if error.is_empty():
		pause_feedback_label.text = gameplay.persistence_success_message(action)
		ui_audio.play_event(UiAudio.ACTION_COMPLETE)
		return
	_report_persistence_failure(action, error)
	pause_feedback_label.text = PersistenceFeedback.failure_message(action, error, true)
	ui_audio.play_event(UiAudio.ACTION_REJECTED)

func _report_persistence_failure(action: PersistenceFeedback.Action, diagnostic: String) -> void:
	push_warning("%s 실패: %s" % [PersistenceFeedback.action_name(action), diagnostic])

func _refresh_main_load_button() -> void:
	main_load_button.set_available(_has_save_candidate())

func _has_save_candidate() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")

func _on_main_menu_pressed() -> void:
	return_to_main_menu()

func _on_quit_pressed() -> void:
	get_tree().quit()
