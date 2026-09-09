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

func test_full_lesson_is_visible_and_pause_hides_cues() -> void:
	assert_eq(main.hud.training_body.text, main.hud.training_description)
	assert_null(main.hud.training_panel.get_node_or_null("VBox/TrainingDetailsButton"))
	main.hud.set_training_lesson(2, 3, "안내", "첫 문장. 두 번째 문장도 표시합니다.")
	assert_eq(main.hud.training_body.text, "첫 문장. 두 번째 문장도 표시합니다.")
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

func test_observation_steps_do_not_prompt_time_control_clicks() -> void:
	for step: TrainingController.Step in [TrainingController.Step.ACQUIRE, TrainingController.Step.ENGAGE, TrainingController.Step.WAIT_RESUPPLY, TrainingController.Step.WAIT_REPAIR, TrainingController.Step.WAIT_RELOCATE]:
		main.training_controller._set_step(step)
		guidance.refresh()
		assert_false(guidance.target_rect.has_area())
		assert_eq(main.session.simulation_speed, 1.0)

func test_track_selection_rejects_unconfirmed_and_non_hostile_contacts() -> void:
	var track := PlayerTrack.new()
	main.training_controller._set_step(TrainingController.Step.SELECT_TRACK)
	main.training_controller.track_selected(track)
	assert_eq(main.training_controller.step, TrainingController.Step.SELECT_TRACK)
	track.state = PlayerTrack.State.CONFIRMED
	track.affiliation = PlayerTrack.Affiliation.FRIENDLY
	track.affiliation_confidence = 1.0
	main.training_controller.track_selected(track)
	assert_eq(main.training_controller.step, TrainingController.Step.SELECT_TRACK)
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	main.training_controller.track_selected(track)
	assert_eq(main.training_controller.step, TrainingController.Step.DOCTRINE)

func test_terrain_obstruction_requires_relocation_then_returns_to_detection() -> void:
	main.training_controller.next_requested()
	guidance.refresh()
	main.placement.select(main.scenario.available_defenses[1])
	guidance.refresh()
	main.placement.candidate_position = guidance.suggestion
	assert_true(main.placement.request_selected_defense_placement())
	var radar := main.defenses.back() as SearchRadar
	main.placement.select(main.scenario.available_defenses[0])
	guidance.refresh()
	main.placement.candidate_position = guidance.suggestion
	assert_true(main.placement.request_selected_defense_placement())
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE)
	main.training_controller.tracks_refreshed(0)
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE, "사거리 밖 표적에 사각 해결을 요구하지 않습니다")
	var threat := main.registry.get_hostile_active()[0]
	var blocked := Vector3.INF
	for index: int in 720:
		var candidate := radar.global_position + Vector3(cos(index * 0.2), 0, sin(index * 0.2)) * (100.0 + float(index % 12) * 45.0)
		candidate.y = main.battlefield.terrain_height(candidate.x, candidate.z) + 3.0
		if not radar._has_line_of_sight(radar.global_position + Vector3.UP * 11.0, candidate):
			blocked = candidate
			break
	assert_true(blocked.is_finite())
	threat.global_position = blocked
	main.training_controller.tracks_refreshed(0)
	assert_eq(main.training_controller.step, TrainingController.Step.RELOCATE)
	assert_eq(main.session.simulation_speed, 0.0)
	assert_same(main.training_controller.relocation_subject, radar)
	main._on_asset_selected(radar)
	main.hud.relocation_button.pressed.emit()
	guidance.refresh()
	assert_true(guidance.suggestion.is_finite())
	assert_true(radar._has_line_of_sight(guidance.suggestion + Vector3.UP * 11.0, threat.get_aim_position()))
	main.placement.candidate_position = guidance.suggestion
	assert_true(main.placement.request_selected_defense_placement())
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RELOCATE)
	main.relocation_manager.gameplay_tick(radar.definition.relocation_duration + 0.1)
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE)
	assert_eq(main.session.simulation_speed, 1.0)
