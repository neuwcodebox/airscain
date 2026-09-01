class_name TacticalScreenOverlay
extends Control

const EDGE_MARGIN := 42.0

var camera: Camera3D
var player_knowledge: Node
var selected_track_id: int = -1

func configure(camera_value: Camera3D, knowledge: Node) -> void:
	camera = camera_value
	player_knowledge = knowledge
	queue_redraw()

func select_track(track: PlayerTrack) -> void:
	selected_track_id = track.track_id if track != null else -1
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if camera == null or player_knowledge == null:
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
