class_name TrainingGuidance
extends Control
## Non-interactive cues follow the real lesson, menu, selection and placement state.

const COLOR := Color(1.0, 0.78, 0.28)
const PLACEMENT_LESSONS := {
	TrainingController.Step.RADAR: &"search_radar",
	TrainingController.Step.WEAPON: &"missile_battery",
	TrainingController.Step.SUPPORT: &"support_facility",
	TrainingController.Step.ALTITUDE: &"tracking_radar",
	TrainingController.Step.ENERGY: &"high_energy_laser",
}

var training: TrainingController
var placement: PlacementController
var rig: CameraRig
var hud: Hud
var target_control: Control
var target_rect: Rect2
var caption: String
var pulse: float = 0.0
var world_target: bool = false
var suggestion := Vector3.INF
var suggestion_step: int = -1
var revealed_button: Control
var label_style := StyleBoxFlat.new()
var card_origin: Vector2

func configure(controller: TrainingController, placement_value: PlacementController, camera_rig: CameraRig) -> void:
	training = controller
	placement = placement_value
	rig = camera_rig
	hud = training.hud
	card_origin = hud.training_panel.position
	hud.overlay_option.get_popup().about_to_popup.connect(_on_overlay_popup)
	label_style.bg_color = Color(0.035, 0.045, 0.055, 0.95)
	label_style.set_corner_radius_all(4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	pulse += delta
	refresh()
	queue_redraw()

func refresh() -> void:
	target_control = null
	target_rect = Rect2()
	caption = ""
	world_target = false
	if hud != null:
		hud.training_panel.position = card_origin
		if hud.selected_asset_panel.is_visible_in_tree() and hud.selected_asset_panel.get_global_rect().intersects(hud.training_panel.get_global_rect()):
			hud.training_panel.position.x = hud.selected_asset_panel.get_global_rect().end.x + 16.0
		var covered := (hud.catalog_expanded and hud.catalog.get_global_rect().intersects(hud.training_panel.get_global_rect())) or (hud.city_menu_expanded and hud.city_menu.get_global_rect().intersects(hud.training_panel.get_global_rect()))
		hud.training_panel.visible = not covered
	if training == null or rig.input_blocked or training.step == TrainingController.Step.NONE:
		return
	if PLACEMENT_LESSONS.has(training.step):
		_placement_cue(PLACEMENT_LESSONS[training.step])
		return
	match training.step:
		TrainingController.Step.COMMAND:
			_asset(training.city_command())
		TrainingController.Step.CAMERA, TrainingController.Step.OPERATIONS:
			_button(hud.training_next_button, "계속")
		TrainingController.Step.SELECT_TRACK:
			_track()
		TrainingController.Step.SELECT_ASSET:
			_asset(training.training_battery)
		TrainingController.Step.TARGET_POLICY:
			if hud.selected_asset != training.training_battery:
				_asset(training.training_battery)
			else:
				_button(hud.target_kind_buttons[4], "로켓 교전 차단")
		TrainingController.Step.DOCTRINE:
			_asset_action(training.training_battery, hud.hold_fire_button, "사격중지 해제")
		TrainingController.Step.RESUPPLY:
			_asset_action(training.training_battery, hud.resupply_button, "재보급 요청")
		TrainingController.Step.REPAIR:
			_asset_action(training.training_battery, hud.repair_button, "수리 요청")
		TrainingController.Step.CITY_RESTORE:
			_button(hud.city_restoration_button if hud.city_menu_expanded else hud.city_menu_button, "피해 복구" if hud.city_menu_expanded else "도시 관리")
		TrainingController.Step.OVERLAY:
			_button(hud.overlay_option, "지휘 연결 선택")
		TrainingController.Step.ENERGY_REVIEW:
			if training.energy_reviewed:
				_button(hud.training_next_button, "확인 후 계속")
			else:
				_asset(training.energy_subject)
		TrainingController.Step.RELOCATE:
			if placement.relocating_unit == training.relocation_subject and placement.selected != null:
				_placement_destination(placement.selected)
			else:
				_asset_action(training.relocation_subject, hud.relocation_button, "재배치 위치 지정")
		TrainingController.Step.ACQUIRE, TrainingController.Step.ENGAGE:
			_button(hud.normal_button, "관찰 중 · 자동 진행")
		TrainingController.Step.WAIT_RESUPPLY, TrainingController.Step.WAIT_REPAIR, TrainingController.Step.WAIT_RELOCATE:
			_button(hud.very_fast_button, "완료 대기 · 4×")

func _button(control: Control, text: String) -> void:
	# Menus remain the input owners; never draw a cue for a covered control.
	if hud.catalog_expanded and control != hud.defense_menu_button and not hud.catalog.is_ancestor_of(control):
		control = hud.defense_menu_button
		text = "메뉴 닫기"
	elif hud.city_menu_expanded and control != hud.city_menu_button and not hud.city_menu.is_ancestor_of(control):
		control = hud.city_menu_button
		text = "메뉴 닫기"
	if not control.is_visible_in_tree():
		return
	target_control = control
	target_rect = control.get_global_rect().grow(4.0)
	caption = text

func _asset_action(unit: DefenseUnit, button: Control, text: String) -> void:
	if hud.selected_asset == unit and button.is_visible_in_tree():
		_button(button, text)
	else:
		_asset(unit)

func _asset(unit: DefenseUnit) -> void:
	if not is_instance_valid(unit):
		return
	_point(unit.global_position + Vector3.UP * 8.0, "선택")
	if unit.pointer_target != null and not rig.camera.is_position_behind(unit.global_position):
		var rect := unit.pointer_target.screen_rect(unit, rig.camera).grow(10.0)
		if get_viewport_rect().encloses(rect):
			target_rect = rect
	_avoid_world_menu()

func _track() -> void:
	var overlay := training.tactical_screen_overlay as TacticalScreenOverlay
	for track: PlayerTrack in overlay.player_knowledge.call("get_active_tracks"):
		if track.state == PlayerTrack.State.CONFIRMED and track.affiliation == PlayerTrack.Affiliation.HOSTILE:
			var point := overlay.track_marker_screen_position(track)
			target_rect = Rect2(point - Vector2.ONE * 22.0, Vector2.ONE * 44.0)
			caption = "항적 선택"
			world_target = true
			_avoid_world_menu()
			return

func _placement_cue(id: StringName) -> void:
	if placement.selected != null and placement.selected.id == id:
		_placement_destination(placement.selected)
		return
	if placement.selected != null:
		target_rect = Rect2(get_viewport().get_mouse_position() - Vector2.ONE * 16, Vector2.ONE * 32)
		caption = "우클릭 · 배치 취소"
		return
	if not hud.catalog_expanded:
		revealed_button = null
		_button(hud.defense_menu_button, "방공 자산 열기")
		return
	for index: int in hud.defense_definitions.size():
		if hud.defense_definitions[index].id != id:
			continue
		var button := hud.defense_buttons[index]
		if revealed_button != button:
			hud.defense_scroll.ensure_control_visible(button)
			revealed_button = button
		_button(button, "선택")
		target_rect = target_rect.intersection(hud.defense_scroll.get_global_rect())
		if not target_rect.has_area():
			_button(hud.defense_scroll, "목록 스크롤")
		return

func _placement_destination(definition: DefenseDefinition) -> void:
	if suggestion.is_finite() and not training.battlefield.placement_result(suggestion, definition.placement_profile).valid:
		suggestion_step = -1
	if suggestion_step != int(training.step):
		suggestion_step = int(training.step)
		suggestion = _find_suggestion(definition)
	if suggestion.is_finite():
		_point(suggestion, "추천 위치")
	else:
		target_rect = Rect2(get_viewport().get_mouse_position() - Vector2.ONE * 20, Vector2.ONE * 40)
		caption = "초록색 위치에 배치"
	_avoid_world_menu()

func _find_suggestion(definition: DefenseDefinition) -> Vector3:
	var near := Vector3(300, 0, 0)
	if is_instance_valid(training.training_battery):
		near = training.training_battery.global_position + Vector3(0, 0, 65)
	if training.step == TrainingController.Step.WEAPON:
		for unit: DefenseUnit in training.defenses:
			if unit.definition.id == &"search_radar":
				near = unit.global_position + Vector3(-60, 0, 45)
	if training.step == TrainingController.Step.RELOCATE and is_instance_valid(training.relocation_subject):
		near = training.relocation_subject.global_position + Vector3(65, 0, 40)
	for index: int in 120:
		var candidate := near + Vector3(cos(index * 0.8), 0, sin(index * 0.8)) * float(index * 2)
		candidate.y = training.battlefield.terrain_height(candidate.x, candidate.z)
		candidate = training.battlefield.snap_placement_position(candidate, definition.placement_profile)
		if not training.battlefield.placement_result(candidate, definition.placement_profile).valid:
			continue
		if training.step == TrainingController.Step.WEAPON:
			if not training.c2_network.placement_preview(definition, candidate).ready:
				continue
		if training.step == TrainingController.Step.SUPPORT and is_instance_valid(training.training_battery):
			# Use the definition's support radius, not a separate tutorial rule.
			if candidate.distance_to(training.training_battery.global_position) > definition.placement_support_range():
				continue
		return candidate
	return Vector3.INF

func _point(position: Vector3, text: String) -> void:
	var projected := rig.camera.unproject_position(position)
	var safe := Rect2(Vector2(28, 110), get_viewport_rect().size - Vector2(56, 190))
	var behind := rig.camera.is_position_behind(position)
	var on_screen := not behind and safe.has_point(projected)
	var point := projected if on_screen else TacticalScreenOverlay.marker_position_in_safe_area(projected, get_viewport_rect().size, behind, 28, 110, 28, 80)
	target_rect = Rect2(point - Vector2.ONE * 22, Vector2.ONE * 44)
	caption = text if on_screen else "이쪽으로 이동 · WASD"
	world_target = true

func _avoid_world_menu() -> void:
	if hud.catalog_expanded:
		world_target = false
		_button(hud.defense_menu_button, "메뉴 닫기")
	elif hud.city_menu_expanded:
		world_target = false
		_button(hud.city_menu_button, "메뉴 닫기")

func _draw() -> void:
	if not target_rect.has_area():
		return
	var color := COLOR
	color.a = 0.75 + sin(pulse * 4.0) * 0.2
	draw_rect(target_rect.grow(3.0), Color(0.02, 0.03, 0.04, 0.9), false, 5.0)
	draw_rect(target_rect, color, false, 2.0)
	if world_target:
		draw_arc(target_rect.get_center(), maxf(target_rect.size.x, target_rect.size.y) * 0.5 + 5.0 + sin(pulse * 4.0) * 2.0, 0, TAU, 48, color, 2, true)
	if target_control is Button and hud.defense_buttons.has(target_control):
		var tip := Vector2(target_rect.position.x - 1, target_rect.get_center().y)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9, -6), tip + Vector2(-9, 6)]), COLOR)
		return
	var font := get_theme_default_font()
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var label_size := text_size + Vector2(18, 10)
	var position := Vector2(target_rect.get_center().x - label_size.x * 0.5, target_rect.end.y + 10)
	if world_target and hud.placement_hint_panel.visible and hud.placement_hint_panel.get_global_rect().intersects(Rect2(position, label_size)):
		position.x = target_rect.position.x - label_size.x - 12
	if position.y + label_size.y > get_viewport_rect().size.y - 12:
		position.y = target_rect.position.y - label_size.y - 10
	position.x = clampf(position.x, 12, get_viewport_rect().size.x - label_size.x - 12)
	if hud.overlay_option.get_popup().visible:
		return
	draw_style_box(label_style, Rect2(position, label_size))
	draw_string(font, position + Vector2(9, 5 + font.get_ascent(15)), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR)

func _on_overlay_popup() -> void:
	if training.step == TrainingController.Step.OVERLAY:
		_focus_overlay_target.call_deferred()

func _focus_overlay_target() -> void:
	var popup := hud.overlay_option.get_popup()
	if popup.visible and training.step == TrainingController.Step.OVERLAY:
		popup.set_focused_item(Hud.OVERLAY_MODES.find(&"c2"))
