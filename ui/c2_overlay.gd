class_name C2Overlay
extends Node3D

const ACTIVE_COLOR := Color(0.12, 0.82, 1.0, 0.82)
const READY_COLOR := Color(0.18, 0.92, 0.86, 0.92)
const INCOMPLETE_COLOR := Color(1.0, 0.58, 0.18, 0.92)
const LINK_HEIGHT := 9.0
const DASH_LENGTH := 18.0
const DASH_GAP := 10.0

var c2_network: Node
var selected_asset: DefenseUnit
var show_all_links: bool = false
var visible_link_count: int = 0
var placement_definition: DefenseDefinition
var placement_position: Vector3
var placement_active: bool = false
var placement_ready: bool = false

var links := MeshInstance3D.new()
var range_ring := MeshInstance3D.new()
var line_material := StandardMaterial3D.new()
var range_material := StandardMaterial3D.new()

func _ready() -> void:
	links.name = "Links"
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	links.material_override = line_material
	add_child(links)
	range_ring.name = "SelectedRange"
	range_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_material.albedo_color = Color(0.16, 0.78, 0.95, 0.48)
	range_material.no_depth_test = true
	range_ring.material_override = range_material
	add_child(range_ring)
	visible = false

func configure(network: Node) -> void:
	c2_network = network

func select_asset(unit: DefenseUnit) -> void:
	selected_asset = unit
	visible = unit != null or show_all_links
	_rebuild()

func toggle_all_links() -> void:
	set_all_links(not show_all_links)

func set_all_links(enabled: bool) -> void:
	show_all_links = enabled
	visible = show_all_links or selected_asset != null
	_rebuild()

func preview_placement(definition: DefenseDefinition, position: Vector3, active: bool) -> void:
	placement_definition = definition
	placement_position = position
	placement_active = active and definition != null and definition.placement_c2_range() > 0.0
	visible = placement_active or show_all_links or selected_asset != null
	_rebuild()

func _rebuild() -> void:
	visible_link_count = 0
	var line_mesh := ImmediateMesh.new()
	var surface_started := false
	if c2_network != null and placement_active:
		var preview_result: Dictionary = c2_network.call("placement_preview", placement_definition, placement_position)
		placement_ready = bool(preview_result.ready)
		var preview_links: Array = preview_result.links
		if not preview_links.is_empty():
			line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			surface_started = true
			for endpoint: DefenseUnit in preview_links:
				var start := placement_position + Vector3.UP * LINK_HEIGHT
				var finish := endpoint.global_position + Vector3.UP * LINK_HEIGHT
				if placement_ready:
					_add_segment(line_mesh, start, finish, READY_COLOR)
				else:
					_add_dashed_segment(line_mesh, start, finish, INCOMPLETE_COLOR)
				visible_link_count += 1
	elif c2_network != null:
		var active_links: Array = c2_network.call("active_links")
		for link: Array in active_links:
			var first := link[0] as DefenseUnit
			var second := link[1] as DefenseUnit
			if not show_all_links and selected_asset != first and selected_asset != second:
				continue
			if not surface_started:
				line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				surface_started = true
			_add_segment(line_mesh, first.global_position + Vector3.UP * LINK_HEIGHT, second.global_position + Vector3.UP * LINK_HEIGHT, ACTIVE_COLOR)
			visible_link_count += 1
	if surface_started:
		line_mesh.surface_end()
		links.mesh = line_mesh
	else:
		links.mesh = null
	_rebuild_range()

func _rebuild_range() -> void:
	var center := Vector3.ZERO
	var radius := 0.0
	if placement_active:
		center = placement_position
		radius = placement_definition.placement_c2_range()
		range_material.albedo_color = READY_COLOR if placement_ready else INCOMPLETE_COLOR
	elif selected_asset != null:
		center = selected_asset.global_position
		radius = selected_asset.c2_link_range()
		range_material.albedo_color = Color(0.16, 0.78, 0.95, 0.48)
	if radius <= 0.0:
		range_ring.visible = false
		return
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 2.5
	ring.outer_radius = radius
	ring.rings = 8
	ring.ring_segments = 96
	range_ring.mesh = ring
	range_ring.global_position = center + Vector3.UP * 2.0
	range_ring.visible = true

func _add_segment(mesh: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(finish)

func _add_dashed_segment(mesh: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	var distance := start.distance_to(finish)
	if distance <= 0.0:
		return
	var direction := start.direction_to(finish)
	var cursor := 0.0
	while cursor < distance:
		var dash_end := minf(cursor + DASH_LENGTH, distance)
		_add_segment(mesh, start + direction * cursor, start + direction * dash_end, color)
		cursor += DASH_LENGTH + DASH_GAP
