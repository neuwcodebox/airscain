class_name Hud
extends Control

signal defense_selected(definition: DefenseDefinition)
signal start_requested
signal speed_requested(speed: float)
signal restart_requested(same_seed: bool)
signal main_menu_requested
signal overlay_requested(mode: StringName)
signal hold_fire_requested(enabled: bool)
signal engage_unknown_requested(enabled: bool)
signal priority_target_requested
signal munition_mode_requested
signal resupply_requested
signal repair_requested
signal relocation_requested
signal focus_requested
signal city_restoration_requested
signal sandbox_threat_selected(definition: ThreatDefinition)
signal training_next_requested

var session: GameSession
var objective: ProtectedObjective
var pressure_level: int = 1
var defense_definitions: Array[DefenseDefinition] = []
var defense_buttons: Array[Button] = []
var defense_name_labels: Array[Label] = []
var defense_meta_labels: Array[Label] = []
var threat_definitions: Array[ThreatDefinition] = []
var selected_asset: DefenseUnit
var selected_track: PlayerTrack
var selected_asset_connection_count: int = 0
var selected_asset_support_connection_count: int = 0
var selected_track_sensor_count: int = 0
var selected_track_engagement_count: int = 0
var selected_track_can_prioritize: bool = false
var overlay_mode_index: int = 0
var catalog_expanded: bool = false
var city_menu_expanded: bool = false
var threat_menu_expanded: bool = false
var configured_game_mode: int = 0
var feedback_context: String = ""
var feedback_remaining: float = 0.0
var menu_row_normal: StyleBoxFlat
var menu_row_hover: StyleBoxFlat
var menu_row_pressed: StyleBoxFlat
var menu_row_disabled: StyleBoxFlat
const FEEDBACK_DURATION := 3.5
const METRIC_KEY_COLOR := Color(0.58, 0.68, 0.72)
const METRIC_VALUE_COLOR := Color(0.86, 0.9, 0.88)
const METRIC_WARNING_COLOR := Color(1.0, 0.62, 0.3)
const METRIC_FONT_SIZE := 14
const MENU_COLLAPSED_SYMBOL := "▼"
const MENU_EXPANDED_SYMBOL := "▲"
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
@onready var defense_menu_button: Button = %DefenseMenuButton
@onready var city_menu_button: Button = %CityMenuButton
@onready var threat_menu_button: Button = %ThreatMenuButton
@onready var city_restoration_button: Button = %CityRestorationButton
@onready var time_label: Label = %TimeLabel
@onready var placement_power_panel: PanelContainer = %PlacementPowerPanel
@onready var placement_power_label: Label = %PlacementPowerLabel
@onready var pressure_label: Label = %PressureLabel
@onready var pause_button: Button = %PauseButton
@onready var normal_button: Button = %NormalButton
@onready var fast_button: Button = %FastButton
@onready var very_fast_button: Button = %VeryFastButton
@onready var alert_label: Label = %AlertLabel
@onready var overlay_button: Button = %OverlayButton
@onready var defense_list: VBoxContainer = %DefenseList
@onready var catalog: PanelContainer = %Catalog
@onready var catalog_budget_label: Label = %CatalogBudgetLabel
@onready var city_menu: PanelContainer = %CityMenu
@onready var city_integrity_label: Label = %CityIntegrityLabel
@onready var city_action_label: Label = %CityActionLabel
@onready var city_action_meta_label: Label = %CityActionMetaLabel
@onready var threat_menu: PanelContainer = %ThreatMenu
@onready var defense_scroll: ScrollContainer = %DefenseScroll
@onready var start_button: Button = %StartButton
@onready var feedback_label: Label = %FeedbackLabel
@onready var game_over_blocker: ColorRect = %GameOverBlocker
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var game_over_main_menu_button: Button = %GameOverMainMenuButton
@onready var final_stats: Label = %FinalStats
@onready var final_combat_stats: Label = %FinalCombatStats
@onready var final_network_stats: Label = %FinalNetworkStats
@onready var selected_asset_panel: PanelContainer = %SelectedAssetPanel
@onready var selection_kind_label: Label = %SelectionKindLabel
@onready var selected_asset_label: Label = %SelectedAssetLabel
@onready var selection_state_label: Label = %SelectionStateLabel
@onready var asset_section: VBoxContainer = %AssetSection
@onready var asset_metrics: GridContainer = %AssetMetrics
@onready var track_section: VBoxContainer = %TrackSection
@onready var track_metrics: GridContainer = %TrackMetrics
@onready var selected_track_label: Label = %SelectedTrackLabel
@onready var relation_legend: HBoxContainer = %RelationLegend
@onready var track_classification_confidence_value: Label = %TrackClassificationConfidenceValue
@onready var track_affiliation_confidence_value: Label = %TrackAffiliationConfidenceValue
@onready var track_quality_value: Label = %TrackQualityValue
@onready var track_uncertainty_value: Label = %TrackUncertaintyValue
@onready var track_altitude_value: Label = %TrackAltitudeValue
@onready var track_speed_value: Label = %TrackSpeedValue
@onready var track_sensor_value: Label = %TrackSensorValue
@onready var track_engagement_value: Label = %TrackEngagementValue
@onready var engagement_section: VBoxContainer = %EngagementSection
@onready var engagement_source_label: Label = %EngagementSourceLabel
@onready var engagement_source_metrics: GridContainer = %EngagementSourceMetrics
@onready var engagement_target_label: Label = %EngagementTargetLabel
@onready var engagement_target_metrics: GridContainer = %EngagementTargetMetrics
@onready var doctrine_section: VBoxContainer = %DoctrineSection
@onready var action_section: VBoxContainer = %ActionSection
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
	_style_metric_grid(track_metrics, 48.0)
	_ensure_menu_row_styles()
	_apply_menu_row_style(city_restoration_button)
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
	set_catalog_expanded(false)
	set_city_menu_expanded(false)
	set_threat_menu_expanded(false)
	get_viewport().size_changed.connect(_position_context_menus)
	call_deferred("_position_context_menus")

