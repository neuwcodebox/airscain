class_name Hud
extends Control

signal defense_selected(definition: DefenseDefinition)
signal start_requested
signal speed_requested(speed: float)
signal restart_requested(same_seed: bool)

var session: GameSession
var objective: ProtectedObjective
var pressure_level: int = 1
var defense_definition: DefenseDefinition

@onready var budget_label: Label = %BudgetLabel
@onready var integrity_label: Label = %IntegrityLabel
@onready var time_label: Label = %TimeLabel
@onready var pressure_label: Label = %PressureLabel
@onready var speed_label: Label = %SpeedLabel
@onready var defense_button: Button = %DefenseButton
@onready var start_button: Button = %StartButton
@onready var feedback_label: Label = %FeedbackLabel
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var final_stats: Label = %FinalStats

func configure(session_value: GameSession, objective_value: ProtectedObjective, defenses: Array[DefenseDefinition]) -> void:
	session = session_value
	objective = objective_value
	defense_definition = defenses[0] if not defenses.is_empty() else null
	if defense_definition != null:
		defense_button.text = "%s  $%d" % [defense_definition.display_name, defense_definition.price]
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

func _on_state_changed() -> void:
	budget_label.text = "예산  $%d" % session.budget
	time_label.text = "생존  %02d:%02d" % [int(session.survival_time) / 60, int(session.survival_time) % 60]
	speed_label.text = "일시정지" if is_zero_approx(session.simulation_speed) else "%d×" % int(session.simulation_speed)
	defense_button.disabled = session.phase == GameSession.Phase.GAME_OVER or session.budget < (defense_definition.price if defense_definition != null else 0)
	start_button.disabled = session.phase != GameSession.Phase.PREPARATION or session.defense_count < 1

func _on_integrity_changed(current: int, maximum: int) -> void:
	integrity_label.text = "도시  %d / %d" % [current, maximum]

func _on_phase_changed(new_phase: GameSession.Phase) -> void:
	start_button.visible = new_phase == GameSession.Phase.PREPARATION
	game_over_panel.visible = new_phase == GameSession.Phase.GAME_OVER
	if new_phase == GameSession.Phase.GAME_OVER:
		final_stats.text = "생존 시간  %02d:%02d\n무력화한 위협  %d\n배치한 포대  %d\n최고 위협 단계  %d" % [int(session.survival_time) / 60, int(session.survival_time) % 60, session.neutralized_count, session.defense_count, session.highest_pressure]
	_on_state_changed()

func _on_defense_pressed() -> void:
	if defense_definition != null:
		defense_selected.emit(defense_definition)

func _on_start_pressed() -> void:
	start_requested.emit()

func _on_pause_pressed() -> void:
	speed_requested.emit(0.0)

func _on_normal_pressed() -> void:
	speed_requested.emit(1.0)

func _on_fast_pressed() -> void:
	speed_requested.emit(2.0)

func _on_same_seed_pressed() -> void:
	restart_requested.emit(true)

func _on_new_seed_pressed() -> void:
	restart_requested.emit(false)
