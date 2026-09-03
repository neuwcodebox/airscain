class_name Hud
extends Control

signal defense_selected(definition: DefenseDefinition)
signal start_requested
signal speed_requested(speed: float)
signal restart_requested(same_seed: bool)
signal overlay_requested(mode: StringName)
signal hold_fire_requested(enabled: bool)
signal engage_unknown_requested(enabled: bool)
signal priority_target_requested
signal munition_mode_requested
signal resupply_requested
signal repair_requested
signal relocation_requested
signal focus_requested
signal save_requested
signal load_requested
signal city_restoration_requested
signal sandbox_threat_selected(definition: ThreatDefinition)
signal training_next_requested

var session: GameSession
var objective: ProtectedObjective
var pressure_level: int = 1
var defense_definitions: Array[DefenseDefinition] = []
var defense_buttons: Array[Button] = []
var threat_definitions: Array[ThreatDefinition] = []
var selected_asset: DefenseUnit
var selected_track: PlayerTrack
var selected_asset_connection_count: int = 0
var overlay_mode_index: int = 0
var catalog_expanded: bool = true
var configured_game_mode: int = 0
const OVERLAY_MODES: Array[StringName] = [&"none", &"sensor", &"weapon", &"support", &"electronic", &"c2"]
const OVERLAY_LABELS: Array[String] = ["범위 없음", "센서 범위", "교전 영역", "지원 작업", "전자전", "C2 연결"]
const CATALOG_GROUP_ORDER: Array[StringName] = [&"sensor", &"network", &"missile", &"special"]
const CATALOG_GROUP_LABELS := {
	&"sensor": "감시·추적",
	&"network": "지휘·지원",
	&"missile": "미사일 방어",
	&"special": "근접·특수 요격",
}

@onready var budget_label: Label = %BudgetLabel
@onready var integrity_label: Label = %IntegrityLabel
@onready var city_restoration_button: Button = %CityRestorationButton
@onready var time_label: Label = %TimeLabel
@onready var pressure_label: Label = %PressureLabel
@onready var pause_button: Button = %PauseButton
@onready var normal_button: Button = %NormalButton
@onready var fast_button: Button = %FastButton
@onready var very_fast_button: Button = %VeryFastButton
@onready var alert_label: Label = %AlertLabel
@onready var overlay_button: Button = %OverlayButton
@onready var defense_list: VBoxContainer = %DefenseList
@onready var catalog: PanelContainer = %Catalog
@onready var catalog_toggle: Button = %CatalogToggle
@onready var defense_scroll: ScrollContainer = %DefenseScroll
@onready var start_button: Button = %StartButton
@onready var feedback_label: Label = %FeedbackLabel
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var final_stats: Label = %FinalStats
@onready var final_combat_stats: Label = %FinalCombatStats
@onready var final_network_stats: Label = %FinalNetworkStats
@onready var selected_asset_panel: PanelContainer = %SelectedAssetPanel
@onready var selected_asset_label: Label = %SelectedAssetLabel
@onready var selected_track_label: Label = %SelectedTrackLabel
@onready var relation_legend: Label = %RelationLegend
@onready var hold_fire_button: CheckButton = %HoldFireButton
@onready var engage_unknown_button: CheckButton = %EngageUnknownButton
@onready var priority_target_button: Button = %PriorityTargetButton
@onready var munition_mode_button: Button = %MunitionModeButton
@onready var resupply_button: Button = %ResupplyButton
@onready var repair_button: Button = %RepairButton
@onready var relocation_button: Button = %RelocationButton
@onready var focus_button: Button = %FocusButton
@onready var sandbox_threat_option: OptionButton = %SandboxThreatOption
@onready var sandbox_threat_button: Button = %SandboxThreatButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var training_panel: PanelContainer = %TrainingPanel
@onready var training_title: Label = %TrainingTitle
@onready var training_body: Label = %TrainingBody
@onready var training_next_button: Button = %TrainingNextButton

func configure(session_value: GameSession, objective_value: ProtectedObjective, defenses: Array[DefenseDefinition], threats: Array[ThreatDefinition] = [], game_mode: int = 0) -> void:
	session = session_value
	objective = objective_value
	defense_definitions = defenses
	threat_definitions = threats
	configured_game_mode = game_mode
	_build_defense_catalog()
	_build_mode_controls(game_mode)
	session.budget_changed.connect(_on_state_changed.unbind(1))
	session.phase_changed.connect(_on_phase_changed)
	session.statistics_changed.connect(_on_state_changed)
	objective.integrity_changed.connect(_on_integrity_changed)
	_on_state_changed()
	_on_integrity_changed(objective.current_integrity, objective.definition.maximum_integrity)
	set_selected_asset(null, 0)
	set_selected_track(null, false)
	set_catalog_expanded(true)