func _build_mode_controls(game_mode: int) -> void:
	sandbox_threat_option.clear()
	for definition: ThreatDefinition in threat_definitions:
		sandbox_threat_option.add_item(definition.display_name)
	threat_menu_button.visible = game_mode == 2
	training_panel.visible = game_mode == 1

func set_catalog_expanded(expanded: bool) -> void:
	catalog_expanded = expanded
	if expanded and city_menu_expanded:
		set_city_menu_expanded(false)
	if expanded and threat_menu_expanded:
		set_threat_menu_expanded(false)
	defense_menu_button.text = "방공 자산  %s" % (MENU_EXPANDED_SYMBOL if expanded else MENU_COLLAPSED_SYMBOL)
	catalog.visible = expanded
	defense_scroll.visible = expanded
	if expanded:
		_raise_context_menu(catalog)
		_position_context_menus()

func _on_defense_menu_pressed() -> void:
	set_catalog_expanded(not catalog_expanded)

func set_city_menu_expanded(expanded: bool) -> void:
	city_menu_expanded = expanded
	if expanded and catalog_expanded:
		set_catalog_expanded(false)
	if expanded and threat_menu_expanded:
		set_threat_menu_expanded(false)
	city_menu_button.text = _city_menu_text(MENU_EXPANDED_SYMBOL if expanded else MENU_COLLAPSED_SYMBOL)
	city_menu.visible = expanded
	if expanded:
		_raise_context_menu(city_menu)
		_position_context_menus()

func _on_city_menu_pressed() -> void:
	set_city_menu_expanded(not city_menu_expanded)

