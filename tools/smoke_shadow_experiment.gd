extends RefCounted
## Diagnostic alternative; gameplay retains sphere proxies until frame-time
## improvement is repeatable on the target renderer.

const SHADER := preload("res://tools/smoke_shadow_impostor.gdshader")

static func make_impostor(sphere: SphereMesh) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * sphere.radius * 2.0
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("shadow_radius", sphere.radius)
	var source := sphere.material as ShaderMaterial
	for parameter: Dictionary in source.shader.get_shader_uniform_list():
		if parameter.name != "billboard_enabled":
			material.set_shader_parameter(parameter.name, source.get_shader_parameter(parameter.name))
	mesh.material = material
	return mesh