func _build_mode_controls(game_mode: int) -> void:
	sandbox_threat_option.clear()
	for definition: ThreatDefinition in threat_definitions:
		sandbox_threat_option.add_item(definition.display_name)
	sandbox_threat_option.visible = game_mode == 2
	sandbox_threat_button.visible = game_mode == 2
	save_button.disabled = game_mode != 0
	load_button.disabled = game_mode != 0
	training_panel.visible = game_mode == 1

func set_catalog_expanded(expanded: bool) -> void:
	catalog_expanded = expanded
	catalog_toggle.text = "방공망 자산  ▾" if expanded else "방공망 자산  ▴"
	defense_scroll.visible = expanded
	start_button.visible = expanded and session.phase == GameSession.Phase.PREPARATION
	sandbox_threat_option.visible = expanded and configured_game_mode == 2
	sandbox_threat_button.visible = expanded and configured_game_mode == 2
	if expanded:
		catalog.anchor_top = 0.0
		catalog.offset_top = 380.0
	else:
		catalog.anchor_top = 1.0
		catalog.offset_top = -66.0

func _on_catalog_toggle_pressed() -> void:
	set_catalog_expanded(not catalog_expanded)

func set_training_lesson(step: int, total: int, title: String, body: String, next_visible: bool = false) -> void:
	training_panel.visible = true
	training_title.text = "훈련 %d/%d · %s" % [step, total, title]
	training_body.text = body
	training_next_button.visible = next_visible

func set_pressure(level: int) -> void:
	pressure_level = level
	pressure_label.text = "전투 강도  %d" % level
	_on_state_changed()

func set_tactical_alert(hostile_count: int, engagement_count: int, warnings: Array[String]) -> void:
	var parts: Array[String] = ["▲ 적성 항적 %d" % hostile_count, "교전 %d" % engagement_count]
	parts.append_array(warnings)
	alert_label.text = "  ·  ".join(parts)
	alert_label.modulate = Color(1.0, 0.52, 0.32) if not warnings.is_empty() else Color(1.0, 0.78, 0.35)

func set_feedback(message: String) -> void:
	feedback_label.text = message

func set_final_stats(stats: Dictionary) -> void:
	final_stats.text = String(stats.get("summary", ""))
	final_combat_stats.text = String(stats.get("combat", ""))
	final_network_stats.text = String(stats.get("network", ""))

func _process(_delta: float) -> void:
	if selected_asset != null and is_instance_valid(selected_asset):
		_refresh_selected_asset_label()

func refresh_selected_asset() -> void:
	if selected_asset != null and is_instance_valid(selected_asset):
		set_selected_asset(selected_asset, selected_asset_connection_count)

func set_selected_asset(unit: DefenseUnit, connection_count: int) -> void:
	selected_asset = unit
	selected_asset_connection_count = connection_count
	selected_asset_panel.visible = unit != null or selected_track != null
	focus_button.visible = unit != null or selected_track != null
	if unit != null:
		_refresh_selected_asset_label()
		var supports_doctrine := unit.has_method("set_hold_fire")
		hold_fire_button.visible = supports_doctrine
		engage_unknown_button.visible = supports_doctrine
		priority_target_button.visible = supports_doctrine
		munition_mode_button.visible = unit is MissileBattery and (unit.definition as MissileBatteryDefinition).munitions.size() > 1
		resupply_button.visible = unit is ArmedDefenseUnit and (unit as ArmedDefenseUnit).uses_ammunition()
		repair_button.visible = true
		relocation_button.visible = unit.definition.mobile
		if supports_doctrine:
			var doctrine: Variant = unit.get("doctrine")
			hold_fire_button.set_pressed_no_signal(bool(doctrine.get("hold_fire")))
			engage_unknown_button.set_pressed_no_signal(bool(doctrine.get("engage_unknown")))
			priority_target_button.disabled = true
	elif selected_track == null:
		selected_asset_label.text = "선택 자산 없음"
	if unit == null:
		hold_fire_button.visible = false
		engage_unknown_button.visible = false
		priority_target_button.visible = false
		munition_mode_button.visible = false
		resupply_button.visible = false
		repair_button.visible = false
		relocation_button.visible = false