func set_threat_menu_expanded(expanded: bool) -> void:
	threat_menu_expanded = expanded and configured_game_mode == 2
	if threat_menu_expanded and catalog_expanded:
		set_catalog_expanded(false)
	if threat_menu_expanded and city_menu_expanded:
		set_city_menu_expanded(false)
	threat_menu_button.text = "위협 투입  %s" % (MENU_EXPANDED_SYMBOL if threat_menu_expanded else MENU_COLLAPSED_SYMBOL)
	threat_menu.visible = threat_menu_expanded
	if threat_menu_expanded:
		_raise_context_menu(threat_menu)
		_position_context_menus()

func _on_threat_menu_pressed() -> void:
	set_threat_menu_expanded(not threat_menu_expanded)

func _position_context_menus() -> void:
	var viewport_size := get_viewport_rect().size
	var menu_top := ($TopBar as Control).get_global_rect().end.y + 4.0
	var catalog_width := 340.0
	var desired_catalog_height := defense_list.get_combined_minimum_size().y + 62.0
	var catalog_height := minf(minf(520.0, desired_catalog_height), viewport_size.y - menu_top - 18.0)
	var catalog_x := clampf(defense_menu_button.get_global_rect().position.x, 18.0, viewport_size.x - catalog_width - 18.0)
	catalog.position = Vector2(catalog_x, menu_top)
	catalog.size = Vector2(catalog_width, catalog_height)
	var city_width := 340.0
	var city_x := clampf(city_menu_button.get_global_rect().position.x, 18.0, viewport_size.x - city_width - 18.0)
	city_menu.position = Vector2(city_x, menu_top)
	city_menu.size = Vector2(city_width, 112.0)
	var threat_width := 280.0
	var threat_x := clampf(threat_menu_button.get_global_rect().position.x, 18.0, viewport_size.x - threat_width - 18.0)
	threat_menu.position = Vector2(threat_x, menu_top)
	threat_menu.size = Vector2(threat_width, 96.0)

func _raise_context_menu(menu: Control) -> void:
	menu.move_to_front()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (catalog_expanded or city_menu_expanded or threat_menu_expanded):
		set_catalog_expanded(false)
		set_city_menu_expanded(false)
		set_threat_menu_expanded(false)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	if catalog_expanded and not catalog.get_global_rect().has_point(mouse_button.position) and not defense_menu_button.get_global_rect().has_point(mouse_button.position):
		set_catalog_expanded(false)
	if city_menu_expanded and not city_menu.get_global_rect().has_point(mouse_button.position) and not city_menu_button.get_global_rect().has_point(mouse_button.position):
		set_city_menu_expanded(false)
	if threat_menu_expanded and not threat_menu.get_global_rect().has_point(mouse_button.position) and not threat_menu_button.get_global_rect().has_point(mouse_button.position):
		set_threat_menu_expanded(false)

func set_training_lesson(step: int, total: int, title: String, body: String, next_visible: bool = false) -> void:
	training_panel.visible = true
	training_title.text = "훈련 %d/%d · %s" % [step, total, title]
	training_body.text = body
	training_next_button.visible = next_visible

func set_pressure(level: int) -> void:
	pressure_level = level
	pressure_label.text = "위협 단계  %d" % level
	_on_state_changed()

func set_tactical_alert(hostile_count: int, engagement_count: int, warnings: Array[String]) -> void:
	var parts: Array[String] = ["▲ 적성 항적 %d" % hostile_count, "교전 %d" % engagement_count]
	parts.append_array(warnings)
	alert_label.text = "    ".join(parts)
	alert_label.modulate = Color(1.0, 0.52, 0.32) if not warnings.is_empty() else Color(1.0, 0.78, 0.35)

func set_feedback(message: String, transient: bool = true) -> void:
	if transient:
		feedback_remaining = FEEDBACK_DURATION if not message.is_empty() else 0.0
		_set_feedback_text(message if not message.is_empty() else feedback_context)
		return
	feedback_context = message
	if feedback_remaining <= 0.0:
		_set_feedback_text(feedback_context)

