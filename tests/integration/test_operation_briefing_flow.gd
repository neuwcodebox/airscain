extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")

var original_requested_mode: AirscainMain.GameMode
var original_briefings: bool

func before_each() -> void:
	original_requested_mode = AirscainMain.requested_mode
	original_briefings = bool(PlayerSettings.instance().values.briefings)
	PlayerSettings.instance().values.briefings = true

func after_each() -> void:
	AirscainMain.requested_mode = original_requested_mode
	PlayerSettings.instance().values.briefings = original_briefings

func test_new_operation_opens_the_first_phase_paused_until_acknowledged() -> void:
	var operation := _new_operation(AirscainMain.GameMode.SUSTAINED)
	assert_true(operation.briefing_panel.visible)
	assert_eq(operation.briefing_panel.current_briefing().id, &"operation_start")
	assert_eq(operation.session.simulation_speed, 0.0)
	assert_true(operation.camera_rig.input_blocked)
	operation.briefing_panel.acknowledge_button.pressed.emit()
	assert_false(operation.briefing_panel.visible)
	assert_eq(operation.session.simulation_speed, 1.0)
	assert_false(operation.camera_rig.input_blocked)

func test_reaching_a_new_phase_pauses_on_its_briefing_and_escape_restores_speed() -> void:
	var operation := _acknowledged_operation()
	operation.session.set_simulation_speed(2.0)
	operation.director.pressure_changed.emit(2)
	assert_true(operation.briefing_panel.visible)
	assert_eq(operation.briefing_panel.current_briefing().id, &"recon_and_swarms")
	assert_eq(operation.session.simulation_speed, 0.0)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	operation.briefing_panel._input(escape)
	assert_false(operation.briefing_panel.visible)
	assert_eq(operation.session.simulation_speed, 2.0)

func test_briefing_lists_the_threats_and_assets_of_its_phase() -> void:
	var operation := _acknowledged_operation()
	operation.director.pressure_changed.emit(3)
	var briefing := operation.briefing_panel.current_briefing()
	assert_eq(briefing.id, &"cruise_and_jamming")
	assert_eq(operation.briefing_panel.threat_list.get_child_count(), operation.scenario.briefing_threats(briefing).size())
	assert_eq(operation.briefing_panel.asset_list.get_child_count(), operation.scenario.briefing_defenses(briefing).size())
	assert_true(operation.briefing_panel.deploy_button.visible)

func test_deploy_opens_the_catalog_with_only_new_assets_highlighted_until_closed() -> void:
	var operation := _acknowledged_operation()
	operation.director.pressure_changed.emit(2)
	operation.briefing_panel.deploy_button.pressed.emit()
	assert_false(operation.briefing_panel.visible)
	assert_true(operation.hud.catalog_expanded)
	for index: int in operation.hud.defense_definitions.size():
		var definition := operation.hud.defense_definitions[index]
		assert_eq(operation.hud.defense_new_badges[index].visible, definition.id == &"high_energy_laser", String(definition.id))
	operation.hud.set_catalog_expanded(false)
	for badge: Label in operation.hud.defense_new_badges:
		assert_false(badge.visible)

func test_disabled_briefings_are_recorded_without_pausing() -> void:
	var operation := _acknowledged_operation()
	PlayerSettings.instance().values.briefings = false
	operation.director.pressure_changed.emit(2)
	assert_false(operation.briefing_panel.visible)
	assert_eq(operation.session.simulation_speed, 1.0)
	assert_true(operation.briefing_controller.delivered_ids.has(&"recon_and_swarms"))
	assert_string_contains(operation.hud.feedback_label.text, "정찰과 군집")

func test_saved_operation_keeps_delivered_briefings_without_reopening_them() -> void:
	var operation := _acknowledged_operation()
	operation.director.pressure_changed.emit(2)
	operation.briefing_panel.close()
	var document := SaveDocument.decode(SaveDocument.encode(operation.capture_save_document()))
	operation.briefing_controller.delivered_ids.clear()
	assert_eq(operation.restore_from_document(document), "")
	assert_eq(operation.briefing_controller.delivered_ids, [&"operation_start", &"recon_and_swarms"] as Array[StringName])
	assert_false(operation.briefing_panel.visible)

func test_legacy_save_treats_reached_phases_as_delivered() -> void:
	var operation := _acknowledged_operation()
	var legacy := SaveDocument.decode(SaveDocument.encode(operation.capture_save_document()))
	legacy.version = 31
	legacy.payload.erase("briefings")
	legacy.payload.session.current_pressure = 3
	legacy.payload.director.pressure_level = 3
	assert_eq(operation.restore_from_document(legacy), "")
	assert_eq(operation.briefing_controller.delivered_ids, [&"operation_start", &"recon_and_swarms", &"cruise_and_jamming"] as Array[StringName])
	assert_false(operation.briefing_panel.visible)
	assert_eq(operation.session.simulation_speed, 1.0)

func test_training_and_sandbox_never_show_phase_briefings() -> void:
	for mode: AirscainMain.GameMode in [AirscainMain.GameMode.TRAINING, AirscainMain.GameMode.SANDBOX]:
		var operation := _new_operation(mode)
		operation.director.pressure_changed.emit(3)
		assert_null(operation.briefing_panel, "mode %d" % mode)
		assert_true(operation.briefing_controller.delivered_ids.is_empty(), "mode %d" % mode)

func _new_operation(mode: AirscainMain.GameMode) -> AirscainMain:
	AirscainMain.requested_mode = mode
	var operation := MAIN_SCENE.instantiate() as AirscainMain
	add_child_autofree(operation)
	operation.set_process(false)
	return operation

func _acknowledged_operation() -> AirscainMain:
	var operation := _new_operation(AirscainMain.GameMode.SUSTAINED)
	operation.briefing_panel.close()
	return operation
