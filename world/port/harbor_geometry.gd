class_name HarborGeometry
extends RefCounted
## Static details share a mesh per color, including across repeated ship instances.
var surfaces: Dictionary[String, SurfaceTool] = {}

func box(size: Vector3, at: Vector3, color: String, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	append(mesh, Transform3D(basis, at), color)

func beam(a: Vector3, b: Vector3, width: float, color: String) -> void:
	var direction := b - a
	var axis := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
	box(Vector3(width, width, direction.length()), (a + b) * 0.5, color, Basis.looking_at(direction, axis))

func cylinder(radius: float, height: float, at: Vector3, color: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	append(mesh, Transform3D(Basis.IDENTITY, at), color)

func append(mesh: Mesh, transform: Transform3D, color: String) -> void:
	# A shared surface keeps only indexed triangles once any indexed part joins it,
	# so unindexed parts are indexed first rather than silently dropped.
	if mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == null:
		var indexed := SurfaceTool.new()
		indexed.create_from(mesh, 0)
		indexed.index()
		mesh = indexed.commit()
	if not surfaces.has(color):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[color] = surface
	surfaces[color].append_from(mesh, 0, transform)

func mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	for color: String in surfaces:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = 0.78
		surfaces[color].set_material(material)
		surfaces[color].commit(result)
	return result

func instance(parent: Node3D, label: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh()
	parent.add_child(part)
	return part

static func container_mesh() -> ArrayMesh:
	var geometry := HarborGeometry.new()
	geometry.box(Vector3(2.44, 2.59, 6.06), Vector3.ZERO, "ffffff")
	for side: float in [-1.0, 1.0]:
		for rib: int in 15:
			geometry.box(Vector3(0.09, 2.32, 0.1), Vector3(side * 1.24, 0.0, -2.8 + rib * 0.4), "d5d9d7")
		for edge: float in [-1.0, 1.0]:
			geometry.box(Vector3(0.12, 2.65, 0.12), Vector3(side * 1.2, 0.0, edge * 3.0), "c5cccb")
		geometry.box(Vector3(0.07, 2.25, 0.08), Vector3(side * 0.65, 0.0, 3.08), "d5d9d7")
	for rib: int in 15:
		geometry.box(Vector3(2.2, 0.06, 0.12), Vector3(0.0, 1.32, -2.8 + rib * 0.4), "d5d9d7")
	var source := geometry.mesh()
	var combined := SurfaceTool.new()
	combined.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface: int in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tint := (source.surface_get_material(surface) as StandardMaterial3D).albedo_color
		for index: int in indices:
			combined.set_color(tint)
			combined.set_normal(normals[index])
			combined.add_vertex(vertices[index])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	combined.set_material(material)
	return combined.commit()