func _set_feedback_text(message: String) -> void:
	feedback_label.text = message
	feedback_label.visible = not message.is_empty()

func set_placement_power_preview(current_demand: float, added_demand: float, capacity: float, added_capacity: float, screen_position: Vector2, active: bool) -> void:
	placement_power_panel.visible = active and (added_demand > 0.0 or added_capacity > 0.0)
	if not placement_power_panel.visible:
		return
	var expected_demand := current_demand + added_demand
	var expected_capacity := capacity + added_capacity
	placement_power_label.text = "전력 수요  %d / %d\n배치 후  %d / %d" % [roundi(current_demand), roundi(capacity), roundi(expected_demand), roundi(expected_capacity)]
	var color := Color(1.0, 0.48, 0.3) if expected_demand > expected_capacity else Color(0.45, 0.92, 0.82)
	placement_power_label.add_theme_color_override("font_color", color)
	var viewport_size := get_viewport_rect().size
	var panel_size := placement_power_panel.size
	var preferred := screen_position + Vector2(22.0, -panel_size.y * 0.5)
	placement_power_panel.position = Vector2(clampf(preferred.x, 12.0, viewport_size.x - panel_size.x - 12.0), clampf(preferred.y, 66.0, viewport_size.y - panel_size.y - 12.0))

func set_final_stats(stats: Dictionary) -> void:
	final_stats.text = String(stats.get("summary", ""))
	final_combat_stats.text = String(stats.get("combat", ""))
	final_network_stats.text = String(stats.get("network", ""))

func _process(delta: float) -> void:
	if feedback_remaining > 0.0:
		feedback_remaining = maxf(0.0, feedback_remaining - delta)
		if feedback_remaining <= 0.0:
			_set_feedback_text(feedback_context)
	if selected_asset != null and is_instance_valid(selected_asset):
		_refresh_selected_asset_label(false)

func refresh_selected_asset() -> void:
	if selected_asset != null and is_instance_valid(selected_asset):
		set_selected_asset(selected_asset, selected_asset_connection_count, selected_asset_support_connection_count)

func set_selected_asset(unit: DefenseUnit, connection_count: int, support_connection_count: int = 0) -> void:
	selected_asset = unit
	selected_asset_connection_count = connection_count
	selected_asset_support_connection_count = support_connection_count
	if unit != null:
		var supports_doctrine := unit.supports_engagement_controls()
		if supports_doctrine:
			hold_fire_button.set_pressed_no_signal(unit.engagement_hold_fire())
			engage_unknown_button.set_pressed_no_signal(unit.engagement_engages_unknown())
		_refresh_selected_asset_label()
	else:
		_refresh_selection_view()

func _refresh_selected_asset_label(fit_panel: bool = true) -> void:
	if selected_asset == null or not is_instance_valid(selected_asset):
		return
	_refresh_asset_metrics()
	if selected_asset.uses_ammunition():
		resupply_button.text = "재보급 요청  $%d" % selected_asset.resupply_cost()
	if selected_asset.supports_munition_selection():
		munition_mode_button.text = "탄종  %s" % selected_asset.munition_mode_text()
	resupply_button.disabled = not selected_asset.uses_ammunition() or not selected_asset.can_request_resupply()
	repair_button.text = "수리 요청  $%d" % selected_asset.repair_cost()
	repair_button.disabled = not selected_asset.can_request_repair()
	relocation_button.text = "재배치 위치 지정" if selected_asset.can_request_relocation() else "재배치 중"
	relocation_button.disabled = not selected_asset.can_request_relocation()
	_refresh_selection_view(fit_panel)

func set_selected_track(track: PlayerTrack, can_prioritize: bool, sensor_count: int = 0, engagement_count: int = 0) -> void:
	selected_track = track
	selected_track_can_prioritize = can_prioritize
	selected_track_sensor_count = sensor_count
	selected_track_engagement_count = engagement_count
	_refresh_selection_view()