func _refresh_selected_asset_label() -> void:
	var resource_status := selected_asset.resource_status_text()
	selected_asset_label.text = "%s\nC2 직접 연결  %d" % [selected_asset.definition.display_name, selected_asset_connection_count]
	if not resource_status.is_empty():
		selected_asset_label.text += "\n%s" % resource_status
	if selected_asset is ArmedDefenseUnit:
		resupply_button.text = "재보급 요청  $%d" % (selected_asset as ArmedDefenseUnit).resupply_cost()
	if selected_asset is MissileBattery:
		munition_mode_button.text = "탄종  %s" % (selected_asset as MissileBattery).munition_mode_text()
	resupply_button.disabled = not selected_asset is ArmedDefenseUnit or not (selected_asset as ArmedDefenseUnit).uses_ammunition() or not (selected_asset as ArmedDefenseUnit).can_request_resupply()
	repair_button.text = "수리 요청  $%d" % selected_asset.repair_cost()
	repair_button.disabled = not selected_asset.can_request_repair()
	relocation_button.text = "재배치 위치 지정" if selected_asset.can_request_relocation() else "재배치 중"
	relocation_button.disabled = not selected_asset.can_request_relocation()

func set_selected_track(track: PlayerTrack, can_prioritize: bool, sensor_count: int = 0, engagement_count: int = 0) -> void:
	selected_track = track
	if selected_asset == null:
		selected_asset_label.text = "선택 자산 없음"
	selected_asset_panel.visible = selected_asset != null or track != null
	focus_button.visible = selected_asset != null or track != null
	if track == null:
		selected_track_label.visible = false
		relation_legend.visible = false
		priority_target_button.disabled = true
		return
	selected_track_label.visible = true
	relation_legend.visible = true
	selected_track_label.text = "%s %s · %s\n분류 확신 %d%% · 소속 확신 %d%%\n추적 품질 %d%% · 오차 ±%dm\n고도 %dm · 속도 %dm/s\n센서 %d · 교전 자산 %d" % [_affiliation_text(track), _classification_text(track.classification), _track_state_text(track.state), int(track.classification_confidence * 100.0), int(track.affiliation_confidence * 100.0), int(track.track_quality * 100.0), roundi(track.position_uncertainty), roundi(track.estimated_position.y), roundi(track.estimated_velocity.length()), sensor_count, engagement_count]
	priority_target_button.disabled = not can_prioritize

func _classification_text(classification: StringName) -> String:
	match classification:
		&"uav": return "무인기"
		&"small_uav": return "소형 무인기"
		&"cruise_missile": return "순항미사일"
		&"ballistic_missile": return "탄도미사일"
		&"rocket": return "로켓"
		&"strike_aircraft", &"aircraft": return "고속 항공기"
		&"air_contact": return "항공 접촉"
	return "미분류 표적" if classification.is_empty() else String(classification).replace("_", " ").capitalize()

func _track_state_text(state: PlayerTrack.State) -> String:
	match state:
		PlayerTrack.State.TENTATIVE:
			return "잠정"
		PlayerTrack.State.CONFIRMED:
			return "확인"
		PlayerTrack.State.COASTING:
			return "관측 단절"
	return "소실"

func _affiliation_text(track: PlayerTrack) -> String:
	if track.affiliation_confidence < 0.3:
		return "미확인"
	match track.affiliation:
		PlayerTrack.Affiliation.HOSTILE:
			return "적성"
		PlayerTrack.Affiliation.NEUTRAL:
			return "중립"
		PlayerTrack.Affiliation.FRIENDLY:
			return "아군"
	return "미확인"

func _on_state_changed() -> void:
	budget_label.text = "예산  무제한" if session.unlimited_budget else "예산  $%d" % session.budget
	_refresh_city_restoration_button()
	time_label.text = "생존  %02d:%02d" % [int(session.survival_time) / 60, int(session.survival_time) % 60]
	_refresh_speed_buttons()
	for index: int in defense_buttons.size():
		var definition := defense_definitions[index]
		var locked := definition.unlock_pressure_level > session.current_pressure
		defense_buttons[index].disabled = session.phase == GameSession.Phase.GAME_OVER or not session.unlimited_budget and session.budget < definition.price or locked
		defense_buttons[index].text = "%s  강도 %d 해금" % [definition.display_name, definition.unlock_pressure_level] if locked else definition.display_name if session.unlimited_budget else "%s  $%d" % [definition.display_name, definition.price]
	start_button.disabled = session.phase != GameSession.Phase.PREPARATION or session.defense_count < 1

func _refresh_speed_buttons() -> void:
	var buttons: Array[Button] = [pause_button, normal_button, fast_button, very_fast_button]
	var speeds: Array[float] = [0.0, 1.0, 2.0, 4.0]
	for index: int in buttons.size():
		var selected := is_equal_approx(session.simulation_speed, speeds[index])
		buttons[index].set_pressed_no_signal(selected)

func _on_integrity_changed(current: int, maximum: int) -> void:
	integrity_label.text = "도시  %d / %d" % [current, maximum]
	_refresh_city_restoration_button()

