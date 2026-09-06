class_name LabeledRangeRing
extends MeshInstance3D
## Terrain-following range ribbon and a camera-readable circumference caption.

const SURFACE_CLEARANCE := 1.5
const SAMPLE_SPACING := 4.0

var radius: float = 0.0
var caption := Label3D.new()
var screen_bias := Vector2(0.66, 0.73)
var obstacles: Array[Control] = []
var battlefield: Battlefield
var _mesh_transform := Transform3D.IDENTITY
var _mesh_radius: float = -1.0
var _mesh_terrain: Mesh

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test = true
	caption.fixed_size = true
	caption.font_size = 28
	caption.outline_size = 8
	caption.pixel_size = 0.0004075
	caption.render_priority = 125
	caption.outline_render_priority = 124
	add_child(caption)

func set_range(value: float, title: String) -> void:
	visible = value > 0.0
	if not visible:
		return
	radius = value
	refresh_surface()
	caption.text = title

func refresh_surface() -> void:
	if radius <= 0.0 or not is_inside_tree():
		return
	var terrain_mesh: Mesh = battlefield.terrain.mesh if is_instance_valid(battlefield) else null
	if mesh != null and _mesh_transform == global_transform and _mesh_radius == radius and _mesh_terrain == terrain_mesh:
		return
	_mesh_transform = global_transform
	_mesh_radius = radius
	_mesh_terrain = terrain_mesh
	var segments := maxi(96, ceili(TAU * radius / SAMPLE_SPACING))
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for index: int in segments + 1:
		var angle := TAU * float(index % segments) / float(segments)
		vertices.append(_surface_point(angle, maxf(0.0, radius - 2.5)))
		vertices.append(_surface_point(angle, radius))
		if index < segments:
			var base := index * 2
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = ribbon

func _surface_point(angle: float, distance: float) -> Vector3:
	var point := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	if is_instance_valid(battlefield):
		var world := global_transform * point
		world.y = battlefield.flight_surface_height(world.x, world.z) + SURFACE_CLEARANCE
		return to_local(world)
	return point

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	refresh_surface()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var safe := Rect2(Vector2(130, 110), viewport_size - Vector2(260, 190))
	var preferred := viewport_size * screen_bias
	var blocked_regions: Array[Rect2] = []
	for control: Control in obstacles:
		if is_instance_valid(control) and control.is_visible_in_tree():
			blocked_regions.append(control.get_global_rect().grow(8.0))
	var caption_extent := Vector2(float(caption.text.length()) * 6.0 + 12.0, 16.0)
	var best := INF
	caption.visible = false
	for index: int in 64:
		var angle := TAU * float(index) / 64.0
		var point := _surface_point(angle, radius) + Vector3.UP * 2.5
		var world := global_transform * point
		if camera.is_position_behind(world):
			continue
		var screen := camera.unproject_position(world)
		if not safe.has_point(screen):
			continue
		var blocked := false
		var caption_rect := Rect2(screen - caption_extent, caption_extent * 2.0)
		for region: Rect2 in blocked_regions:
			if region.intersects(caption_rect):
				blocked = true
				break
		if blocked:
			continue
		var score := screen.distance_squared_to(preferred)
		if score < best:
			best = score
			caption.position = point
			caption.visible = true
	var material := material_override as BaseMaterial3D
	if material != null:
		var color := material.albedo_color
		color.a = 1.0
		caption.modulate = color

static func primary_radius(definition: DefenseDefinition) -> float:
	if definition.placement_support_range() > 0.0:
		return definition.placement_support_range()
	if definition.tactical_overlay_mode() == &"none":
		return 0.0
	return definition.tactical_range()

static func primary_title(definition: DefenseDefinition) -> String:
	match definition.tactical_overlay_mode():
		&"sensor": return "탐지 범위"
		&"weapon": return "교전 범위"
		&"support": return "지원 범위"
		&"electronic": return "전자전 범위"
	return "작동 범위"
