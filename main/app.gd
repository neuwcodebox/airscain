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
@onready var main_load_button: Button = %MainLoadButton
@onready var pause_save_button: Button = %PauseSaveButton
@onready var pause_load_button: Button = %PauseLoadButton
@onready var menu_feedback_label: Label = %MenuFeedbackLabel
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
	_style_menu_buttons()
	_refresh_main_load_button()
	_set_preparation_ui(false)
	get_tree().process_frame.connect(_start_combat_vfx_warmup, CONNECT_ONE_SHOT)

func _style_menu_buttons() -> void:
	for menu: Control in [main_menu, pause_menu]:
		for node: Node in menu.find_children("*", "Button"):
			var button := node as Button
			for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.08, 0.14, 0.16, 0.9)
				style.border_color = Color("3b6668")
				style.border_width_bottom = 1
				style.content_margin_left = 22
				style.content_margin_right = 22
				if state in ["hover", "focus"]:
					style.bg_color = Color("254b50")
					style.border_color = Color("a8d7c3")
					style.border_width_left = 3
				elif state == "pressed":
					style.bg_color = Color("34625f")
				elif state == "disabled":
					style.bg_color = Color(0.05, 0.09, 0.10, 0.7)
				if button.name == "SustainedButton" and state == "normal":
					style.bg_color = Color("32645e")
					style.border_color = Color("8fb6a0")
				button.add_theme_stylebox_override(state, style)
			button.add_theme_color_override("font_color", Color("e0e8dd"))
			if menu == main_menu:
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _start_combat_vfx_warmup() -> void:
	if combat_vfx_warmup_started:
		return
	combat_vfx_warmup_started = true
	var warmup := CombatVfxWarmup.new()
	warmup.progress_changed.connect(func(fraction: float) -> void: menu_feedback_label.text = "로딩 중 · %d%%" % roundi(fraction * 100.0))
	warmup.completed.connect(_on_combat_vfx_warmup_completed)
	add_child(warmup)

func _on_combat_vfx_warmup_completed() -> void:
	combat_vfx_warmup_completed = true
	_set_preparation_ui(true)
	menu_feedback_label.text = ""

func _set_preparation_ui(ready: bool) -> void:
	for path: String in ["Panel/VBox/SustainedButton", "Panel/VBox/TrainingButton", "Panel/VBox/SandboxButton"]:
		(main_menu.get_node(path) as Button).disabled = not ready
	main_load_button.disabled = not ready or not _has_save_candidate()
	if not ready:
		menu_feedback_label.text = "로딩 중…"

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
		pause_save_button.disabled = gameplay.game_mode != AirscainMain.GameMode.SUSTAINED
		pause_load_button.disabled = gameplay.game_mode != AirscainMain.GameMode.SUSTAINED or not _has_save_candidate()
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
		pause_feedback_label.text = gameplay.persistence_success_message("저장") if error.is_empty() else "저장 실패 · %s" % error
		ui_audio.play_event(UiAudio.ACTION_COMPLETE if error.is_empty() else UiAudio.ACTION_REJECTED)
		pause_load_button.disabled = gameplay.game_mode != AirscainMain.GameMode.SUSTAINED or not _has_save_candidate()

func _on_pause_load_pressed() -> void:
	if gameplay == null:
		return
	var error := gameplay.load_operation()
	if error.is_empty():
		previous_simulation_speed = gameplay.session.simulation_speed
		gameplay.session.set_simulation_speed(0.0)
	pause_feedback_label.text = gameplay.persistence_success_message("불러오기") if error.is_empty() else "불러오기 실패 · %s" % error
	ui_audio.play_event(UiAudio.ACTION_COMPLETE if error.is_empty() else UiAudio.ACTION_REJECTED)

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
				gameplay.last_persistence_repairs.push_front("기본 저장 대신 마지막 정상 백업을 사용했습니다")
				push_warning("불러오기 자동 복구: 기본 저장 대신 마지막 정상 백업을 사용했습니다")
			gameplay.hud.set_feedback(gameplay.persistence_success_message("불러오기"))
			ui_audio.play_event(UiAudio.ACTION_COMPLETE)
			return
		errors.append(error)
		var failed_gameplay := gameplay
		gameplay = null
		failed_gameplay.queue_free()
		await get_tree().process_frame
	main_menu.visible = true
	var primary_error := errors[0] if not errors.is_empty() else "저장 파일이 없습니다"
	var backup_error := errors[1] if errors.size() > 1 else "저장 파일이 없습니다"
	menu_feedback_label.text = "불러오기 실패 · %s" % primary_error if backup_error == "저장 파일이 없습니다" else "불러오기 실패 · %s · 백업: %s" % [primary_error, backup_error]
	ui_audio.play_event(UiAudio.ACTION_REJECTED)
	_refresh_main_load_button()

func _refresh_main_load_button() -> void:
	main_load_button.disabled = not _has_save_candidate()

func _has_save_candidate() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")

func _on_main_menu_pressed() -> void:
	return_to_main_menu()

func _on_quit_pressed() -> void:
	get_tree().quit()
