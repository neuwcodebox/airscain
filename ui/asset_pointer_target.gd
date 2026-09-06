class_name AssetPointerTarget
extends RefCounted

const OUTLINE_SHADER := preload("res://ui/asset_hover_outline.gdshader")
const CLICK_PADDING := 10.0
const MINIMUM_TARGET_SIZE := 36.0
static var outline_material: ShaderMaterial

var meshes: Array[MeshInstance3D] = []
var mesh_bounds: Array[AABB] = []
var bounds: AABB
var hovered: bool = false

func prepare(unit: Node3D) -> void:
	_collect(unit, Transform3D.IDENTITY)
	if outline_material == null:
		outline_material = ShaderMaterial.new()
		outline_material.shader = OUTLINE_SHADER

func _collect(node: Node, local_transform: Transform3D) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.visible:
			return
		var material := instance.material_override as BaseMaterial3D
		if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return
		var local_bounds: AABB = local_transform * instance.get_aabb()
		bounds = local_bounds if meshes.is_empty() else bounds.merge(local_bounds)
		meshes.append(instance)
		mesh_bounds.append(instance.get_aabb())
	for child: Node in node.get_children():
		var child_transform := local_transform
		if child is Node3D:
			child_transform *= (child as Node3D).transform
		_collect(child, child_transform)

func screen_rect(unit: Node3D, camera: Camera3D) -> Rect2:
	# Only nearby pointer candidates need articulation-aware bounds. Mesh geometry
	# stays cached, while rotating dishes, barrels and launch tubes stay pickable.
	var current_bounds := AABB()
	var inverse := unit.global_transform.affine_inverse()
	for index: int in meshes.size():
		var local_bounds: AABB = (inverse * meshes[index].global_transform) * mesh_bounds[index]
		current_bounds = local_bounds if index == 0 else current_bounds.merge(local_bounds)
	return _project_bounds(current_bounds, unit, camera)

func _project_bounds(local_bounds: AABB, unit: Node3D, camera: Camera3D) -> Rect2:
	var rect := Rect2()
	for index: int in 8:
		var point := unit.global_transform * local_bounds.get_endpoint(index)
		if camera.is_position_behind(point):
			return Rect2()
		var screen := camera.unproject_position(point)
		rect = Rect2(screen, Vector2.ZERO) if index == 0 else rect.expand(screen)
	return rect

func hit_score(unit: Node3D, camera: Camera3D, position: Vector2) -> float:
	if meshes.is_empty() or not unit.is_visible_in_tree():
		return INF
	var coarse := _project_bounds(bounds.grow(bounds.size.length()), unit, camera)
	if coarse.has_area() and not coarse.grow(MINIMUM_TARGET_SIZE).has_point(position):
		return INF
	var rect := screen_rect(unit, camera)
	if not rect.has_area():
		return INF
	var size := rect.size + Vector2.ONE * CLICK_PADDING * 2.0
	size = size.max(Vector2.ONE * MINIMUM_TARGET_SIZE)
	if not Rect2(rect.get_center() - size * 0.5, size).has_point(position):
		return INF
	# Direct model hits win over another asset's padded margin.
	return position.distance_to(rect.get_center()) + (0.0 if rect.has_point(position) else 10000.0)

func set_hovered(enabled: bool) -> void:
	if hovered == enabled:
		return
	hovered = enabled
	for instance: MeshInstance3D in meshes:
		if is_instance_valid(instance):
			instance.material_overlay = outline_material if enabled else null
