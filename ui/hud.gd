class_name Hud
extends Control

signal defense_selected(definition: DefenseDefinition)
signal start_requested
signal speed_requested(speed: float)
signal restart_requested(same_seed: bool)
signal c2_overlay_requested
signal hold_fire_requested(enabled: bool)
signal engage_unknown_requested(enabled: bool)
signal priority_target_requested
signal resupply_requested
signal repair_requested
signal save_requested
signal load_requested

var session: GameSession
var objective: ProtectedObjective
var pressure_level: int = 1
var defense_definitions: Array[DefenseDefinition] = []
var defense_buttons: Array[Button] = []
var selected_asset: DefenseUnit
var selected_asset_connection_count: int = 0

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
@onready var selected_track_label: Label = %SelectedTrackLabel
@onready var hold_fire_button: CheckButton = %HoldFireButton
@onready var engage_unknown_button: CheckButton = %EngageUnknownButton
@onready var priority_target_button: Button = %PriorityTargetButton
@onready var resupply_button: Button = %ResupplyButton
@onready var repair_button: Button = %RepairButton

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

func _process(_delta: float) -> void:
	if selected_asset != null and is_instance_valid(selected_asset):
		_refresh_selected_asset_label()

func set_selected_asset(unit: DefenseUnit, connection_count: int) -> void:
	selected_asset = unit
	selected_asset_connection_count = connection_count
	selected_asset_panel.visible = unit != null
	if unit != null:
		_refresh_selected_asset_label()
		var supports_doctrine := unit.has_method("set_hold_fire")
		hold_fire_button.visible = supports_doctrine
		engage_unknown_button.visible = supports_doctrine
		priority_target_button.visible = supports_doctrine
		resupply_button.visible = unit is ArmedDefenseUnit
		repair_button.visible = true
		if supports_doctrine:
			var doctrine: Variant = unit.get("doctrine")
			hold_fire_button.set_pressed_no_signal(bool(doctrine.get("hold_fire")))
			engage_unknown_button.set_pressed_no_signal(bool(doctrine.get("engage_unknown")))
			priority_target_button.disabled = true
		selected_track_label.text = "항적을 클릭해 상세 확인"

func _refresh_selected_asset_label() -> void:
	var resource_status := selected_asset.resource_status_text()
	selected_asset_label.text = "%s\nC2 직접 연결  %d" % [selected_asset.definition.display_name, selected_asset_connection_count]
	if not resource_status.is_empty():
		selected_asset_label.text += "\n%s" % resource_status
	if selected_asset is ArmedDefenseUnit:
		resupply_button.text = "재보급 요청  $%d" % (selected_asset as ArmedDefenseUnit).resupply_cost()
	resupply_button.disabled = not selected_asset is ArmedDefenseUnit or not (selected_asset as ArmedDefenseUnit).can_request_resupply()
	repair_button.text = "수리 요청  $%d" % selected_asset.repair_cost()
	repair_button.disabled = not selected_asset.can_request_repair()

func set_selected_track(track: PlayerTrack, can_prioritize: bool) -> void:
	if track == null:
		selected_track_label.text = "항적을 클릭해 상세 확인"
		priority_target_button.disabled = true
		return
	selected_track_label.text = "%s  분류 %d%%\n소속 %d%% · 추적 %d%%" % [String(track.classification).to_upper(), int(track.classification_confidence * 100.0), int(track.affiliation_confidence * 100.0), int(track.track_quality * 100.0)]
	priority_target_button.disabled = not can_prioritize

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

func _on_hold_fire_toggled(enabled: bool) -> void:
	hold_fire_requested.emit(enabled)

func _on_engage_unknown_toggled(enabled: bool) -> void:
	engage_unknown_requested.emit(enabled)

func _on_priority_target_pressed() -> void:
	priority_target_requested.emit()

func _on_resupply_pressed() -> void:
	resupply_requested.emit()

func _on_repair_pressed() -> void:
	repair_requested.emit()

func _on_save_pressed() -> void:
	save_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func _on_same_seed_pressed() -> void:
	restart_requested.emit(true)

func _on_new_seed_pressed() -> void:
	restart_requested.emit(false)
