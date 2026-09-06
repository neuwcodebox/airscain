extends GutTest

const MAIN := preload("res://main/main.tscn")
var main: AirscainMain
var guidance: TrainingGuidance

func before_each() -> void:
	AirscainMain.requested_mode = AirscainMain.GameMode.TRAINING
	AirscainMain.requested_seed = 73129
	main = add_child_autofree(MAIN.instantiate()) as AirscainMain
	AirscainMain.requested_mode = AirscainMain.GameMode.SUSTAINED
	await get_tree().process_frame
	guidance = main.hud.get_node("TrainingGuidance") as TrainingGuidance

func test_menu_cue_follows_open_catalog_and_keeps_clicks_available() -> void:
	main.hud.training_next_button.pressed.emit()
	guidance.refresh()
	assert_same(guidance.target_control, main.hud.defense_menu_button)
	main.hud.set_catalog_expanded(true)
	await get_tree().process_frame
	guidance.refresh()
	assert_same(guidance.target_control, main.hud.defense_buttons[1])
	assert_false(main.hud.training_panel.visible)
	assert_eq(guidance.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_gt(guidance.z_index, main.hud.catalog.z_index)
	main.hud.defense_buttons[1].pressed.emit()
	guidance.refresh()
	assert_true(guidance.suggestion.is_finite())
	assert_true(main.battlefield.placement_result(guidance.suggestion, main.placement.selected.placement_profile).valid)
	assert_null(guidance.target_control)
	assert_true(guidance.world_target)
	assert_true(main.hud.training_panel.visible)
	assert_almost_eq(guidance.target_rect.get_center(), main.camera_rig.camera.unproject_position(guidance.suggestion), Vector2.ONE * 0.01)
	main.placement.cancel()
	guidance.refresh()
	assert_same(guidance.target_control, main.hud.defense_menu_button)

func test_all_purchase_steps_resolve_an_available_catalog_button() -> void:
	for step: int in TrainingGuidance.PLACEMENT_LESSONS:
		main.training_controller._set_step(step as TrainingController.Step)
		main.hud.set_catalog_expanded(true)
		await get_tree().process_frame
		guidance.refresh()
		assert_not_null(guidance.target_control)
		assert_true(main.hud.defense_buttons.has(guidance.target_control))
		assert_true(guidance.target_rect.has_area())

func test_details_are_optional_and_pause_hides_cues() -> void:
	var summary := main.hud.training_body.text
	main.hud._on_training_details_toggled(true)
	assert_eq(main.hud.training_body.text, main.hud.training_description)
	main.hud._on_training_details_toggled(false)
	assert_eq(main.hud.training_body.text, summary)
	main.camera_rig.input_blocked = true
	guidance.refresh()
	assert_false(guidance.target_rect.has_area())
	main.camera_rig.input_blocked = false
	main.training_controller._set_step(TrainingController.Step.COMPLETE)
	guidance.refresh()
	assert_false(guidance.target_rect.has_area())

func test_card_moves_beside_a_tall_selection_panel() -> void:
	main.hud.selected_asset_panel.show()
	main.hud.selected_asset_panel.position = guidance.card_origin
	guidance.refresh()
	assert_false(main.hud.selected_asset_panel.get_global_rect().intersects(main.hud.training_panel.get_global_rect()))
	assert_true(main.hud.training_panel.visible)
