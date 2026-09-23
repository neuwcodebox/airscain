class_name TacticalScreenOverlay
extends Control

const EDGE_MARGIN := 20.0

var camera: Camera3D
var player_knowledge: PlayerKnowledge
var selected_track_id: int = -1
var training_approach_visible: bool = false
var training_approach_origin: Vector3
var training_approach_position: Vector3
var training_approach_text: String = "훈련 표적 진입"
var training_left_panel: Control
var placement: PlacementController
var harbor_port: HarborPort
var hovered_track: PlayerTrack
var pointer_hint := PanelContainer.new()
var pointer_label := Label.new()
var hint_icon := TextureRect.new()
var hint_separator := HSeparator.new()
var hint_details := VBoxContainer.new()
var hint_rows: Array[Label] = []
var instability_time: float = 0.0

func _ready() -> void:
	pointer_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer_label.add_theme_font_size_override("font_size", 18)
	pointer_label.add_theme_color_override("font_color", Color("edf5f8"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.08, 0.96)
	style.border_color = Color("41616d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	pointer_hint.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 7)
	pointer_hint.add_child(content)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 8)
	content.add_child(heading)
	hint_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_icon.custom_minimum_size = Vector2(24, 24)
	hint_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hint_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hint_icon.modulate = Color("a7cbd9")
	heading.add_child(hint_icon)
	heading.add_child(pointer_label)
	hint_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := StyleBoxLine.new()
	rule.color = Color("304650")
	rule.thickness = 1
	hint_separator.add_theme_stylebox_override("separator", rule)
	content.add_child(hint_separator)
	hint_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_details.add_theme_constant_override("separation", 4)
	content.add_child(hint_details)
	for index: int in 4:
		var row := Label.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_size_override("font_size", 14)
		hint_details.add_child(row)
		hint_rows.append(row)
	add_child(pointer_hint)
	pointer_hint.hide()

func track_at_screen(point: Vector2) -> PlayerTrack:
	var nearest: PlayerTrack
	var distance := 34.0
	for track: PlayerTrack in player_knowledge.get_active_tracks():
		if not _unstable_track_visible(track):
			continue
		var screen := track_marker_screen_position(track)
		if screen.is_finite() and screen.distance_to(point) < distance:
			distance = screen.distance_to(point)
			nearest = track
	return nearest

func configure(camera_value: Camera3D, knowledge: PlayerKnowledge, left_panel: Control = null) -> void:
	camera = camera_value
	player_knowledge = knowledge
	training_left_panel = left_panel
	queue_redraw()

func select_track(track: PlayerTrack) -> void:
	selected_track_id = track.track_id if track != null else -1
	queue_redraw()

func show_training_approach(origin: Vector3, approach_position: Vector3, text: String = "훈련 표적 진입") -> void:
	training_approach_origin = origin
	training_approach_position = approach_position
	training_approach_text = text
	training_approach_visible = true
	queue_redraw()

func hide_training_approach() -> void:
	training_approach_visible = false
	queue_redraw()

func _process(delta: float) -> void:
	instability_time += delta
	hovered_track = null
	pointer_hint.hide()
	var mouse := get_viewport().get_mouse_position()
	var can_hover := placement != null and placement.selected == null and placement.selected_threat == null and get_viewport().get_visible_rect().has_point(mouse) and get_viewport().gui_get_hovered_control() == null
	var rig := camera.get_parent() as CameraRig if camera != null else null
	if rig != null:
		can_hover = can_hover and not rig.input_blocked and not rig.rotating
	var asset := placement.asset_at_screen(mouse) if can_hover else null
	if is_instance_valid(asset):
		_show_asset_hint(asset, mouse)
	elif can_hover and harbor_marker_at_screen(harbor_port, camera, mouse):
		_show_harbor_hint(harbor_port, mouse)
	elif can_hover:
		hovered_track = track_at_screen(mouse)
		if hovered_track != null:
			_show_pointer_hint(tr("클릭: 항적 정보"), mouse)
	queue_redraw()

func _show_pointer_hint(message: String, mouse: Vector2) -> void:
	pointer_label.text = message
	hint_icon.hide()
	hint_separator.hide()
	hint_details.hide()
	_position_pointer_hint(mouse)

func _show_asset_hint(unit: DefenseUnit, mouse: Vector2) -> void:
	_show_status_hint(tr(unit.definition.display_name), unit.definition.identity_icon, asset_hint_status_entries(unit), mouse)

func _show_harbor_hint(port: HarborPort, mouse: Vector2) -> void:
	_show_status_hint(tr("화물 항구"), HarborPort.IDENTITY_ICON, harbor_hint_status_entries(port), mouse)

static func harbor_hint_status_entries(port: HarborPort) -> Array[Dictionary]:
	var entries: Array[Dictionary] = [{"kind": &"normal", "text": TranslationServer.translate("화물 하역 · 정기 지원")}]
	entries.append({"kind": &"normal" if port.operational else &"disabled", "text": TranslationServer.translate("정상 운영") if port.operational else TranslationServer.translate("복구 중 · 지원 중단")})
	return entries

func _show_status_hint(title: String, texture: Texture2D, entries: Array[Dictionary], mouse: Vector2) -> void:
	pointer_label.text = title
	hint_icon.texture = texture
	hint_icon.show()
	hint_separator.visible = not entries.is_empty()
	hint_details.visible = not entries.is_empty()
	for index: int in hint_rows.size():
		var row := hint_rows[index]
		row.visible = index < entries.size()
		if row.visible:
			row.text = String(entries[index].text)
			row.add_theme_color_override("font_color", _hint_status_color(StringName(entries[index].kind)))
	_position_pointer_hint(mouse)

static func harbor_marker_at_screen(port: HarborPort, view_camera: Camera3D, point: Vector2) -> bool:
	if not is_instance_valid(port) or not is_instance_valid(port.identity_marker) or view_camera == null:
		return false
	var marker := port.identity_marker
	for sprite: Sprite3D in [marker.icon, marker.condition_frame, marker.reload_background, marker.reload_fill]:
		var rect := AssetPointerTarget.marker_screen_rect(sprite, view_camera)
		if rect.has_area() and rect.grow(4.0).has_point(point):
			return true
	return false

static func _hint_status_color(kind: StringName) -> Color:
	if kind in [&"disabled", &"ammunition_empty"]:
		return Color("ff9685")
	if kind in [&"damaged", &"obstructed", &"ammunition_partial", &"resupply_waiting"]:
		return Color("e8bd78")
	if kind == &"resupply_active":
		return Color("85d5c7")
	return Color("a7bdc8")

func _position_pointer_hint(mouse: Vector2) -> void:
	pointer_hint.reset_size()
	var extent := get_viewport().get_visible_rect().size
	pointer_hint.position = (mouse + Vector2(20, 24)).clamp(Vector2(8, 8), (extent - pointer_hint.size - Vector2(8, 8)).max(Vector2(8, 8)))
	pointer_hint.show()

static func asset_hint_statuses(unit: DefenseUnit) -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in asset_hint_status_entries(unit):
		lines.append(String(entry.text))
	return lines

static func asset_hint_status_entries(unit: DefenseUnit) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not unit.active:
		var relocating := unit.relocation_manager != null and not unit.relocation_manager.task_status(unit).is_empty()
		entries.append({"kind": &"relocating" if relocating else &"disabled", "text": TranslationServer.translate("재배치 중") if relocating else TranslationServer.translate("기능 정지")})
	elif unit.operational_ratio() < 0.75:
		entries.append({"kind": &"damaged", "text": TranslationServer.translate("손상")})
	var supply_kind := unit.supply_status_kind()
	if not supply_kind.is_empty():
		entries.append({"kind": supply_kind, "text": unit.supply_status_text()})
	var obstruction := unit.obstruction_status_text()
	if not obstruction.is_empty():
		entries.append({"kind": &"obstructed", "text": TranslationServer.translate(obstruction)})
	var magazine := unit.reload_display_magazine() if unit.active else null
	if magazine != null:
		entries.append({"kind": &"reloading", "text": TranslationServer.translate("재장전 · %.1f초") % magazine.reload_remaining})
	return entries

func _draw() -> void:
	if camera == null:
		return
	if training_approach_visible:
		_draw_training_approach()
	if player_knowledge == null:
		return
	var viewport_size := size
	for track: PlayerTrack in player_knowledge.get_active_tracks():
		if not _unstable_track_visible(track):
			continue
		if track.state == PlayerTrack.State.TENTATIVE or _is_on_screen(track.estimated_position + Vector3.UP * 12.0, viewport_size):
			continue
		var marker := track_marker_screen_position(track)
		var direction := (marker - viewport_size * 0.5).normalized()
		var tangent := Vector2(-direction.y, direction.x)
		var scale := 1.35 if track.track_id == selected_track_id else 1.0
		var points := PackedVector2Array([
			marker + direction * 12.0 * scale,
			marker - direction * 8.0 * scale + tangent * 8.0 * scale,
			marker - direction * 8.0 * scale - tangent * 8.0 * scale,
		])
		var color := _track_color(track)
		draw_colored_polygon(points, color)
		draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color(0.02, 0.03, 0.04, 0.95), 2.0, true)
		if track.track_id == selected_track_id:
			draw_arc(marker, 18.0, 0.0, TAU, 24, Color(1.0, 0.92, 0.38, 0.95), 2.5, true)

