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
	if unit is DefenseUnit:
		var defense := unit as DefenseUnit
		var marker_score := INF
		for parent: Node3D in [defense.identity_marker, defense.status_marker]:
			if not is_instance_valid(parent):
				continue
			for child: Node in parent.get_children():
				if child is Sprite3D or child is Label3D:
					var rect := marker_screen_rect(child as GeometryInstance3D, camera)
					if rect.has_area() and rect.grow(4.0).has_point(position):
						marker_score = minf(marker_score, position.distance_to(rect.get_center()))
		if is_finite(marker_score):
			return marker_score
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

static func marker_screen_rect(marker: GeometryInstance3D, camera: Camera3D) -> Rect2:
	if not marker.is_visible_in_tree() or camera.is_position_behind(marker.global_position):
		return Rect2()
	# Fixed-size billboards cancel perspective depth, but retain projection scale.
	var projection := camera.get_camera_projection()
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var scale := Vector2(projection.x.x * viewport_size.x, projection.y.y * viewport_size.y) * 0.5 * marker.global_basis.get_scale().x
	var rect: Rect2
	var pixel_size: float
	if marker is Sprite3D:
		var sprite := marker as Sprite3D
		rect = sprite.get_item_rect()
		pixel_size = sprite.pixel_size
	else:
		var label := marker as Label3D
		var font := label.font if label.font != null else ThemeDB.fallback_font
		var size := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
		size.y = font.get_height(label.font_size)
		size += Vector2.ONE * label.outline_size * 2.0
		rect = Rect2(label.offset - size * 0.5, size)
		pixel_size = label.pixel_size
	var origin := camera.unproject_position(marker.global_position)
	return Rect2(origin + Vector2(rect.position.x, -rect.end.y) * scale * pixel_size, rect.size * scale * pixel_size)

func set_hovered(enabled: bool) -> void:
	if hovered == enabled:
		return
	hovered = enabled
	for instance: MeshInstance3D in meshes:
		if is_instance_valid(instance):
			instance.material_overlay = outline_material if enabled else null
