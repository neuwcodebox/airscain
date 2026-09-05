class_name ModelGeometry
extends RefCounted
## Small mesh vocabulary; content scenes own composition and proportions.

static func material(color: Color, metallic: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	return result

static func mesh(parent: Node3D, name_value: String, shape: Mesh, position: Vector3, finish: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = name_value
	visual.mesh = shape
	visual.position = position
	visual.material_override = finish
	parent.add_child(visual)
	return visual

static func box(parent: Node3D, name_value: String, size: Vector3, position: Vector3, finish: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, name_value, shape, position, finish)

static func strut(parent: Node3D, name_value: String, from: Vector3, to: Vector3, width: float, finish: Material) -> MeshInstance3D:
	var visual := box(parent, name_value, Vector3(width, from.distance_to(to), width), from.lerp(to, 0.5), finish)
	visual.basis = Basis(Quaternion(Vector3.UP, from.direction_to(to)))
	return visual

static func cylinder(parent: Node3D, name_value: String, radius: float, height: float, position: Vector3, finish: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 10
	return mesh(parent, name_value, shape, position, finish)

static func hull(stations: Array[Vector3]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for station: int in stations.size() - 1:
		for side: int in 8:
			var angle := TAU * float(side) / 8.0
			var next_angle := TAU * float(side + 1) / 8.0
			var first := stations[station]
			var next := stations[station + 1]
			var a := Vector3(cos(angle) * first.x, sin(angle) * first.y, first.z)
			var b := Vector3(cos(next_angle) * first.x, sin(next_angle) * first.y, first.z)
			var c := Vector3(cos(angle) * next.x, sin(angle) * next.y, next.z)
			var d := Vector3(cos(next_angle) * next.x, sin(next_angle) * next.y, next.z)
			for vertex: Vector3 in [a, c, b, b, c, d]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

static func wing(outline: PackedVector2Array, thickness: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for index: int in range(0, triangles.size(), 3):
		for side: float in [-1.0, 1.0]:
			var order := PackedInt32Array([0, 1, 2]) if side > 0.0 else PackedInt32Array([2, 1, 0])
			for corner: int in order:
				var point := outline[triangles[index + corner]]
				surface.add_vertex(Vector3(point.x, side * thickness * 0.5, point.y))
	for index: int in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		for vertex: Vector3 in [Vector3(a.x, -thickness * 0.5, a.y), Vector3(b.x, -thickness * 0.5, b.y), Vector3(a.x, thickness * 0.5, a.y), Vector3(b.x, -thickness * 0.5, b.y), Vector3(b.x, thickness * 0.5, b.y), Vector3(a.x, thickness * 0.5, a.y)]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()
