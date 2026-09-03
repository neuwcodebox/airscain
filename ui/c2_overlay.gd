class_name C2Overlay
extends Node3D

const C2_COLOR := Color(0.12, 0.82, 1.0, 0.82)
const SUPPORT_COLOR := Color(0.36, 1.0, 0.54, 0.9)
const INCOMPLETE_COLOR := Color(1.0, 0.58, 0.18, 0.92)
const LINK_HEIGHT := 9.0

var c2_network: Node
var support_manager: SupportManager
var selected_asset: DefenseUnit
var show_all_links: bool = false
var visible_link_count: int = 0
var visible_c2_link_count: int = 0
var visible_support_link_count: int = 0
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

func configure(network: Node, support: SupportManager) -> void:
	c2_network = network
	support_manager = support

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
	placement_active = active and definition != null
	visible = placement_active or show_all_links or selected_asset != null
	_rebuild()

func _rebuild() -> void:
	visible_link_count = 0
	visible_c2_link_count = 0
	visible_support_link_count = 0
	placement_ready = true
	var line_mesh := ImmediateMesh.new()
	var surface_started := false
	if placement_active:
		if c2_network != null and placement_definition.placement_c2_range() > 0.0:
			var preview_result: Dictionary = c2_network.call("placement_preview", placement_definition, placement_position)
			placement_ready = bool(preview_result.ready)
			var preview_links: Array = preview_result.links
			for endpoint: DefenseUnit in preview_links:
				surface_started = _ensure_surface(line_mesh, surface_started)
				_add_relation(line_mesh, placement_position, endpoint.global_position, C2_COLOR)
				visible_c2_link_count += 1
				visible_link_count += 1
	elif c2_network != null:
		var active_links: Array = c2_network.call("active_links")
		for link: Array in active_links:
			var first := link[0] as DefenseUnit
			var second := link[1] as DefenseUnit
			var touches_selection := selected_asset == first or selected_asset == second
			if not show_all_links and not touches_selection:
				continue
			surface_started = _ensure_surface(line_mesh, surface_started)
			_add_relation(line_mesh, first.global_position, second.global_position, C2_COLOR)
			visible_link_count += 1
			if touches_selection or selected_asset == null:
				visible_c2_link_count += 1
	var support_relations := _support_relations()
	for relation: Array in support_relations:
		surface_started = _ensure_surface(line_mesh, surface_started)
		_add_relation(line_mesh, relation[0], relation[1], SUPPORT_COLOR)
		visible_support_link_count += 1
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
		if placement_definition is not SupportFacilityDefinition:
			radius = placement_definition.placement_c2_range()
			range_material.albedo_color = C2_COLOR if placement_ready else INCOMPLETE_COLOR
	elif selected_asset != null:
		center = selected_asset.global_position
		if selected_asset is SupportFacility:
			radius = (selected_asset as SupportFacility).service_range()
			range_material.albedo_color = SUPPORT_COLOR
		else:
			radius = selected_asset.c2_link_range()
			range_material.albedo_color = C2_COLOR
	if radius <= 0.0:
		range_ring.visible = false
		return
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 2.5
	ring.outer_radius = radius
	ring.rings = 96
	ring.ring_segments = 8
	range_ring.mesh = ring
	range_ring.global_position = center + Vector3.UP * 2.0
	range_ring.visible = true

func _add_segment(mesh: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(finish)

func _ensure_surface(mesh: ImmediateMesh, started: bool) -> bool:
	if not started:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	return true

func _add_relation(mesh: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	_add_segment(mesh, start + Vector3.UP * LINK_HEIGHT, finish + Vector3.UP * LINK_HEIGHT, color)

func _support_relations() -> Array[Array]:
	var result: Array[Array] = []
	if support_manager == null:
		return result
	if placement_active:
		if placement_definition is SupportFacilityDefinition:
			var service_range := (placement_definition as SupportFacilityDefinition).service_range
			for unit: DefenseUnit in support_manager.serviceable_units_from(placement_position, service_range):
				result.append([placement_position, unit.global_position])
		else:
			var provider := support_manager.service_facility_for_position(placement_position)
			if provider != null:
				result.append([placement_position, provider.global_position])
	elif selected_asset is SupportFacility:
		var facility := selected_asset as SupportFacility
		for unit: DefenseUnit in support_manager.serviceable_units_from(facility.global_position, facility.service_range(), facility):
			result.append([facility.global_position, unit.global_position])
	elif selected_asset != null:
		var provider := support_manager.service_facility_for(selected_asset)
		if provider != null and provider != selected_asset:
			result.append([selected_asset.global_position, provider.global_position])
	return result