func _refresh_selection_view(fit_panel: bool = true) -> void:
	var has_asset := selected_asset != null and is_instance_valid(selected_asset)
	var has_track := selected_track != null
	var engagement_review := has_asset and has_track and selected_asset.supports_engagement_controls()
	selected_asset_panel.visible = has_asset or has_track
	if not selected_asset_panel.visible:
		return
	asset_section.visible = has_asset and not has_track
	track_section.visible = has_track and not engagement_review
	engagement_section.visible = engagement_review
	doctrine_section.visible = has_asset and not has_track and selected_asset.supports_engagement_controls()
	action_section.visible = has_asset or has_track
	hold_fire_button.visible = doctrine_section.visible
	engage_unknown_button.visible = doctrine_section.visible
	munition_mode_button.visible = doctrine_section.visible and selected_asset.supports_munition_selection()
	priority_target_button.visible = engagement_review
	priority_target_button.disabled = not selected_track_can_prioritize
	resupply_button.visible = has_asset and not has_track and selected_asset.uses_ammunition()
	repair_button.visible = has_asset and not has_track
	relocation_button.visible = has_asset and not has_track and selected_asset.definition.mobile
	focus_button.visible = has_asset or has_track
	if engagement_review:
		_refresh_engagement_review()
	elif has_track:
		_refresh_track_details()
	else:
		selection_kind_label.text = "방공 자산"
		selected_asset_label.text = selected_asset.definition.display_name
		selection_state_label.text = _asset_state_text(selected_asset)
		_set_state_color(selected_asset.active and selected_asset.operational_ratio() >= 0.75)
		_refresh_selected_asset_label_fields_only()
	if fit_panel:
		call_deferred("_fit_selection_panel")

func _refresh_selected_asset_label_fields_only() -> void:
	_refresh_asset_metrics()

func _refresh_asset_metrics() -> void:
	var network_value := "직접 연결 %d" % selected_asset_connection_count
	var support_value := "연결됨" if selected_asset_support_connection_count > 0 else "범위 밖"
	if selected_asset.service_range() > 0.0:
		network_value = "해당 없음"
		support_value = "지원 가능 %d" % selected_asset_support_connection_count
	var rows: Array[Dictionary] = [
		{"label": "내구도", "value": "%d%%" % roundi(selected_asset.operational_ratio() * 100.0)},
		{"label": "지휘통제", "value": network_value},
		{"label": "지역 지원", "value": support_value},
	]
	rows.append_array(selected_asset.selection_status_rows())
	_set_metric_rows(asset_metrics, rows)

func _refresh_track_details() -> void:
	selection_kind_label.text = "항적 정보"
	selected_asset_label.text = "%s %s" % [_affiliation_text(selected_track), _classification_text(selected_track.classification)]
	selection_state_label.text = _track_state_text(selected_track.state)
	_set_state_color(selected_track.state == PlayerTrack.State.CONFIRMED)
	selected_track_label.text = "식별 및 추적 정보"
	track_classification_confidence_value.text = "%d%%" % roundi(selected_track.classification_confidence * 100.0)
	track_affiliation_confidence_value.text = "%d%%" % roundi(selected_track.affiliation_confidence * 100.0)
	track_quality_value.text = "%d%%" % roundi(selected_track.track_quality * 100.0)
	track_uncertainty_value.text = "±%dm" % roundi(selected_track.position_uncertainty)
	track_altitude_value.text = "%dm" % roundi(selected_track.estimated_position.y)
	track_speed_value.text = "%dm/s" % roundi(selected_track.estimated_velocity.length())
	track_sensor_value.text = str(selected_track_sensor_count)
	track_engagement_value.text = str(selected_track_engagement_count)

