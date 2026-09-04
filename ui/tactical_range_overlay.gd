class_name TacticalRangeOverlay
extends Node3D

const MODE_NONE := &"none"
const MODE_SENSOR := &"sensor"
const MODE_WEAPON := &"weapon"
const MODE_SUPPORT := &"support"
const MODE_ELECTRONIC := &"electronic"

var mode: StringName = MODE_NONE
var defense_parent: Node3D
var registry: ThreatRegistry
var support_manager: SupportManager
var rebuild_remaining: float = 0.0
var line_mesh := MeshInstance3D.new()
var line_material := StandardMaterial3D.new()

func _ready() -> void:
	line_mesh.name = "Ranges"
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	line_mesh.material_override = line_material
	add_child(line_mesh)
	visible = false

func configure(defense_parent_value: Node3D, registry_value: ThreatRegistry, support: SupportManager) -> void:
	defense_parent = defense_parent_value
	registry = registry_value
	support_manager = support

func set_mode(mode_value: StringName) -> void:
	mode = mode_value
	visible = mode != MODE_NONE
	rebuild_remaining = 0.0
	_rebuild()

func _process(delta: float) -> void:
	if mode == MODE_NONE:
		return
	rebuild_remaining -= delta
	if rebuild_remaining <= 0.0:
		rebuild_remaining += 0.25
		_rebuild()

func _rebuild() -> void:
	if mode == MODE_NONE or defense_parent == null:
		line_mesh.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var vertex_count := 0
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit == null or not unit.active:
			continue
		match mode:
			MODE_SENSOR:
				if unit.definition.tactical_overlay_mode() == MODE_SENSOR:
					vertex_count += _add_ring(mesh, unit.global_position, unit.definition.tactical_range() * unit.operational_efficiency(), Color(0.18, 0.82, 1.0, 0.72), 96, 0)
			MODE_WEAPON:
				if unit.definition.tactical_overlay_mode() == MODE_WEAPON:
					vertex_count += _add_ring(mesh, unit.global_position, unit.definition.tactical_range() * unit.operational_efficiency(), Color(1.0, 0.48, 0.18, 0.72), 96, 2)
			MODE_SUPPORT:
				if unit.definition.tactical_overlay_mode() == MODE_SUPPORT:
					vertex_count += _add_ring(mesh, unit.global_position, unit.definition.tactical_range(), Color(0.36, 1.0, 0.54, 0.86), 96, 0)
			MODE_ELECTRONIC:
				var interference := registry.jamming_at(unit.global_position) if registry != null else 0.0
				if interference > 0.02:
					vertex_count += _add_ring(mesh, unit.global_position, lerpf(18.0, 42.0, interference), Color(0.92, 0.3, 1.0, 0.45 + interference * 0.5), 32, 2)
	if mode == MODE_SUPPORT:
		vertex_count += _add_support_relations(mesh)
	if vertex_count > 0:
		mesh.surface_end()
		line_mesh.mesh = mesh
	else:
		line_mesh.mesh = null

func _add_support_relations(mesh: ImmediateMesh) -> int:
	if support_manager == null or support_manager.facilities.is_empty():
		return 0
	var vertex_count := 0
	for task: Dictionary in support_manager.tasks:
		var target := support_manager.consumers.get(int(task.target_defense_id)) as DefenseUnit
		if target == null or not is_instance_valid(target):
			continue
		var facility := support_manager.service_facility_for(target)
		if facility == null:
			continue
		vertex_count += _add_dashed_segment(mesh, facility.global_position + Vector3.UP * 8.0, target.global_position + Vector3.UP * 8.0, Color(0.36, 1.0, 0.54, 0.82), 12)
	return vertex_count

func _add_ring(mesh: ImmediateMesh, center: Vector3, radius: float, color: Color, segments: int, gap_stride: int) -> int:
	var vertex_count := 0
	for index: int in segments:
		if gap_stride > 0 and index % (gap_stride * 2) >= gap_stride:
			continue
		var first_angle := TAU * float(index) / float(segments)
		var second_angle := TAU * float(index + 1) / float(segments)
		_add_segment(mesh, center + Vector3(cos(first_angle) * radius, 3.0, sin(first_angle) * radius), center + Vector3(cos(second_angle) * radius, 3.0, sin(second_angle) * radius), color)
		vertex_count += 2
	return vertex_count

func _add_dashed_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color, dash_count: int) -> int:
	for index: int in range(0, dash_count, 2):
		_add_segment(mesh, from.lerp(to, float(index) / float(dash_count)), from.lerp(to, float(index + 1) / float(dash_count)), color)
	return dash_count

func _add_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)
