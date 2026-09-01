class_name C2Overlay
extends Node3D

var c2_network: Node
var selected_asset: DefenseUnit
var show_all_links: bool = false
var visible_link_count: int = 0

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
	show_all_links = not show_all_links
	visible = show_all_links or selected_asset != null
	_rebuild()

func _rebuild() -> void:
	visible_link_count = 0
	var line_mesh := ImmediateMesh.new()
	var surface_started := false
	if c2_network != null:
		var active_links: Array = c2_network.call("active_links")
		for link: Array in active_links:
			var first := link[0] as DefenseUnit
			var second := link[1] as DefenseUnit
			if not show_all_links and selected_asset != first and selected_asset != second:
				continue
			if not surface_started:
				line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				surface_started = true
			line_mesh.surface_set_color(Color(0.12, 0.82, 1.0, 0.82))
			line_mesh.surface_add_vertex(first.global_position + Vector3.UP * 9.0)
			line_mesh.surface_add_vertex(second.global_position + Vector3.UP * 9.0)
			visible_link_count += 1
	if surface_started:
		line_mesh.surface_end()
		links.mesh = line_mesh
	else:
		links.mesh = null
	_rebuild_range()

func _rebuild_range() -> void:
	if selected_asset == null or selected_asset.c2_link_range() <= 0.0:
		range_ring.visible = false
		return
	var ring := TorusMesh.new()
	ring.inner_radius = selected_asset.c2_link_range() - 2.5
	ring.outer_radius = selected_asset.c2_link_range()
	ring.rings = 8
	ring.ring_segments = 96
	range_ring.mesh = ring
	range_ring.global_position = selected_asset.global_position + Vector3.UP * 2.0
	range_ring.visible = true