func _refresh_engagement_review() -> void:
	selection_kind_label.text = "교전 검토"
	selected_asset_label.text = "자산과 항적"
	selection_state_label.text = "선택됨"
	_set_state_color(true)
	engagement_source_label.text = selected_asset.definition.display_name
	var source_rows: Array[Dictionary] = [
		{"label": "상태", "value": _asset_state_text(selected_asset), "warning": not selected_asset.active},
		{"label": "내구도", "value": "%d%%" % roundi(selected_asset.operational_ratio() * 100.0)},
		{"label": "지휘통제", "value": "직접 연결 %d" % selected_asset_connection_count},
	]
	source_rows.append_array(selected_asset.selection_status_rows())
	_set_metric_rows(engagement_source_metrics, source_rows)
	engagement_target_label.text = "%s %s" % [_affiliation_text(selected_track), _classification_text(selected_track.classification)]
	_set_metric_rows(engagement_target_metrics, [
		{"label": "상태", "value": _track_state_text(selected_track.state)},
		{"label": "추적 품질", "value": "%d%%" % roundi(selected_track.track_quality * 100.0)},
		{"label": "고도", "value": "%dm" % roundi(selected_track.estimated_position.y)},
		{"label": "속도", "value": "%dm/s" % roundi(selected_track.estimated_velocity.length())},
	])

func _set_metric_rows(grid: GridContainer, rows: Array[Dictionary]) -> void:
	if grid.get_child_count() != rows.size() * 2:
		for child: Node in grid.get_children():
			child.free()
		for row: Dictionary in rows:
			var key_label := Label.new()
			grid.add_child(key_label)
			var value_label := Label.new()
			grid.add_child(value_label)
	_style_metric_grid(grid, 132.0)
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var key_label := grid.get_child(index * 2) as Label
		var value_label := grid.get_child(index * 2 + 1) as Label
		key_label.text = String(row.get("label", ""))
		value_label.text = String(row.get("value", ""))
		value_label.add_theme_color_override("font_color", METRIC_WARNING_COLOR if bool(row.get("warning", false)) else METRIC_VALUE_COLOR)

func _style_metric_grid(grid: GridContainer, value_width: float) -> void:
	for index: int in grid.get_child_count():
		var label := grid.get_child(index) as Label
		if label == null:
			continue
		label.add_theme_font_size_override("font_size", METRIC_FONT_SIZE)
		if index % 2 == 0:
			label.add_theme_color_override("font_color", METRIC_KEY_COLOR)
		else:
			label.custom_minimum_size.x = value_width
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_color_override("font_color", METRIC_VALUE_COLOR)

func _asset_state_text(unit: DefenseUnit) -> String:
	if unit.integrity <= 0.0:
		return "파괴"
	if not unit.active:
		return "기능 정지"
	if unit.operational_ratio() < 0.75:
		return "성능 저하"
	return "정상"

func _set_state_color(positive: bool) -> void:
	selection_state_label.add_theme_color_override("font_color", Color(0.45, 0.92, 0.66) if positive else Color(1.0, 0.62, 0.3))

func _fit_selection_panel() -> void:
	selected_asset_panel.reset_size()
	var panel_size := selected_asset_panel.get_combined_minimum_size()
	selected_asset_panel.size = panel_size
	selected_asset_panel.position = Vector2(18.0, get_viewport_rect().size.y - panel_size.y - 18.0)

