extends GutTest

const MAIN := preload("res://main/main.tscn")
var main: AirscainMain
var guidance: TrainingGuidance
var original_requested_seed: int
var original_requested_mode: AirscainMain.GameMode
var original_requested_layout_id: StringName
var original_last_generated_seed: int

func before_each() -> void:
	original_requested_seed = AirscainMain.requested_seed
	original_requested_mode = AirscainMain.requested_mode
	original_requested_layout_id = AirscainMain.requested_layout_id
	original_last_generated_seed = AirscainMain.last_generated_seed
	AirscainMain.requested_mode = AirscainMain.GameMode.TRAINING
	AirscainMain.requested_seed = 73129
	AirscainMain.requested_layout_id = &""
	main = add_child_autofree(MAIN.instantiate()) as AirscainMain
	AirscainMain.requested_mode = original_requested_mode
	await get_tree().process_frame
	guidance = main.hud.get_node("TrainingGuidance") as TrainingGuidance

func after_each() -> void:
	AirscainMain.requested_seed = original_requested_seed
	AirscainMain.requested_mode = original_requested_mode
	AirscainMain.requested_layout_id = original_requested_layout_id
	AirscainMain.last_generated_seed = original_last_generated_seed

func test_menu_cue_follows_open_catalog_and_keeps_clicks_available() -> void:
	main.hud.training_next_button.pressed.emit()
	guidance.refresh()
	assert_same(guidance.target_control, main.hud.defense_menu_button)
	main.hud.set_catalog_expanded(true)
	await get_tree().process_frame
	guidance.refresh()
	assert_same(guidance.target_control, _catalog_button(&"search_radar"))
	assert_false(main.hud.training_panel.visible)
	assert_eq(guidance.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_gt(guidance.z_index, main.hud.catalog.z_index)
	_catalog_button(&"search_radar").pressed.emit()
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
	assert_eq(main.training_controller.step, TrainingController.Step.ENGAGE)

func test_terrain_obstruction_requires_relocation_then_returns_to_detection() -> void:
	main.training_controller.next_requested()
	guidance.refresh()
	var existing_defense_ids := _defense_runtime_ids()
	main.placement.select(_defense_definition(&"search_radar"))
	guidance.refresh()
	main.placement.candidate_position = guidance.suggestion
	assert_true(main.placement.request_selected_defense_placement())
	var radar := _new_defense_since(existing_defense_ids, &"search_radar") as SearchRadar
	assert_not_null(radar)
	if radar == null:
		return
	main.placement.select(_defense_definition(&"missile_battery"))
	guidance.refresh()
	main.placement.candidate_position = guidance.suggestion
	assert_true(main.placement.request_selected_defense_placement())
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE)
	main.training_controller.tracks_refreshed(0)
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE, "시야가 트인 표적에 사각 해결을 요구하지 않습니다")
	var threat := _training_threat()
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
	main.placement.asset_selected.emit(radar)
	main.hud.relocation_button.pressed.emit()
	guidance.refresh()
	assert_true(guidance.suggestion.is_finite())
	assert_true(radar._has_line_of_sight(guidance.suggestion + Vector3.UP * 11.0, threat.get_aim_position()))
	main.placement.candidate_position = guidance.suggestion
	var relocation_duration := main.relocation_manager.estimated_duration(radar, guidance.suggestion)
	assert_true(main.placement.request_selected_defense_placement())
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RELOCATE)
	main.relocation_manager.gameplay_tick(relocation_duration + 0.1)
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE)
	assert_eq(main.session.simulation_speed, 1.0)

func test_recommended_deployment_confirms_contact_within_ten_seconds() -> void:
	main.training_controller.next_requested()
	for definition_id: StringName in [&"search_radar", &"missile_battery"]:
		main.placement.select(_defense_definition(definition_id))
		guidance.refresh()
		main.placement.candidate_position = guidance.suggestion
		assert_true(main.placement.request_selected_defense_placement())
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE)
	for tick: int in 100:
		main._process(0.1)
		if main.training_controller.step == TrainingController.Step.SELECT_TRACK:
			break
	assert_eq(main.training_controller.step, TrainingController.Step.SELECT_TRACK)
	assert_eq(main.session.simulation_speed, 0.0)
	assert_false(main.training_controller.training_battery.doctrine.hold_fire)

