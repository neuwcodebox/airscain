class_name CargoShip
extends Node3D

const HULL_LENGTH := 76.0
const HULL_WIDTH := 15.0

static var structure_meshes: Dictionary[String, Mesh] = {}
static var cargo_mesh: ArrayMesh
static var cargo_materials: Array[StandardMaterial3D] = []

var haze: DistantContactHaze

var wake: MeshInstance3D
var cargo_containers: Array[MeshInstance3D] = []

func _ready() -> void:
	if structure_meshes.is_empty():
		_build_hull()
		_build_deck()
		_build_bridge()
		for child: Node in get_children():
			if child is MeshInstance3D:
				structure_meshes[String(child.name)] = child.mesh
	else:
		for label: String in structure_meshes:
			var part := MeshInstance3D.new()
			part.name = label
			part.mesh = structure_meshes[label]
			add_child(part)
	_build_cargo()
	_build_lights()
	_build_wake()

func configure_haze(size: float) -> void:
	haze = DistantContactHaze.new()
	add_child(haze)
	haze.configure(self, size)
	haze.set_process(false)

func refresh_haze() -> void:
	if haze != null:
		haze.refresh()
		visible = haze.opacity > 0.001

func set_underway(underway: bool) -> void:
	if wake != null:
		wake.visible = underway

func set_cargo_remaining(fraction: float) -> void:
	var count := ceili(clampf(fraction, 0.0, 1.0) * float(cargo_containers.size()))
	for index: int in cargo_containers.size():
		cargo_containers[index].visible = index < count

