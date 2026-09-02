extends Control

const MAX_ALTITUDE := 1500.0
const LOW_CEILING := 180.0
const MEDIUM_CEILING := 450.0
const TICK_ALTITUDES := [0.0, 100.0, 180.0, 300.0, 450.0, 750.0, 1000.0, 1250.0, 1500.0]

var camera: Camera3D
var player_knowledge: Node
var objective: Node3D
var battlefield_size: float = 1800.0
var refresh_remaining: float = 0.0
var track_markers: Array[Dictionary] = []
var projectile_markers: Array[Dictionary] = []

func configure(camera_value: Camera3D, knowledge_value: Node, objective_value: Node3D, battlefield_size_value: float) -> void:
	camera = camera_value
	player_knowledge = knowledge_value
	objective = objective_value
	battlefield_size = battlefield_size_value
	refresh_snapshot()

func _process(delta: float) -> void:
	refresh_remaining -= delta
	if refresh_remaining <= 0.0:
		refresh_remaining = 0.1
		refresh_snapshot()

func refresh_snapshot() -> void:
	track_markers.clear()
	projectile_markers.clear()
	if player_knowledge != null:
		for track: PlayerTrack in player_knowledge.call("get_active_tracks"):
			track_markers.append({
				"position": track.estimated_position,
				"state": int(track.state),
				"affiliation": int(track.affiliation),
				"confidence": track.affiliation_confidence,
			})
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group("friendly_altitude_projectiles"):
			if node is Node3D and is_instance_valid(node) and not node.is_queued_for_deletion():
				projectile_markers.append({"position": (node as Node3D).global_position})
	queue_redraw()

func altitude_to_plot_y(altitude: float) -> float:
	var top := 30.0
	var bottom := size.y - 30.0
	var band_height := (bottom - top) / 3.0
	var clamped := clampf(altitude, 0.0, MAX_ALTITUDE)
	if clamped <= LOW_CEILING:
		return bottom - (clamped / LOW_CEILING) * band_height
	if clamped <= MEDIUM_CEILING:
		return bottom - band_height - ((clamped - LOW_CEILING) / (MEDIUM_CEILING - LOW_CEILING)) * band_height
	return bottom - band_height * 2.0 - ((clamped - MEDIUM_CEILING) / (MAX_ALTITUDE - MEDIUM_CEILING)) * band_height

func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, Color(0.025, 0.055, 0.075, 0.91), true)
	draw_rect(panel, Color(0.12, 0.72, 0.86, 0.78), false, 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8.0, 19.0), "고도 프로파일", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.68, 0.92, 1.0))
	var plot_left := 36.0
	var plot_right := size.x - 8.0
	var plot_top := 30.0
	var plot_bottom := size.y - 30.0
	var band_height := (plot_bottom - plot_top) / 3.0
	draw_rect(Rect2(plot_left, plot_top, plot_right - plot_left, band_height), Color(0.16, 0.30, 0.48, 0.34), true)
	draw_rect(Rect2(plot_left, plot_top + band_height, plot_right - plot_left, band_height), Color(0.10, 0.40, 0.46, 0.28), true)
	draw_rect(Rect2(plot_left, plot_top + band_height * 2.0, plot_right - plot_left, band_height), Color(0.12, 0.43, 0.30, 0.28), true)
	draw_string(font, Vector2(plot_left + 5.0, plot_top + 14.0), "고층", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.56, 0.76, 0.96, 0.72))
	draw_string(font, Vector2(plot_left + 5.0, plot_top + band_height + 14.0), "중층", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.46, 0.86, 0.88, 0.72))
	draw_string(font, Vector2(plot_left + 5.0, plot_top + band_height * 2.0 + 14.0), "저층", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.52, 0.88, 0.66, 0.72))
	for altitude: float in TICK_ALTITUDES:
		var y := altitude_to_plot_y(altitude)
		var major := altitude in [0.0, LOW_CEILING, MEDIUM_CEILING, MAX_ALTITUDE]
		draw_line(Vector2(plot_left - (6.0 if major else 3.0), y), Vector2(plot_right, y), Color(0.48, 0.68, 0.76, 0.42 if major else 0.2), 1.0)
		draw_string(font, Vector2(2.0, y + 4.0), str(roundi(altitude)), HORIZONTAL_ALIGNMENT_LEFT, 31.0, 9, Color(0.62, 0.76, 0.8, 0.82))
	for marker: Dictionary in track_markers:
		var world_position: Vector3 = marker.position
		var point := Vector2(_horizontal_plot_x(world_position, plot_left, plot_right), altitude_to_plot_y(world_position.y))
		var color := _track_color(marker)
		var radius := 4.0 if int(marker.state) != PlayerTrack.State.TENTATIVE else 3.0
		draw_circle(point, radius, color)
		draw_arc(point, radius + 1.5, 0.0, TAU, 12, Color(0.01, 0.02, 0.03, 0.9), 1.0)
	for marker: Dictionary in projectile_markers:
		var world_position: Vector3 = marker.position
		var point := Vector2(_horizontal_plot_x(world_position, plot_left, plot_right), altitude_to_plot_y(world_position.y))
		var diamond := PackedVector2Array([point + Vector2(0.0, -5.0), point + Vector2(4.0, 0.0), point + Vector2(0.0, 5.0), point + Vector2(-4.0, 0.0)])
		draw_colored_polygon(diamond, Color(0.25, 0.92, 1.0, 0.98))
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(0.01, 0.03, 0.04, 0.95), 1.0)
	draw_string(font, Vector2(8.0, size.y - 10.0), "● 항적   ◆ 요격체", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.68, 0.84, 0.9, 0.88))

func _horizontal_plot_x(world_position: Vector3, left: float, right: float) -> float:
	if objective == null:
		return (left + right) * 0.5
	var direction := Vector3.RIGHT
	if camera != null:
		direction = camera.global_basis.x.normalized()
	var lateral := (world_position - objective.global_position).dot(direction)
	var half_span := maxf(1.0, battlefield_size * 0.5)
	return lerpf(left + 6.0, right - 6.0, clampf(lateral / half_span * 0.5 + 0.5, 0.0, 1.0))

func _track_color(marker: Dictionary) -> Color:
	if int(marker.state) == PlayerTrack.State.COASTING:
		return Color(0.72, 0.82, 0.9, 0.68)
	if int(marker.affiliation) == PlayerTrack.Affiliation.HOSTILE and float(marker.confidence) >= 0.3:
		return Color(1.0, 0.27, 0.17, 0.98)
	if int(marker.affiliation) == PlayerTrack.Affiliation.NEUTRAL and float(marker.confidence) >= 0.3:
		return Color(0.3, 0.86, 0.94, 0.9)
	return Color(1.0, 0.78, 0.24, 0.94)