func _defense_definition(definition_id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id == definition_id:
			return definition
	fail_test("방어 자산 정의를 찾지 못했습니다: %s" % definition_id)
	return null

func _defense_runtime_ids() -> Dictionary[int, bool]:
	var ids: Dictionary[int, bool] = {}
	for unit: DefenseUnit in main.defenses:
		ids[unit.runtime_id] = true
	return ids

func _new_defense_since(existing_ids: Dictionary[int, bool], definition_id: StringName) -> DefenseUnit:
	for unit: DefenseUnit in main.defenses:
		if not existing_ids.has(unit.runtime_id) and unit.definition.id == definition_id:
			return unit
	fail_test("새로 배치한 방어 자산을 찾지 못했습니다: %s" % definition_id)
	return null

func _training_threat() -> ThreatUnit:
	for threat: ThreatUnit in main.registry.get_hostile_active():
		if threat.runtime_id == main.training_controller.training_threat_runtime_id:
			return threat
	fail_test("훈련 표적을 찾지 못했습니다: %d" % main.training_controller.training_threat_runtime_id)
	return null

func _catalog_button(definition_id: StringName) -> Button:
	var definition := _defense_definition(definition_id)
	var index := main.scenario.available_defenses.find(definition)
	if index >= 0 and index < main.hud.defense_buttons.size():
		return main.hud.defense_buttons[index]
	fail_test("방어 자산 카탈로그 버튼을 찾지 못했습니다: %s" % definition_id)
	return null

func test_training_mode_starts_paused_with_guidance_and_disables_saves() -> void:
	assert_eq(main.game_mode, AirscainMain.GameMode.TRAINING)
	assert_eq(main.training_controller.step, TrainingController.Step.CAMERA)
	assert_eq(main.session.phase, GameSession.Phase.RUNNING)
	assert_false(main.hud.start_button.visible)
	assert_false(main.hud.feedback_label.text.contains("방어를 시작"))
	assert_eq(main.session.simulation_speed, 0.0)
	assert_eq(main.registry.hostile_count(), 1)
	var initial_threat := _training_threat()
	assert_not_null(initial_threat)
	if initial_threat == null:
		return
	var initial_position := initial_threat.global_position
	main._process(5.0)
	assert_eq(main.session.survival_time, 0.0)
	assert_eq(initial_threat.global_position, initial_position)
	assert_true(main.hud.training_panel.visible)
	assert_string_contains(main.hud.training_title.text, "1/%d" % TrainingController.LESSON_COUNT)
	assert_string_contains(main.hud.training_body.text, "WASD")
	assert_string_contains(main.hud.training_body.text, "가운데 버튼 드래그")
	assert_string_contains(main.hud.training_body.text, "수평, 수직 회전")
	assert_string_contains(main.hud.training_body.text, "Backspace")
	assert_null(main.hud.get_node_or_null("%SaveButton"))
	assert_null(main.hud.get_node_or_null("%LoadButton"))
	assert_eq(main.save_operation(), "저장은 지속 작전에서만 사용할 수 있습니다")


func test_training_approach_marker_stays_readable_across_layout_and_rotation() -> void:
	var initial_threat := _training_threat()
	assert_not_null(initial_threat)
	if initial_threat == null:
		return
	assert_true(main.tactical_screen_overlay.training_approach_visible)
	var approach_position := main.tactical_screen_overlay.training_approach_position
	assert_gt(approach_position.x, main.objective.global_position.x)
	assert_eq(initial_threat.global_position, approach_position)
	var approach_marker := main.tactical_screen_overlay.training_marker_screen_position()
	assert_lte(approach_marker.x, main.tactical_screen_overlay.size.x - TacticalScreenOverlay.EDGE_MARGIN)
	assert_gte(approach_marker.y, 100.0)
	var approach_label_rect := main.tactical_screen_overlay.training_approach_label_rect()
	assert_false(approach_label_rect.intersects(main.hud.training_panel.get_global_rect()))
	main.hud.set_catalog_expanded(true)
	await get_tree().process_frame
	var marker_with_catalog := main.tactical_screen_overlay.training_marker_screen_position()
	assert_almost_eq(marker_with_catalog.x, approach_marker.x, 0.001)
	assert_almost_eq(marker_with_catalog.y, approach_marker.y, 0.001)
	main.hud.set_catalog_expanded(false)
	assert_eq(main.tactical_screen_overlay.training_approach_label_text(), "훈련 표적 진입")
	main.camera_rig.yaw_radians += PI * 0.5
	main.camera_rig._update_camera()
	var rotated_marker := main.tactical_screen_overlay.training_marker_screen_position()
	assert_lte(rotated_marker.x, main.tactical_screen_overlay.size.x - TacticalScreenOverlay.EDGE_MARGIN)
	assert_gte(rotated_marker.y, 100.0)
	main.camera_rig.yaw_radians -= PI * 0.5
	main.camera_rig._update_camera()


func test_training_lesson_progresses_through_deployment_support_and_recovery() -> void:
	var approach_position := main.tactical_screen_overlay.training_approach_position
	main.hud.training_next_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.RADAR, "1. 카메라 안내를 마치면 레이더 배치로 이동합니다")
	var radar_result := _place_available_defense(&"search_radar")
	assert_true(radar_result.success, "2. 추천 위치에 탐색 레이더를 배치합니다")
	assert_eq(main.training_controller.step, TrainingController.Step.WEAPON, "2. 레이더 배치 후 무장 배치로 이동합니다")
	var training_radar := radar_result.unit as DefenseUnit
	training_radar.active = false
	var battery_result := _place_available_defense(&"missile_battery")
	assert_true(battery_result.success, "3. 추천 위치에 미사일 포대를 배치합니다")
	var battery := battery_result.unit as MissileBattery
	assert_false(battery.doctrine.hold_fire)
	assert_eq(main.training_controller.step, TrainingController.Step.CONNECT, "3. 무장 배치 후 연결 확인으로 이동합니다")
	main.training_controller.tracks_refreshed(0)
	assert_eq(main.training_controller.step, TrainingController.Step.CONNECT)
	assert_eq(main.session.simulation_speed, 0.0)
	training_radar.active = true
	var hostile_count := main.registry.hostile_count()
	main.training_controller.tracks_refreshed(0)
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE, "4. 센서 연결 후 표적 탐지로 이동합니다")
	assert_false(main.tactical_screen_overlay.training_approach_visible)
	assert_false(main.hud.catalog_expanded)
	assert_false(main.director.enabled)
	assert_eq(main.registry.hostile_count(), hostile_count)
	var threat := _training_threat()
	assert_not_null(threat)
	if threat == null:
		return
	assert_eq(threat.global_position, approach_position)
	assert_eq(main.session.simulation_speed, 1.0)
	var observation := SensorObservation.new()
	observation.setup((radar_result.unit as DefenseUnit).runtime_id, 0.0, threat.global_position, 0.95, 4.0, 0.4, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.8)
	var track := main.player_knowledge.submit_observation(observation)
	main._refresh_tactical_ui()
	assert_eq(track.state, PlayerTrack.State.TENTATIVE)
	assert_eq(main.training_controller.step, TrainingController.Step.ACQUIRE)
	assert_eq(main.session.simulation_speed, 1.0)
	observation = SensorObservation.new()
	observation.setup((radar_result.unit as DefenseUnit).runtime_id, 0.1, threat.global_position, 0.95, 4.0, 0.4, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.8)
	track = main.player_knowledge.submit_observation(observation)
	main._refresh_tactical_ui()
	assert_eq(track.state, PlayerTrack.State.CONFIRMED)
	assert_eq(main.training_controller.step, TrainingController.Step.SELECT_TRACK, "5. 두 관측으로 항적이 확인되면 선택 단계로 이동합니다")
	assert_eq(main.session.simulation_speed, 0.0)
	assert_false(main.tactical_screen_overlay.training_approach_visible)
	var distant_track_marker := main.tactical_screen_overlay.track_marker_screen_position(track)
	assert_true(distant_track_marker.is_finite())
	main.placement.world_selected.emit(Vector3.INF, distant_track_marker)
	assert_same(main.selected_track, track)
	assert_eq(main.training_controller.step, TrainingController.Step.ENGAGE, "6. 확인된 적성 항적을 선택하면 교전 단계로 이동합니다")
	assert_eq(main.session.simulation_speed, 1.0)
	assert_true(threat.resolve_once(true))
	assert_eq(main.training_controller.step, TrainingController.Step.SUPPLY_STATUS, "7. 표적 무력화 후 탄약 상태 확인으로 이동합니다")
	assert_eq(battery.critical_status_text(), "재보급 대기")
	main.support_manager.gameplay_tick(2.0)
	assert_true(main.support_manager.tasks.is_empty())
	assert_eq(main.training_controller.step, TrainingController.Step.SUPPLY_STATUS)
	main.hud.training_next_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.SUPPORT, "8. 탄약 안내를 확인하면 지원 시설 배치로 이동합니다")
	assert_false(main.hud.catalog_expanded)
	assert_true(main.hud.training_panel.visible)
	assert_string_contains(main.hud.training_body.text, "방공 자산을 열어")
	assert_eq(main.session.simulation_speed, 1.0)
	main.hud.set_catalog_expanded(true)
	assert_true(_place_available_defense(&"support_facility").success, "9. 지원 시설을 배치합니다")
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RESUPPLY, "9. 지원 시설 배치 후 재보급 완료를 기다립니다")
	assert_eq(battery.magazine.reserve, 0)
	assert_null(main.selected_asset)
	main.placement.asset_selected.emit(battery)
	assert_true(battery.automatic_resupply_enabled())
	main.support_manager.gameplay_tick(1.0)
	assert_false(bool(main.support_manager.tasks[0].user_requested))
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RESUPPLY)
	assert_eq(main.session.simulation_speed, 1.0)
	assert_eq(main.support_manager.tasks.size(), 1)
	main.hud.training_next_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RESUPPLY, "보급 완료 전에 다른 조작으로 건너뛰지 않습니다")
	var supply_description := main.hud.training_body.text
	main.support_manager.gameplay_tick(100.0)
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RESUPPLY)
	assert_string_contains(main.hud.training_body.text, supply_description)
	assert_true(main.hud.training_next_button.visible)
	assert_eq(battery.integrity, battery.definition.maximum_integrity)
	main._process(10.0)
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_RESUPPLY)
	main.hud.training_next_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.REPAIR, "10. 재보급 확인 후 수리 단계로 이동합니다")
	assert_eq(main.session.simulation_speed, 1.0)
	assert_gt(battery.magazine.reserve, 0)
	assert_lt(battery.integrity, battery.definition.maximum_integrity)
	main.placement.asset_selected.emit(battery)
	assert_false(main.hud.repair_button.disabled)
	main.hud.repair_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_REPAIR, "11. 수리를 요청하면 완료를 기다립니다")
	assert_eq(main.support_manager.task_detail_status(battery), "수리 진행 · 3.0초")
	main.hud.training_next_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_REPAIR)
	var repair_description := main.hud.training_body.text
	main.support_manager.gameplay_tick(2.9)
	assert_lt(battery.integrity, battery.definition.maximum_integrity)
	main.support_manager.gameplay_tick(0.2)
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_REPAIR)
	assert_string_contains(main.hud.training_body.text, repair_description)
	assert_true(main.hud.training_next_button.visible)
	main._process(10.0)
	assert_eq(main.training_controller.step, TrainingController.Step.WAIT_REPAIR)
	main.hud.training_next_button.pressed.emit()
	assert_eq(main.training_controller.step, TrainingController.Step.CITY_RESTORE, "12. 자산 수리 확인 후 도시 복구로 이동합니다")
	assert_eq(battery.integrity, battery.definition.maximum_integrity)
	assert_lt(main.objective.current_integrity, main.objective.definition.maximum_integrity)
	var budget_before_restore := main.session.budget
	main.hud.city_restoration_button.pressed.emit()
	assert_eq(main.session.budget, budget_before_restore - main.objective.definition.restoration_cost)
	assert_eq(main.training_controller.step, TrainingController.Step.COMPLETE, "13. 도시 복구로 전체 훈련을 완료합니다")
	assert_string_contains(main.hud.training_title.text, "훈련 완료")
	assert_eq(main.session.simulation_speed, 1.0)

func _place_available_defense(definition_id: StringName) -> Dictionary:
	var definition := _defense_definition(definition_id)
	if definition == null:
		return {"success": false, "reason": "방어 자산 정의 없음"}
	for z: int in range(-420, 421, 30):
		for x: int in range(-420, 421, 30):
			var position := Vector3(float(x), main.battlefield.terrain_height(float(x), float(z)), float(z))
			if main.battlefield.placement_result(position, definition.placement_profile).valid:
				return main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
	return {"success": false, "reason": "테스트 배치 위치 없음"}
