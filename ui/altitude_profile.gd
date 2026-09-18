class_name AltitudeProfile
extends Control

const MAX_ALTITUDE := 1500.0
const LOW_CEILING := 180.0
const MEDIUM_CEILING := 450.0
const TICK_ALTITUDES := [0.0, 100.0, 180.0, 300.0, 450.0, 750.0, 1000.0, 1250.0, 1500.0]

var camera: Camera3D
var player_knowledge: PlayerKnowledge
var objective: Node3D
var battlefield_size: float = 1800.0
var refresh_remaining: float = 0.0
var track_markers: Array[Dictionary] = []
var projectile_markers: Array[Dictionary] = []

func configure(camera_value: Camera3D, knowledge_value: PlayerKnowledge, objective_value: Node3D, battlefield_size_value: float) -> void:
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
		for track: PlayerTrack in player_knowledge.get_active_tracks():
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
	var accent := MenuStyle.ACCENT
	draw_rect(panel, MenuStyle.SURFACE, true)
	draw_rect(panel.grow(-0.5), Color(accent, 0.35), false, 1.0)
	draw_rect(Rect2(0.0, 0.0, size.x, 2.0), Color(accent, 0.8), true)
	var font := ThemeDB.fallback_font
	draw_string(MenuStyle.tracked_font(1), Vector2(10.0, 20.0), "고도 프로파일", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, MenuStyle.TEXT)
	draw_string(font, Vector2(size.x - 10.0 - 12.0, 20.0), "m", HORIZONTAL_ALIGNMENT_RIGHT, 12.0, 10, MenuStyle.TEXT_MUTED)
	var plot_left := 36.0
	var plot_right := size.x - 8.0
	var plot_top := 30.0
	var plot_bottom := size.y - 30.0
	var band_height := (plot_bottom - plot_top) / 3.0
	var bands: Array[Dictionary] = [
		{"name": "고층", "color": Color(0.5, 0.68, 0.96)},
		{"name": "중층", "color": Color(0.44, 0.84, 0.86)},
		{"name": "저층", "color": Color(0.5, 0.88, 0.62)},
	]
	for index: int in bands.size():
		var band: Dictionary = bands[index]
		var color: Color = band.color
		var top := plot_top + band_height * index
		draw_rect(Rect2(plot_left, top, plot_right - plot_left, band_height), Color(color, 0.07), true)
		draw_rect(Rect2(plot_left, top, 2.0, band_height), Color(color, 0.55), true)
		draw_string(font, Vector2(plot_left, top + 13.0), String(band.name), HORIZONTAL_ALIGNMENT_RIGHT, plot_right - plot_left - 4.0, 10, Color(color, 0.75))
	for altitude: float in TICK_ALTITUDES:
		var y := altitude_to_plot_y(altitude)
		var major := altitude in [0.0, LOW_CEILING, MEDIUM_CEILING, MAX_ALTITUDE]
		if major:
			draw_line(Vector2(plot_left - 4.0, y), Vector2(plot_right, y), Color(accent, 0.3), 1.0)
		else:
			draw_dashed_line(Vector2(plot_left, y), Vector2(plot_right, y), Color(accent, 0.1), 1.0, 3.0)
		draw_string(font, Vector2(2.0, y + 3.5), str(roundi(altitude)), HORIZONTAL_ALIGNMENT_RIGHT, plot_left - 8.0, 9, Color(MenuStyle.TEXT_MUTED, 0.9 if major else 0.6))
	for marker: Dictionary in track_markers:
		var world_position: Vector3 = marker.position
		var point := Vector2(_horizontal_plot_x(world_position, plot_left, plot_right), altitude_to_plot_y(world_position.y))
		var color := _track_color(marker)
		var radius := 4.0 if int(marker.state) != PlayerTrack.State.TENTATIVE else 3.0
		draw_circle(point, radius + 3.0, Color(color, 0.16))
		draw_circle(point, radius, color)
		draw_arc(point, radius + 1.0, 0.0, TAU, 12, Color(0.01, 0.02, 0.03, 0.9), 1.0)
	for marker: Dictionary in projectile_markers:
		var world_position: Vector3 = marker.position
		var point := Vector2(_horizontal_plot_x(world_position, plot_left, plot_right), altitude_to_plot_y(world_position.y))
		_draw_diamond(point, 4.5, Color(0.25, 0.92, 1.0, 0.98))
	var legend_y := size.y - 12.0
	draw_circle(Vector2(12.0, legend_y - 3.5), 3.5, MenuStyle.TEXT)
	draw_string(font, Vector2(20.0, legend_y), "항적", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, MenuStyle.TEXT_MUTED)
	_draw_diamond(Vector2(58.0, legend_y - 3.5), 4.0, MenuStyle.TEXT)
	draw_string(font, Vector2(66.0, legend_y), "요격체", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, MenuStyle.TEXT_MUTED)

func _draw_diamond(point: Vector2, radius: float, color: Color) -> void:
	var diamond := PackedVector2Array([point + Vector2(0.0, -radius), point + Vector2(radius * 0.8, 0.0), point + Vector2(0.0, radius), point + Vector2(-radius * 0.8, 0.0)])
	draw_colored_polygon(diamond, color)
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(0.01, 0.03, 0.04, 0.95), 1.0)

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
