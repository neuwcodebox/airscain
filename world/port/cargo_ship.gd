class_name CargoShip
extends Node3D

const HULL_LENGTH := 76.0
const HULL_WIDTH := 15.0

var wake: MeshInstance3D
var cargo_containers: Array[MeshInstance3D] = []

func _ready() -> void:
	_build_hull()
	_build_deck()
	_build_cargo()
	_build_bridge()
	_build_lights()
	_build_wake()

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
	var outline := PackedVector2Array([
		Vector2(-HULL_WIDTH * 0.5, 32.0), Vector2(HULL_WIDTH * 0.5, 32.0),
		Vector2(HULL_WIDTH * 0.5, -24.0), Vector2(5.0, -34.0),
		Vector2(0.0, -HULL_LENGTH * 0.5), Vector2(-5.0, -34.0),
		Vector2(-HULL_WIDTH * 0.5, -24.0),
	])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in outline.size():
		var next := (index + 1) % outline.size()
		var a := Vector3(outline[index].x, 4.5, outline[index].y)
		var b := Vector3(outline[next].x, 4.5, outline[next].y)
		var c := Vector3(outline[index].x * 0.86, -3.0, outline[index].y * 0.94)
		var d := Vector3(outline[next].x * 0.86, -3.0, outline[next].y * 0.94)
		for point: Vector3 in [a, b, c, b, d, c]:
			surface.add_vertex(point)
	for index: int in range(1, outline.size() - 1):
		for vertex_index: int in [0, index, index + 1]:
			var point := outline[vertex_index]
			surface.add_vertex(Vector3(point.x, 4.5, point.y))
	surface.generate_normals()
	var body := MeshInstance3D.new()
	body.name = "SteelHull"
	body.mesh = surface.commit()
	body.material_override = _material(Color("263e49"), 0.27)
	add_child(body)
	_box(self, "Waterline", Vector3(HULL_WIDTH * 0.94, 0.45, 53.0), Vector3(0.0, 0.3, 2.5), _material(Color("a05c3b")))

func _build_deck() -> void:
	_box(self, "MainDeck", Vector3(12.8, 0.55, 58.0), Vector3(0.0, 4.55, 2.0), _material(Color("727873"), 0.25))
	_box(self, "ForwardBulwark", Vector3(10.0, 1.6, 0.55), Vector3(0.0, 5.1, -27.0), _material(Color("d7dbd2")))

func _build_cargo() -> void:
	var colors: Array[Color] = [Color("bb6040"), Color("b79b65"), Color("527687"), Color("798b70"), Color("d0b380")]
	for row: int in 4:
		for side: int in 2:
			for level: int in 2:
				var index := row * 4 + side * 2 + level
				var container := _box(self, "Container%d" % index, Vector3(5.2, 2.6, 10.0), Vector3(-3.0 if side == 0 else 3.0, 6.0 + float(level) * 2.7, -16.0 + float(row) * 10.5), _material(colors[index % colors.size()]))
				container.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				cargo_containers.append(container)

func _build_bridge() -> void:
	var white := _material(Color("d7dbd2"))
	_box(self, "SternDeckhouse", Vector3(12.0, 6.0, 11.0), Vector3(0.0, 8.0, 25.0), white)
	_box(self, "Bridge", Vector3(10.0, 3.2, 7.0), Vector3(0.0, 12.1, 23.0), white)
	_box(self, "BridgeWindows", Vector3(10.1, 1.15, 0.2), Vector3(0.0, 12.6, 19.4), _material(Color("354d58"), 0.2))
	_box(self, "Funnel", Vector3(3.1, 4.0, 3.4), Vector3(0.0, 15.4, 28.0), _material(Color("9a7444")))

func _build_lights() -> void:
	_box(self, "PortLight", Vector3(0.8, 0.8, 0.8), Vector3(-7.8, 6.3, -8.0), _material(Color("ff5949"), 0.0, true))
	_box(self, "StarboardLight", Vector3(0.8, 0.8, 0.8), Vector3(7.8, 6.3, -8.0), _material(Color("58d79a"), 0.0, true))
	_box(self, "MastLight", Vector3(0.7, 0.7, 0.7), Vector3(0.0, 18.3, 22.0), _material(Color("fff0bf"), 0.0, true))

func _build_wake() -> void:
	var wake_mesh := PlaneMesh.new()
	wake_mesh.size = Vector2(16.0, 45.0)
	wake = MeshInstance3D.new()
	wake.name = "Wake"
	wake.mesh = wake_mesh
	wake.position = Vector3(0.0, 0.1, 55.0)
	var material := _material(Color(0.75, 0.91, 0.89, 0.18))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake.material_override = material
	add_child(wake)
