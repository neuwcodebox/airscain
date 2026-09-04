class_name TrackDisplay
extends Node3D

var player_knowledge: Node
var markers: Dictionary[int, TrackMarker] = {}
var defense_parent: Node3D
var engagement_coordinator: EngagementCoordinator
var selected_track: PlayerTrack
var selected_engagement_source: DefenseUnit
var selection_lines := MeshInstance3D.new()
var engagement_distance_label := Label3D.new()
var line_material := StandardMaterial3D.new()
var rebuild_remaining: float = 0.0

func _ready() -> void:
	selection_lines.name = "SelectionRelations"
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	selection_lines.material_override = line_material
	add_child(selection_lines)
	engagement_distance_label.name = "EngagementDistance"
	engagement_distance_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	engagement_distance_label.no_depth_test = true
	engagement_distance_label.fixed_size = true
	engagement_distance_label.pixel_size = 0.001
	engagement_distance_label.font_size = 14
	engagement_distance_label.outline_size = 6
	engagement_distance_label.outline_modulate = Color(0.015, 0.025, 0.035, 0.96)
	engagement_distance_label.render_priority = 110
	engagement_distance_label.visible = false
	add_child(engagement_distance_label)

func configure(player_knowledge_value: Node, defense_parent_value: Node3D, coordinator: EngagementCoordinator) -> void:
	player_knowledge = player_knowledge_value
	defense_parent = defense_parent_value
	engagement_coordinator = coordinator
	player_knowledge.connect("track_created", _on_track_created)
	player_knowledge.connect("track_updated", _on_track_updated)
	player_knowledge.connect("track_state_changed", _on_track_state_changed)
	player_knowledge.connect("track_removed", _on_track_removed)
	var existing_tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	for track: PlayerTrack in existing_tracks:
		_on_track_created(track)

func _process(delta: float) -> void:
	rebuild_remaining -= delta
	if rebuild_remaining <= 0.0:
		rebuild_remaining += 0.1
		_rebuild_selection_lines()

func select_track(track: PlayerTrack) -> void:
	selected_track = track
	rebuild_remaining = 0.1
	for marker: TrackMarker in markers.values():
		marker.set_selected(track != null and marker.track.track_id == track.track_id)
	_rebuild_selection_lines()

func select_engagement_source(unit: DefenseUnit) -> void:
	selected_engagement_source = unit if unit != null and unit.supports_engagement_controls() else null
	_rebuild_selection_lines()

func selection_details() -> Dictionary:
	if selected_track == null:
		return {"sensor_count": 0, "engagement_count": 0}
	return {
		"sensor_count": _related_assets(selected_track.contributing_sensor_ids).size(),
		"engagement_count": engagement_coordinator.engagement_owner_ids(selected_track.track_id).size() if engagement_coordinator != null else 0,
	}

func reset() -> void:
	selected_track = null
	selected_engagement_source = null
	selection_lines.mesh = null
	engagement_distance_label.visible = false
	for marker: TrackMarker in markers.values():
		if is_instance_valid(marker):
			marker.free()
	markers.clear()

func _on_track_created(track: PlayerTrack) -> void:
	if markers.has(track.track_id):
		return
	var marker := TrackMarker.new()
	marker.name = "TrackMarker%d" % track.track_id
	add_child(marker)
	marker.setup(track)
	markers[track.track_id] = marker

func _on_track_state_changed(track: PlayerTrack, _previous_state: PlayerTrack.State) -> void:
	var marker := markers.get(track.track_id) as TrackMarker
	if marker != null:
		marker.refresh_state()

func _on_track_updated(track: PlayerTrack) -> void:
	var marker := markers.get(track.track_id) as TrackMarker
	if marker != null:
		marker.refresh_state()

func _on_track_removed(track_id: int) -> void:
	var marker := markers.get(track_id) as TrackMarker
	if marker != null:
		marker.queue_free()
	markers.erase(track_id)
	if selected_track != null and selected_track.track_id == track_id:
		select_track(null)

func _rebuild_selection_lines() -> void:
	engagement_distance_label.visible = false
	if selected_track == null or selected_track.state == PlayerTrack.State.LOST:
		selection_lines.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var vertex_count := 0
	var marker := markers.get(selected_track.track_id) as TrackMarker
	if marker != null:
		for index: int in range(1, marker.position_history.size()):
			_add_segment(mesh, marker.position_history[index - 1] + Vector3.UP * 12.0, marker.position_history[index] + Vector3.UP * 12.0, Color(1.0, 0.82, 0.25, 0.72))
			vertex_count += 2
	var prediction_seconds := 3.0
	vertex_count += _add_dashed_segment(mesh, selected_track.estimated_position + Vector3.UP * 12.0, selected_track.estimated_position + selected_track.estimated_velocity * prediction_seconds + Vector3.UP * 12.0, Color(1.0, 0.92, 0.45, 0.55), 6)
	for sensor: DefenseUnit in _related_assets(selected_track.contributing_sensor_ids):
		_add_segment(mesh, sensor.global_position + Vector3.UP * 9.0, selected_track.estimated_position + Vector3.UP * 12.0, Color(0.2, 0.82, 1.0, 0.62))
		vertex_count += 2
	if engagement_coordinator != null:
		for owner: DefenseUnit in _related_assets(engagement_coordinator.engagement_owner_ids(selected_track.track_id)):
			vertex_count += _add_dashed_segment(mesh, owner.global_position + Vector3.UP * 9.0, selected_track.estimated_position + Vector3.UP * 12.0, Color(1.0, 0.34, 0.18, 0.82), 10)
	if selected_engagement_source != null and is_instance_valid(selected_engagement_source):
		var source_position := selected_engagement_source.global_position + Vector3.UP * 9.0
		var target_position := selected_track.estimated_position + Vector3.UP * 12.0
		vertex_count += _add_dashed_segment(mesh, source_position, target_position, Color(0.28, 0.9, 1.0, 0.88), 8)
		var distance := selected_engagement_source.global_position.distance_to(selected_track.estimated_position)
		var effective_range := selected_engagement_source.definition.tactical_range() * selected_engagement_source.operational_efficiency()
		engagement_distance_label.text = "%dm / %dm" % [roundi(distance), roundi(effective_range)]
		engagement_distance_label.modulate = Color(0.45, 0.92, 0.82) if distance <= effective_range else Color(1.0, 0.62, 0.3)
		engagement_distance_label.global_position = source_position.lerp(target_position, 0.5) + Vector3.UP * 6.0
		engagement_distance_label.visible = true
	if vertex_count > 0:
		mesh.surface_end()
		selection_lines.mesh = mesh
	else:
		selection_lines.mesh = null

func _related_assets(runtime_ids: Array[int]) -> Array[DefenseUnit]:
	var result: Array[DefenseUnit] = []
	if defense_parent == null:
		return result
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit != null and runtime_ids.has(unit.runtime_id):
			result.append(unit)
	return result

func _add_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)

func _add_dashed_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color, dash_count: int) -> int:
	for index: int in range(0, dash_count, 2):
		var start_weight := float(index) / float(dash_count)
		var end_weight := float(index + 1) / float(dash_count)
		_add_segment(mesh, from.lerp(to, start_weight), from.lerp(to, end_weight), color)
	return dash_count
