class_name TrackMarker
extends Node3D

var track: PlayerTrack

var icon := Label3D.new()
var uncertainty_ring := MeshInstance3D.new()
var selection_ring := MeshInstance3D.new()
var ring_material := StandardMaterial3D.new()
var selection_material := StandardMaterial3D.new()
var position_history: Array[Vector3] = []
var selected: bool = false
var base_icon_text: String = "?"

func _ready() -> void:
	icon.name = "Icon"
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.font_size = 52
	icon.pixel_size = 0.22
	icon.outline_size = 8
	icon.modulate = Color.WHITE
	add_child(icon)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 5.2
	ring_mesh.outer_radius = 5.8
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 32
	uncertainty_ring.mesh = ring_mesh
	uncertainty_ring.position.y = -8.0
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	uncertainty_ring.material_override = ring_material
	add_child(uncertainty_ring)
	var selection_mesh := TorusMesh.new()
	selection_mesh.inner_radius = 8.5
	selection_mesh.outer_radius = 9.5
	selection_mesh.rings = 8
	selection_mesh.ring_segments = 40
	selection_ring.name = "SelectionRing"
	selection_ring.mesh = selection_mesh
	selection_ring.position.y = -8.0
	selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	selection_material.albedo_color = Color(1.0, 0.92, 0.38, 0.9)
	selection_ring.material_override = selection_material
	selection_ring.visible = false
	add_child(selection_ring)

func setup(track_value: PlayerTrack) -> void:
	track = track_value
	refresh_state()
	refresh_position()

func _process(_delta: float) -> void:
	refresh_position()

func refresh_position() -> void:
	if track == null:
		return
	global_position = track.estimated_position + Vector3.UP * 12.0
	if position_history.is_empty() or position_history.back().distance_to(track.estimated_position) >= 8.0:
		position_history.append(track.estimated_position)
		if position_history.size() > 14:
			position_history.pop_front()
	var uncertainty_scale := clampf(track.position_uncertainty / 12.0, 0.65, 5.0)
	uncertainty_ring.scale = Vector3(uncertainty_scale, 1.0, uncertainty_scale)

func set_selected(enabled: bool) -> void:
	selected = enabled
	selection_ring.visible = enabled and visible
	_apply_selection()

func _apply_selection() -> void:
	icon.text = "%s\nT-%03d" % [base_icon_text, track.track_id] if selected and track != null else base_icon_text
	icon.outline_size = 12 if selected else 8
	icon.scale = Vector3.ONE * (1.18 if selected else 1.0)

func refresh_state() -> void:
	if track == null:
		return
	match track.state:
		PlayerTrack.State.TENTATIVE:
			visible = true
			base_icon_text = "?"
			icon.modulate = Color(1.0, 0.78, 0.22, 0.92)
			ring_material.albedo_color = Color(1.0, 0.78, 0.22, 0.24)
		PlayerTrack.State.CONFIRMED:
			visible = true
			if track.affiliation_confidence < 0.3:
				base_icon_text = "◇"
				icon.modulate = Color(1.0, 0.78, 0.22, 0.94)
				ring_material.albedo_color = Color(1.0, 0.78, 0.22, 0.2)
			elif track.affiliation == PlayerTrack.Affiliation.HOSTILE:
				base_icon_text = "◆"
				icon.modulate = Color(1.0, 0.24, 0.16, 0.96)
				ring_material.albedo_color = Color(1.0, 0.24, 0.16, 0.18)
			elif track.affiliation == PlayerTrack.Affiliation.NEUTRAL:
				base_icon_text = "●"
				icon.modulate = Color(0.28, 0.82, 0.92, 0.9)
				ring_material.albedo_color = Color(0.28, 0.82, 0.92, 0.18)
			else:
				base_icon_text = "■"
				icon.modulate = Color(0.35, 0.94, 0.54, 0.9)
				ring_material.albedo_color = Color(0.35, 0.94, 0.54, 0.18)
		PlayerTrack.State.COASTING:
			visible = true
			base_icon_text = "◇"
			icon.modulate = Color(0.82, 0.88, 0.92, 0.78)
			ring_material.albedo_color = Color(0.82, 0.88, 0.92, 0.34)
		PlayerTrack.State.LOST:
			visible = false
	selection_ring.visible = selected and visible
	_apply_selection()