func _classification_text(classification: StringName) -> String:
	match classification:
		&"bird": return "조류"
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
	catalog_budget_label.text = "예산 무제한" if session.unlimited_budget else "예산 $%d" % session.budget
	_refresh_city_restoration_button()
	time_label.text = "생존  %02d:%02d" % [int(session.survival_time) / 60, int(session.survival_time) % 60]
	_refresh_speed_buttons()
	for index: int in defense_buttons.size():
		var definition := defense_definitions[index]
		var locked := definition.unlock_pressure_level > session.current_pressure
		var unaffordable := not session.unlimited_budget and session.budget < definition.price
		defense_buttons[index].disabled = session.phase == GameSession.Phase.GAME_OVER or unaffordable or locked
		defense_name_labels[index].add_theme_color_override("font_color", Color(0.48, 0.55, 0.6) if defense_buttons[index].disabled else Color(0.86, 0.92, 0.95))
		if locked:
			defense_meta_labels[index].text = "%d단계 해금" % definition.unlock_pressure_level
			defense_meta_labels[index].add_theme_color_override("font_color", Color(0.78, 0.57, 0.32))
		elif session.unlimited_budget:
			defense_meta_labels[index].text = "무료"
			defense_meta_labels[index].add_theme_color_override("font_color", Color(0.45, 0.92, 0.66))
		else:
			defense_meta_labels[index].text = "$%d" % definition.price
			defense_meta_labels[index].add_theme_color_override("font_color", Color(0.65, 0.48, 0.42) if unaffordable else Color(0.45, 0.92, 0.66))
	start_button.disabled = session.phase != GameSession.Phase.PREPARATION or session.defense_count < 1

func _refresh_speed_buttons() -> void:
	var buttons: Array[Button] = [pause_button, normal_button, fast_button, very_fast_button]
	var speeds: Array[float] = [0.0, 1.0, 2.0, 4.0]
	for index: int in buttons.size():
		var selected := is_equal_approx(session.simulation_speed, speeds[index])
		buttons[index].set_pressed_no_signal(selected)

func _on_integrity_changed(current: int, maximum: int) -> void:
	city_menu_button.text = _city_menu_text(MENU_EXPANDED_SYMBOL if city_menu_expanded else MENU_COLLAPSED_SYMBOL, current, maximum)
	city_integrity_label.text = "%d / %d" % [current, maximum]
	_refresh_city_restoration_button()

func _city_menu_text(arrow: String, current: int = -1, maximum: int = -1) -> String:
	var displayed_current := objective.current_integrity if current < 0 and objective != null else current
	var displayed_maximum := objective.definition.maximum_integrity if maximum < 0 and objective != null else maximum
	return "도시 상태  %d / %d  %s" % [displayed_current, displayed_maximum, arrow]

func _refresh_city_restoration_button() -> void:
	if session == null or objective == null or objective.definition == null:
		return
	var cost := objective.definition.restoration_cost
	var amount := objective.definition.restoration_amount
	city_action_label.text = "피해 복구"
	city_action_meta_label.text = "+%d    무료" % amount if session.unlimited_budget else "+%d    $%d" % [amount, cost]
	city_restoration_button.disabled = session.phase == GameSession.Phase.GAME_OVER or objective.current_integrity >= objective.definition.maximum_integrity or not session.unlimited_budget and session.budget < cost
	city_action_label.add_theme_color_override("font_color", Color(0.48, 0.55, 0.6) if city_restoration_button.disabled else Color(0.86, 0.92, 0.95))
	city_action_meta_label.add_theme_color_override("font_color", Color(0.48, 0.55, 0.6) if city_restoration_button.disabled else Color(0.45, 0.92, 0.66))

func _on_phase_changed(new_phase: GameSession.Phase) -> void:
	start_button.visible = new_phase == GameSession.Phase.PREPARATION
	var game_over := new_phase == GameSession.Phase.GAME_OVER
	game_over_blocker.visible = game_over
	game_over_panel.visible = game_over
	_set_gameplay_controls_disabled(game_over)
	if game_over:
		set_catalog_expanded(false)
		set_city_menu_expanded(false)
		set_threat_menu_expanded(false)
		final_stats.text = "생존 시간  %02d:%02d\n무력화한 위협  %d\n배치한 포대  %d\n최고 위협 단계  %d" % [int(session.survival_time) / 60, int(session.survival_time) % 60, session.neutralized_count, session.defense_count, session.highest_pressure]
	_on_state_changed()

