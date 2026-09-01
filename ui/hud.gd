class_name Hud
extends Control

signal defense_selected(definition: DefenseDefinition)
signal start_requested
signal speed_requested(speed: float)
signal restart_requested(same_seed: bool)
signal c2_overlay_requested

var session: GameSession
var objective: ProtectedObjective
var pressure_level: int = 1
var defense_definitions: Array[DefenseDefinition] = []
var defense_buttons: Array[Button] = []

@onready var budget_label: Label = %BudgetLabel
@onready var integrity_label: Label = %IntegrityLabel
@onready var time_label: Label = %TimeLabel
@onready var pressure_label: Label = %PressureLabel
@onready var speed_label: Label = %SpeedLabel
@onready var defense_list: VBoxContainer = %DefenseList
@onready var start_button: Button = %StartButton
@onready var feedback_label: Label = %FeedbackLabel
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var final_stats: Label = %FinalStats
@onready var selected_asset_panel: PanelContainer = %SelectedAssetPanel
@onready var selected_asset_label: Label = %SelectedAssetLabel

func configure(session_value: GameSession, objective_value: ProtectedObjective, defenses: Array[DefenseDefinition]) -> void:
	session = session_value
	objective = objective_value
	defense_definitions = defenses
	_build_defense_catalog()
	session.budget_changed.connect(_on_state_changed.unbind(1))
	session.phase_changed.connect(_on_phase_changed)
	session.statistics_changed.connect(_on_state_changed)
	objective.integrity_changed.connect(_on_integrity_changed)
	_on_state_changed()
	_on_integrity_changed(objective.current_integrity, objective.definition.maximum_integrity)

func set_pressure(level: int) -> void:
	pressure_level = level
	pressure_label.text = "위협 단계  %d" % level

func set_feedback(message: String) -> void:
	feedback_label.text = message

func set_selected_asset(unit: DefenseUnit, connection_count: int) -> void:
	selected_asset_panel.visible = unit != null
	if unit != null:
		selected_asset_label.text = "%s\nC2 직접 연결  %d" % [unit.definition.display_name, connection_count]

func _on_state_changed() -> void:
	budget_label.text = "예산  $%d" % session.budget
	time_label.text = "생존  %02d:%02d" % [int(session.survival_time) / 60, int(session.survival_time) % 60]
	speed_label.text = "일시정지" if is_zero_approx(session.simulation_speed) else "%d×" % int(session.simulation_speed)
	for index: int in defense_buttons.size():
		defense_buttons[index].disabled = session.phase == GameSession.Phase.GAME_OVER or session.budget < defense_definitions[index].price
	start_button.disabled = session.phase != GameSession.Phase.PREPARATION or session.defense_count < 1

func _on_integrity_changed(current: int, maximum: int) -> void:
	integrity_label.text = "도시  %d / %d" % [current, maximum]

func _on_phase_changed(new_phase: GameSession.Phase) -> void:
	start_button.visible = new_phase == GameSession.Phase.PREPARATION
	game_over_panel.visible = new_phase == GameSession.Phase.GAME_OVER
	if new_phase == GameSession.Phase.GAME_OVER:
		final_stats.text = "생존 시간  %02d:%02d\n무력화한 위협  %d\n배치한 포대  %d\n최고 위협 단계  %d" % [int(session.survival_time) / 60, int(session.survival_time) % 60, session.neutralized_count, session.defense_count, session.highest_pressure]
	_on_state_changed()

func _build_defense_catalog() -> void:
	for child: Node in defense_list.get_children():
		child.queue_free()
	defense_buttons.clear()
	for definition: DefenseDefinition in defense_definitions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.add_theme_font_size_override("font_size", 17)
		button.text = "%s  $%d" % [definition.display_name, definition.price]
		button.pressed.connect(_on_defense_pressed.bind(definition))
		defense_list.add_child(button)
		defense_buttons.append(button)

func _on_defense_pressed(definition: DefenseDefinition) -> void:
	defense_selected.emit(definition)

func _on_start_pressed() -> void:
	start_requested.emit()

func _on_pause_pressed() -> void:
	speed_requested.emit(0.0)

func _on_normal_pressed() -> void:
	speed_requested.emit(1.0)

func _on_fast_pressed() -> void:
	speed_requested.emit(2.0)

func _on_c2_overlay_pressed() -> void:
	c2_overlay_requested.emit()

func _on_same_seed_pressed() -> void:
	restart_requested.emit(true)

func _on_new_seed_pressed() -> void:
	restart_requested.emit(false)