func _draw_training_approach() -> void:
	var marker := training_marker_screen_position()
	var origin_screen := size * 0.5
	if not camera.is_position_behind(training_approach_origin):
		origin_screen = camera.unproject_position(training_approach_origin)
	var inward := (origin_screen - marker).normalized()
	if inward.length_squared() < 0.001:
		inward = Vector2.LEFT
	draw_dashed_line(origin_screen, marker, Color(1.0, 0.62, 0.12, 0.48), 3.0, 12.0, true)
	var tangent := Vector2(-inward.y, inward.x)
	var arrow := PackedVector2Array([
		marker + inward * 17.0,
		marker - inward * 10.0 + tangent * 11.0,
		marker - inward * 10.0 - tangent * 11.0,
	])
	draw_colored_polygon(arrow, Color(1.0, 0.58, 0.08, 0.98))
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color(0.08, 0.06, 0.02, 0.95), 2.0, true)
	var label_rect := training_approach_label_rect()
	var label_position := label_rect.get_center()
	draw_rect(label_rect, Color(0.04, 0.055, 0.05, 0.9), true)
	draw_rect(label_rect, Color(1.0, 0.62, 0.12, 0.92), false, 2.0)
	_draw_centered_text(training_approach_label_text(), label_position, Color(1.0, 0.82, 0.34), 16)