func _set_gameplay_controls_disabled(disabled: bool) -> void:
	defense_menu_button.disabled = disabled
	city_menu_button.disabled = disabled
	threat_menu_button.disabled = disabled
	pause_button.disabled = disabled
	normal_button.disabled = disabled
	fast_button.disabled = disabled
	very_fast_button.disabled = disabled
	overlay_button.disabled = disabled

func _build_defense_catalog() -> void:
	for child: Node in defense_list.get_children():
		child.queue_free()
	defense_buttons.clear()
	defense_buttons.resize(defense_definitions.size())
	defense_name_labels.clear()
	defense_name_labels.resize(defense_definitions.size())
	defense_meta_labels.clear()
	defense_meta_labels.resize(defense_definitions.size())
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
		heading.custom_minimum_size = Vector2(0.0, 24.0)
		heading.add_theme_font_size_override("font_size", 13)
		heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		defense_list.add_child(heading)
		for definition: DefenseDefinition in group_definitions:
			var button := Button.new()
			button.custom_minimum_size = Vector2(0.0, 44.0)
			button.text = ""
			button.tooltip_text = definition.purchase_tooltip
			_apply_menu_row_style(button)
			var row := _create_menu_row(definition.display_name)
			button.add_child(row.container)
			button.pressed.connect(_on_defense_pressed.bind(definition))
			defense_list.add_child(button)
			var definition_index := defense_definitions.find(definition)
			defense_buttons[definition_index] = button
			defense_name_labels[definition_index] = row.name_label
			defense_meta_labels[definition_index] = row.meta_label

func _create_menu_row(name: String) -> Dictionary:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 6)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.text = name
	row.add_child(name_label)
	var meta_label := Label.new()
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_label.add_theme_font_size_override("font_size", 14)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(meta_label)
	return {"container": margin, "name_label": name_label, "meta_label": meta_label}

func _ensure_menu_row_styles() -> void:
	if menu_row_normal != null:
		return
	menu_row_normal = _menu_row_style(Color(0.055, 0.08, 0.105, 0.96), Color(0.12, 0.24, 0.31, 0.85))
	menu_row_hover = _menu_row_style(Color(0.075, 0.14, 0.18, 0.98), Color(0.22, 0.58, 0.72, 0.95))
	menu_row_pressed = _menu_row_style(Color(0.06, 0.22, 0.28, 0.98), Color(0.35, 0.78, 0.88, 1.0))
	menu_row_disabled = _menu_row_style(Color(0.04, 0.055, 0.07, 0.82), Color(0.1, 0.14, 0.17, 0.72))

func _menu_row_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _apply_menu_row_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", menu_row_normal)
	button.add_theme_stylebox_override("hover", menu_row_hover)
	button.add_theme_stylebox_override("pressed", menu_row_pressed)
	button.add_theme_stylebox_override("focus", menu_row_hover)
	button.add_theme_stylebox_override("disabled", menu_row_disabled)

func _catalog_group_for(definition: DefenseDefinition) -> StringName:
	return definition.catalog_group()

func _on_defense_pressed(definition: DefenseDefinition) -> void:
	set_catalog_expanded(false)
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

func _on_city_restoration_pressed() -> void:
	set_city_menu_expanded(false)
	city_restoration_requested.emit()

func _on_sandbox_threat_pressed() -> void:
	var index := sandbox_threat_option.selected
	if index >= 0 and index < threat_definitions.size():
		set_threat_menu_expanded(false)
		sandbox_threat_selected.emit(threat_definitions[index])

func _on_sandbox_threat_option_selected(index: int) -> void:
	if index >= 0 and index < threat_definitions.size():
		set_threat_menu_expanded(false)
		sandbox_threat_selected.emit(threat_definitions[index])

func _on_training_next_pressed() -> void:
	training_next_requested.emit()

func _on_same_seed_pressed() -> void:
	restart_requested.emit(true)

func _on_new_seed_pressed() -> void:
	restart_requested.emit(false)

func _on_game_over_main_menu_pressed() -> void:
	main_menu_requested.emit()
