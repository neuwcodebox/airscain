class_name SmokeShadowFactory
extends RefCounted

const SHADOW_SHADER := preload("res://effects/smoke_shadow.gdshader")

class Proxy:
	extends RefCounted

	var mesh: Mesh
	var material: ShaderMaterial

	func _init(mesh_value: Mesh, material_value: ShaderMaterial) -> void:
		mesh = mesh_value
		material = material_value

static func create(source_mesh: Mesh, radial_segments: int = 8, rings: int = 4) -> Proxy:
	if source_mesh == null or source_mesh.get_surface_count() == 0:
		return null
	var source_material := source_mesh.surface_get_material(0) as StandardMaterial3D
	if source_material == null:
		return null
	var uses_billboard := source_material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED
	var shadow_mesh: Mesh
	if uses_billboard and source_mesh is QuadMesh:
		var source_quad := source_mesh as QuadMesh
		var sphere := SphereMesh.new()
		sphere.radius = maxf(source_quad.size.x, source_quad.size.y) * 0.42
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = radial_segments
		sphere.rings = rings
		shadow_mesh = sphere
	else:
		shadow_mesh = source_mesh.duplicate() as Mesh
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = SHADOW_SHADER
	shadow_material.set_shader_parameter("billboard_enabled", false if shadow_mesh is SphereMesh else uses_billboard)
	shadow_mesh.surface_set_material(0, shadow_material)
	return Proxy.new(shadow_mesh, shadow_material)