func training_approach_label_text() -> String:
	return tr(training_approach_text)

func training_marker_screen_position() -> Vector2:
	if camera == null:
		return size * 0.5
	var projected := camera.unproject_position(training_approach_position)
	var margins := _training_safe_margins()
	return marker_position_in_safe_area(projected, size, camera.is_position_behind(training_approach_position), margins.x, margins.y, margins.z, margins.w)

func training_approach_label_rect() -> Rect2:
	var marker := training_marker_screen_position()
	var origin_screen := size * 0.5
	if camera != null and not camera.is_position_behind(training_approach_origin):
		origin_screen = camera.unproject_position(training_approach_origin)
	var inward := (origin_screen - marker).normalized()
	if inward.length_squared() < 0.001:
		inward = Vector2.LEFT
	return Rect2(marker + inward * 116.0 - Vector2(95.0, 15.0), Vector2(190.0, 30.0))

func track_marker_screen_position(track: PlayerTrack) -> Vector2:
	if camera == null or track == null:
		return Vector2.INF
	var marker_world_position := track.estimated_position + Vector3.UP * 12.0
	var projected := camera.unproject_position(marker_world_position)
	var behind := camera.is_position_behind(marker_world_position)
	if not behind and Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN).has_point(projected):
		return projected
	if track.state == PlayerTrack.State.TENTATIVE:
		return Vector2.INF
	return tactical_marker_position(projected, size, behind)

func _training_safe_margins() -> Vector4:
	var left := EDGE_MARGIN
	# Keep the lesson's reserved area stable while a menu temporarily hides it.
	if training_left_panel != null:
		left = maxf(left, training_left_panel.get_global_rect().end.x + 16.0)
	return Vector4(left, 100.0, EDGE_MARGIN, 70.0)

func _draw_centered_text(text: String, position: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, position + Vector2(-text_size.x * 0.5, text_size.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _is_on_screen(world_position: Vector3, viewport_size: Vector2) -> bool:
	if camera.is_position_behind(world_position):
		return false
	var screen_position := camera.unproject_position(world_position)
	return Rect2(Vector2.ZERO, viewport_size).grow(-EDGE_MARGIN).has_point(screen_position)

static func marker_position(projected: Vector2, viewport_size: Vector2, behind: bool, margin: float) -> Vector2:
	return marker_position_in_safe_area(projected, viewport_size, behind, margin, margin, margin, margin)

static func tactical_marker_position(projected: Vector2, viewport_size: Vector2, behind: bool) -> Vector2:
	return marker_position(projected, viewport_size, behind, EDGE_MARGIN)

static func marker_position_in_safe_area(projected: Vector2, viewport_size: Vector2, behind: bool, left: float, top: float, right: float, bottom: float) -> Vector2:
	var center := viewport_size * 0.5
	var direction := projected - center
	if behind:
		direction = -direction
	if direction.length_squared() < 0.001:
		direction = Vector2.UP
	var safe_min := Vector2(left, top)
	var safe_max := Vector2(maxf(left, viewport_size.x - right), maxf(top, viewport_size.y - bottom))
	var horizontal_limit := safe_max.x - center.x if direction.x >= 0.0 else center.x - safe_min.x
	var vertical_limit := safe_max.y - center.y if direction.y >= 0.0 else center.y - safe_min.y
	var factor := minf(horizontal_limit / maxf(absf(direction.x), 0.001), vertical_limit / maxf(absf(direction.y), 0.001))
	return center + direction * factor

func _track_color(track: PlayerTrack) -> Color:
	if track.capacity_limited:
		var color := TrackMarker.CAPACITY_LIMITED_COLOR
		color.a = 0.88
		return color
	if track.state == PlayerTrack.State.COASTING:
		return Color(0.78, 0.86, 0.92, 0.72)
	if track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3:
		return Color(1.0, 0.25, 0.16, 0.92)
	if track.affiliation == PlayerTrack.Affiliation.NEUTRAL and track.affiliation_confidence >= 0.3:
		return Color(0.28, 0.82, 0.92, 0.82)
	return Color(1.0, 0.78, 0.22, 0.88)

func _unstable_track_visible(track: PlayerTrack) -> bool:
	return TrackMarker.capacity_limited_visible(track, instability_time)
