class_name TacticalScreenOverlay
extends Control

const EDGE_MARGIN := 42.0
const COMPASS_CENTER := Vector2(410.0, 116.0)
const COMPASS_RADIUS := 38.0
const TRAINING_RIGHT_INSET := 340.0

var camera: Camera3D
var player_knowledge: Node
var selected_track_id: int = -1
var training_approach_visible: bool = false
var training_approach_origin: Vector3
var training_approach_position: Vector3
var training_approach_text: String = "훈련 표적 진입"

func configure(camera_value: Camera3D, knowledge: Node) -> void:
	camera = camera_value
	player_knowledge = knowledge
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
	queue_redraw()

func _draw() -> void:
	if camera == null:
		return
	_draw_compass()
	if training_approach_visible:
		_draw_training_approach()
	if player_knowledge == null:
		return
	var viewport_size := size
	for track: PlayerTrack in player_knowledge.call("get_active_tracks"):
		if track.state == PlayerTrack.State.TENTATIVE or _is_on_screen(track.estimated_position, viewport_size):
			continue
		var marker := marker_position(camera.unproject_position(track.estimated_position), viewport_size, camera.is_position_behind(track.estimated_position), EDGE_MARGIN)
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

func _draw_compass() -> void:
	var background := Color(0.025, 0.055, 0.07, 0.82)
	var line_color := Color(0.52, 0.76, 0.84, 0.72)
	draw_circle(COMPASS_CENTER, COMPASS_RADIUS, background)
	draw_arc(COMPASS_CENTER, COMPASS_RADIUS, 0.0, TAU, 48, Color(0.25, 0.72, 0.88, 0.9), 2.0, true)
	var directions: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	var labels: Array[String] = ["N", "E", "S", "W"]
	for index: int in directions.size():
		var screen_direction := compass_screen_direction(directions[index])
		draw_line(COMPASS_CENTER + screen_direction * 11.0, COMPASS_CENTER + screen_direction * 18.0, line_color, 2.0, true)
		_draw_centered_text(labels[index], COMPASS_CENTER + screen_direction * 27.0, Color(1.0, 0.78, 0.24) if index == 0 else Color(0.78, 0.9, 0.94), 14)
	var north := compass_screen_direction(Vector3.FORWARD)
	var tangent := Vector2(-north.y, north.x)
	draw_colored_polygon(PackedVector2Array([
		COMPASS_CENTER + north * 18.0,
		COMPASS_CENTER - north * 2.0 + tangent * 5.0,
		COMPASS_CENTER - north * 2.0 - tangent * 5.0,
	]), Color(1.0, 0.62, 0.18, 0.95))

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
	var label_position := marker + inward * 116.0
	var label_size := Vector2(190.0, 30.0)
	draw_rect(Rect2(label_position - label_size * 0.5, label_size), Color(0.04, 0.055, 0.05, 0.9), true)
	draw_rect(Rect2(label_position - label_size * 0.5, label_size), Color(1.0, 0.62, 0.12, 0.92), false, 2.0)
	_draw_centered_text("E · %s" % training_approach_text, label_position, Color(1.0, 0.82, 0.34), 16)

func compass_screen_direction(world_direction: Vector3) -> Vector2:
	if camera == null:
		return Vector2.UP
	var direction := Vector2(world_direction.dot(camera.global_basis.x), -world_direction.dot(camera.global_basis.y))
	return direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP

func training_marker_screen_position() -> Vector2:
	if camera == null:
		return size * 0.5
	var projected := camera.unproject_position(training_approach_position)
	if camera.is_position_behind(training_approach_position):
		projected = size - projected
	return Vector2(
		clampf(projected.x, EDGE_MARGIN, maxf(EDGE_MARGIN, size.x - TRAINING_RIGHT_INSET)),
		clampf(projected.y, 100.0, maxf(100.0, size.y - 70.0))
	)

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
	var center := viewport_size * 0.5
	var direction := projected - center
	if behind:
		direction = -direction
	if direction.length_squared() < 0.001:
		direction = Vector2.UP
	var limit := center - Vector2.ONE * margin
	var factor := minf(limit.x / maxf(absf(direction.x), 0.001), limit.y / maxf(absf(direction.y), 0.001))
	return center + direction * factor

func _track_color(track: PlayerTrack) -> Color:
	if track.state == PlayerTrack.State.COASTING:
		return Color(0.78, 0.86, 0.92, 0.72)
	if track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3:
		return Color(1.0, 0.25, 0.16, 0.92)
	if track.affiliation == PlayerTrack.Affiliation.NEUTRAL and track.affiliation_confidence >= 0.3:
		return Color(0.28, 0.82, 0.92, 0.82)
	return Color(1.0, 0.78, 0.22, 0.88)