func _material(color: Color, metallic: float = 0.0, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.72
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material

func _box(parent: Node3D, name_value: String, size: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = name_value
	part.mesh = mesh
	part.material_override = material
	part.position = position_value
	parent.add_child(part)
	return part

func _build_hull() -> void:
	# Longitudinal stations form a rounded stem, flared sides and a tapered transom.
	var stations: Array[Vector2] = [Vector2(-38, 0.15), Vector2(-35, 2.6), Vector2(-30, 5.3), Vector2(-23, 7.0), Vector2(-12, 7.5), Vector2(16, 7.5), Vector2(27, 6.9), Vector2(34, 5.5), Vector2(38, 4.3)]
	var hull := HarborGeometry.new()
	for band: int in 3:
		var levels := [-2.8, 0.15, 0.65, 4.8]
		var scales := [0.68, 0.91, 0.94, 1.0]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index: int in range(stations.size() - 1):
			for side: float in [-1.0, 1.0]:
				var a := Vector3(stations[index].y * side * scales[band], levels[band], stations[index].x)
				var b := Vector3(stations[index + 1].y * side * scales[band], levels[band], stations[index + 1].x)
				var c := Vector3(stations[index].y * side * scales[band + 1], levels[band + 1], stations[index].x)
				var d := Vector3(stations[index + 1].y * side * scales[band + 1], levels[band + 1], stations[index + 1].x)
				var vertices := PackedVector3Array([a, b, c, b, d, c] if side > 0 else [a, c, b, b, c, d])
				for vertex: Vector3 in vertices:
					surface.add_vertex(vertex)
		surface.generate_normals()
		hull.append(surface.commit(), Transform3D.IDENTITY, ["783e35", "c8b789", "294552"][band])
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(stations.size() - 1):
		var a := Vector3(-stations[index].y, 4.8, stations[index].x)
		var b := Vector3(stations[index].y, 4.8, stations[index].x)
		var c := Vector3(-stations[index + 1].y, 4.8, stations[index + 1].x)
		var d := Vector3(stations[index + 1].y, 4.8, stations[index + 1].x)
		for vertex: Vector3 in [a, b, c, b, d, c]:
			deck.add_vertex(vertex)
	deck.generate_normals()
	hull.append(deck.commit(), Transform3D.IDENTITY, "697771")
	hull.box(Vector3(8.6, 7.6, 0.18), Vector3(0, 1, 38), "294552")
	for side: float in [-1.0, 1.0]:
		for index: int in range(stations.size() - 1):
			var a := Vector3(stations[index].y * side, 5.85, stations[index].x)
			var b := Vector3(stations[index + 1].y * side, 5.85, stations[index + 1].x)
			hull.beam(a, b, 0.12, "d0d5c9")
			hull.beam(a - Vector3.UP * 0.55, b - Vector3.UP * 0.55, 0.08, "d0d5c9")
			var count := maxi(1, ceili(a.distance_to(b) / 2.5))
			for post: int in count:
				var at := a.lerp(b, float(post) / count)
				hull.beam(at, at - Vector3.UP, 0.1, "d0d5c9")
	hull.instance(self, "SculptedHullAndRails")

func _build_deck() -> void:
	var detail := HarborGeometry.new()
	for z: float in [-30.5, 34.0]:
		detail.cylinder(0.8, 0.8, Vector3(0, 5.3, z), "343e40")
		for side: float in [-1.0, 1.0]:
			detail.cylinder(0.35, 0.7, Vector3(side * 3.0, 5.1, z), "c0bdac")
			detail.beam(Vector3(side * 3.8, 5.5, z), Vector3(side * 2.2, 5.5, z), 0.25, "c0bdac")
	for row: int in 6:
		detail.box(Vector3(11.2, 0.35, 6.25), Vector3(0, 4.95, -19 + row * 6.4), "505d5c")
	detail.instance(self, "DeckEquipment")

func _build_cargo() -> void:
	var colors: Array[Color] = [Color("ac5a43"), Color("c0a370"), Color("4b747f"), Color("788477"), Color("adada0")]
	if cargo_mesh == null:
		cargo_mesh = HarborGeometry.container_mesh()
		for color: Color in colors:
			var material := _material(color)
			material.vertex_color_use_as_albedo = true
			cargo_materials.append(material)
	var mesh := cargo_mesh
	# Bottom tiers precede upper tiers so unloading never leaves floating containers.
	for level: int in 2:
		for row: int in 6:
			for lane: int in 4:
				var container := MeshInstance3D.new()
				container.mesh = mesh
				container.name = "Container%d" % cargo_containers.size()
				container.position = Vector3(-3.9 + lane * 2.6, 6.4 + level * 2.65, -19 + row * 6.4)
				container.material_override = cargo_materials[(row * 3 + lane + level * 2) % colors.size()]
				add_child(container)
				cargo_containers.append(container)

func _build_bridge() -> void:
	var bridge := HarborGeometry.new()
	bridge.box(Vector3(10.8, 5.4, 10.0), Vector3(0, 7.6, 26), "d7d9cc")
	bridge.box(Vector3(8.7, 3.0, 7.5), Vector3(0, 11.8, 25.0), "e0e1d3")
	bridge.box(Vector3(12.0, 0.35, 8.5), Vector3(0, 10.4, 24.5), "a0aaa3")
	bridge.box(Vector3(10.4, 0.35, 8.4), Vector3(0, 13.45, 25.0), "d7d9cc")
	for index: int in 7:
		bridge.box(Vector3(0.92, 1.05, 0.12), Vector3(-3.55 + index * 1.18, 12.05, 21.2), "294651")
	for side: float in [-1.0, 1.0]:
		for index: int in 4:
			bridge.box(Vector3(0.12, 0.85, 0.95), Vector3(side * 4.4, 12.0, 22.2 + index * 1.5), "294651")
			bridge.box(Vector3(0.12, 0.7, 0.7), Vector3(side * 5.45, 8.4, 22.5 + index * 2), "405860")
		bridge.box(Vector3(1.0, 0.85, 3.6), Vector3(side * 6.0, 7.2, 28), "c2763e")
		bridge.beam(Vector3(side * 5.6, 10.9, 20.5), Vector3(side * 5.6, 10.9, 28.5), 0.12, "e0e1d3")
	bridge.box(Vector3(2.6, 4.6, 3.0), Vector3(0, 14.9, 28), "aa724d")
	bridge.box(Vector3(2.75, 0.65, 3.15), Vector3(0, 17.0, 28), "303c40")
	bridge.beam(Vector3(0, 13.5, 23), Vector3(0, 20, 23), 0.22, "c6ccbe")
	bridge.beam(Vector3(-2.3, 18.1, 23), Vector3(2.3, 18.1, 23), 0.18, "c6ccbe")
	bridge.box(Vector3(3.0, 0.3, 0.6), Vector3(0, 19.2, 23), "d7d9cc")
	bridge.instance(self, "BridgeAndFittings")

func _build_lights() -> void:
	_box(self, "PortLight", Vector3(0.8, 0.8, 0.8), Vector3(-5.8, 11.0, 22.0), _material(Color("ff5949"), 0.0, true))
	_box(self, "StarboardLight", Vector3(0.8, 0.8, 0.8), Vector3(5.8, 11.0, 22.0), _material(Color("58d79a"), 0.0, true))
	_box(self, "MastLight", Vector3(0.7, 0.7, 0.7), Vector3(0.0, 20.1, 23.0), _material(Color("fff0bf"), 0.0, true))

func _build_wake() -> void:
	var foam := SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip: int in 3:
		for segment: int in 14:
			var t0 := float(segment) / 14.0
			var t1 := float(segment + 1) / 14.0
			var side := float(strip - 1)
			var start_z := 35.0 if strip == 1 else -29.0
			var length := 83.0 if strip == 1 else 102.0
			var width0 := lerpf(1.2, 6.0, t0)
			var width1 := lerpf(1.2, 6.0, t1)
			var x0 := side * (5.0 + t0 * 13.0)
			var x1 := side * (5.0 + t1 * 13.0)
			for lane: int in 2:
				var edge0 := float(lane - 1)
				var edge1 := float(lane)
				var points := PackedVector3Array([
					Vector3(x0 + edge0 * width0, 0, start_z + t0 * length),
					Vector3(x0 + edge1 * width0, 0, start_z + t0 * length),
					Vector3(x1 + edge0 * width1, 0, start_z + t1 * length),
					Vector3(x0 + edge1 * width0, 0, start_z + t0 * length),
					Vector3(x1 + edge1 * width1, 0, start_z + t1 * length),
					Vector3(x1 + edge0 * width1, 0, start_z + t1 * length)])
				var edges: Array[float] = [edge0, edge1, edge0, edge1, edge1, edge0]
				for index: int in points.size():
					var t := (points[index].z - start_z) / length
					var alpha := 0.23 * (1.0 - absf(edges[index])) * sin(PI * t) * (1.0 - t)
					foam.set_color(Color(0.8, 0.94, 0.93, alpha))
					foam.add_vertex(points[index])
	wake = MeshInstance3D.new()
	wake.name = "Wake"
	wake.mesh = foam.commit()
	wake.position.y = 0.3
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _material(Color.WHITE)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	wake.material_override = material
	add_child(wake)