func _refresh_city_restoration_button() -> void:
	if session == null or objective == null or objective.definition == null:
		return
	var cost := objective.definition.restoration_cost
	var amount := objective.definition.restoration_amount
	city_restoration_button.text = "복구 +%d" % amount if session.unlimited_budget else "복구 +%d · $%d" % [amount, cost]
	city_restoration_button.disabled = session.phase == GameSession.Phase.GAME_OVER or objective.current_integrity >= objective.definition.maximum_integrity or not session.unlimited_budget and session.budget < cost

func _on_phase_changed(new_phase: GameSession.Phase) -> void:
	start_button.visible = catalog_expanded and new_phase == GameSession.Phase.PREPARATION
	game_over_panel.visible = new_phase == GameSession.Phase.GAME_OVER
	if new_phase == GameSession.Phase.GAME_OVER:
		final_stats.text = "생존 시간  %02d:%02d\n무력화한 위협  %d\n배치한 포대  %d\n최고 위협 단계  %d" % [int(session.survival_time) / 60, int(session.survival_time) % 60, session.neutralized_count, session.defense_count, session.highest_pressure]
	_on_state_changed()

func _build_defense_catalog() -> void:
	for child: Node in defense_list.get_children():
		child.queue_free()
	defense_buttons.clear()
	defense_buttons.resize(defense_definitions.size())
	for group_id: StringName in CATALOG_GROUP_ORDER:
		var group_definitions: Array[DefenseDefinition] = []
		for definition: DefenseDefinition in defense_definitions:
			if _catalog_group_for(definition) == group_id:
				group_definitions.append(definition)
		if group_definitions.is_empty():
			continue
		var heading := Label.new()
		heading.name = "CatalogGroup%s" % String(group_id).to_pascal_case()
		heading.text = String(CATALOG_GROUP_LABELS[group_id])
		heading.add_theme_color_override("font_color", Color(0.48, 0.82, 0.94))
		heading.add_theme_font_size_override("font_size", 13)
		defense_list.add_child(heading)
		for definition: DefenseDefinition in group_definitions:
			var button := Button.new()
			button.custom_minimum_size = Vector2(0.0, 32.0)
			button.add_theme_font_size_override("font_size", 14)
			button.text = "%s  $%d" % [definition.display_name, definition.price]
			button.pressed.connect(_on_defense_pressed.bind(definition))
			defense_list.add_child(button)
			defense_buttons[defense_definitions.find(definition)] = button

func _catalog_group_for(definition: DefenseDefinition) -> StringName:
	if definition is SearchRadarDefinition:
		return &"sensor"
	if definition is CommandPostDefinition or definition is SupportFacilityDefinition:
		return &"network"
	if definition is MissileBatteryDefinition:
		return &"missile"
	return &"special"

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

func _on_very_fast_pressed() -> void:
	speed_requested.emit(4.0)

func _on_c2_overlay_pressed() -> void:
	overlay_mode_index = (overlay_mode_index + 1) % OVERLAY_MODES.size()
	overlay_button.text = OVERLAY_LABELS[overlay_mode_index]
	overlay_requested.emit(OVERLAY_MODES[overlay_mode_index])

func _on_hold_fire_toggled(enabled: bool) -> void:
	hold_fire_requested.emit(enabled)

func _on_engage_unknown_toggled(enabled: bool) -> void:
	engage_unknown_requested.emit(enabled)

func _on_priority_target_pressed() -> void:
	priority_target_requested.emit()

func _on_munition_mode_pressed() -> void:
	munition_mode_requested.emit()
	_refresh_selected_asset_label()

func _on_resupply_pressed() -> void:
	resupply_requested.emit()

func _on_repair_pressed() -> void:
	repair_requested.emit()

func _on_relocation_pressed() -> void:
	relocation_requested.emit()

func _on_focus_pressed() -> void:
	focus_requested.emit()

func _on_save_pressed() -> void:
	save_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func _on_city_restoration_pressed() -> void:
	city_restoration_requested.emit()

func _on_sandbox_threat_pressed() -> void:
	var index := sandbox_threat_option.selected
	if index >= 0 and index < threat_definitions.size():
		sandbox_threat_selected.emit(threat_definitions[index])

func _on_sandbox_threat_option_selected(index: int) -> void:
	if index >= 0 and index < threat_definitions.size():
		sandbox_threat_selected.emit(threat_definitions[index])

func _on_training_next_pressed() -> void:
	training_next_requested.emit()

func _on_same_seed_pressed() -> void:
	restart_requested.emit(true)

func _on_new_seed_pressed() -> void:
	restart_requested.emit(false)
