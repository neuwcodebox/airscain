class_name TacticalScreenOverlay
extends Control

const EDGE_MARGIN := 20.0

var camera: Camera3D
var player_knowledge: Node
var selected_track_id: int = -1
var training_approach_visible: bool = false
var training_approach_origin: Vector3
var training_approach_position: Vector3
var training_approach_text: String = "훈련 표적 진입"
var training_left_panel: Control
var priority_source: DefenseUnit
var placement: PlacementController
var hovered_track: PlayerTrack
var priority_hint := PanelContainer.new()
var priority_label := Label.new()

func _ready() -> void:
	priority_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	priority_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	priority_label.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.08, 0.96)
	style.border_color = Color(0.35, 0.9, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	priority_hint.add_theme_stylebox_override("panel", style)
	priority_hint.add_child(priority_label)
	add_child(priority_hint)
	priority_hint.hide()

static func can_prioritize(unit: DefenseUnit, track: PlayerTrack) -> bool:
	return is_instance_valid(unit) and unit.supports_engagement_controls() and unit.integrity > 0.0 and track != null and track.state != PlayerTrack.State.LOST and track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3

func select_priority_source(unit: DefenseUnit) -> void:
	priority_source = unit
	hovered_track = null
	priority_hint.hide()
	queue_redraw()

func track_at_screen(point: Vector2) -> PlayerTrack:
	var nearest: PlayerTrack
	var distance := 34.0
	for track: PlayerTrack in player_knowledge.call("get_active_tracks"):
		var screen := track_marker_screen_position(track)
		if screen.is_finite() and screen.distance_to(point) < distance:
			distance = screen.distance_to(point)
			nearest = track
	return nearest

func configure(camera_value: Camera3D, knowledge: Node, left_panel: Control = null) -> void:
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

func _process(_delta: float) -> void:
	hovered_track = null
	priority_hint.hide()
	var mouse := get_viewport().get_mouse_position()
	var can_hover := placement != null and placement.selected == null and placement.selected_threat == null and get_viewport().get_visible_rect().has_point(mouse) and get_viewport().gui_get_hovered_control() == null
	var rig := camera.get_parent() as CameraRig if camera != null else null
	if rig != null:
		can_hover = can_hover and not rig.input_blocked and not rig.rotating
	var asset := placement.asset_at_screen(mouse) if can_hover else null
	if is_instance_valid(asset):
		_show_pointer_hint(asset_hint_text(asset), mouse)
	elif can_hover and is_instance_valid(priority_source) and priority_source.supports_engagement_controls():
		hovered_track = track_at_screen(mouse)
		if hovered_track != null:
			priority_label.text = "클릭: 우선표적 지정" if can_prioritize(priority_source, hovered_track) else "클릭: 항적 정보"
			if can_prioritize(priority_source, hovered_track) and priority_source.priority_track_id() == hovered_track.track_id:
				priority_label.text = "우선표적 지정됨"
			_show_pointer_hint(priority_label.text, mouse)
	queue_redraw()

func _show_pointer_hint(message: String, mouse: Vector2) -> void:
	priority_label.text = message
	priority_hint.reset_size()
	var extent := get_viewport().get_visible_rect().size
	priority_hint.position = (mouse + Vector2(20, 24)).clamp(Vector2(8, 8), (extent - priority_hint.size - Vector2(8, 8)).max(Vector2(8, 8)))
	priority_hint.show()

static func asset_hint_text(unit: DefenseUnit) -> String:
	var lines: Array[String] = [unit.definition.display_name]
	var status := unit.critical_status_text()
	if status == "×":
		status = "재배치 중" if unit.relocation_manager != null and not unit.relocation_manager.task_status(unit).is_empty() else "기능 정지"
	if not status.is_empty():
		lines.append(status)
	var magazine := unit.reload_display_magazine() if unit.active else null
	if magazine != null:
		lines.append("재장전 · %.1f초" % magazine.reload_remaining)
	return "\n".join(lines)

func _draw() -> void:
	if camera == null:
		return
	if can_prioritize(priority_source, hovered_track):
		var point := track_marker_screen_position(hovered_track)
		var color := Color(0.35, 1.0, 0.75)
		draw_arc(point, 20.0, 0.0, TAU, 32, color, 1.5, true)
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(point + direction * 16, point + direction * 25, color, 2, true)
	if training_approach_visible:
		_draw_training_approach()
	if player_knowledge == null:
		return
	var viewport_size := size
	for track: PlayerTrack in player_knowledge.call("get_active_tracks"):
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
	return training_approach_text

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
	if track.state == PlayerTrack.State.COASTING:
		return Color(0.78, 0.86, 0.92, 0.72)
	if track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3:
		return Color(1.0, 0.25, 0.16, 0.92)
	if track.affiliation == PlayerTrack.Affiliation.NEUTRAL and track.affiliation_confidence >= 0.3:
		return Color(0.28, 0.82, 0.92, 0.82)
	return Color(1.0, 0.78, 0.22, 0.88)
