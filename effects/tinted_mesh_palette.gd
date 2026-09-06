class_name TintedMeshPalette
extends RefCounted
## One surface for untextured airframes with a common runtime paint color.
## Metallic/roughness stay per source surface via a nearest-filtered data palette.

static func combine(surfaces: Array[ArrayMesh]) -> ArrayMesh:
	assert(not surfaces.is_empty())
	var palette := Image.create(surfaces.size(), 1, false, Image.FORMAT_RGBAF)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for slot: int in surfaces.size():
		var mesh := surfaces[slot]
		assert(mesh.get_surface_count() == 1)
		var finish := mesh.surface_get_material(0) as StandardMaterial3D
		assert(finish != null and finish.albedo_texture == null and not finish.emission_enabled)
		palette.set_pixel(slot, 0, Color(finish.metallic, finish.roughness, 0, 1))
		var arrays := mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in indices:
			builder.set_normal(normals[index])
			builder.set_color(finish.albedo_color)
			builder.set_uv(Vector2((slot + 0.5) / surfaces.size(), 0.5))
			builder.add_vertex(positions[index])
	var texture := ImageTexture.create_from_image(palette)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.metallic = 1.0
	material.roughness = 1.0
	material.metallic_texture = texture
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness_texture = texture
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	builder.set_material(material)
	builder.index()
	return builder.commit()
