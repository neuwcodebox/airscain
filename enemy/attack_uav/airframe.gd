extends Node3D
## Airframe proportions are authored by each content scene, independent of AI.

@export var jet: bool = false
static var _geometry: Dictionary[bool, Array] = {}

func _ready() -> void:
	if _geometry.has(jet):
		_install_geometry(_geometry[jet])
		return
	var skin := ModelGeometry.material(Color("8b9384") if not jet else Color("687a80"), 0.35, 0.55)
	var underside := ModelGeometry.material(Color("414b48"), 0.3)
	var glass := ModelGeometry.material(Color("203d49"), 0.6, 0.18)
	var marking := ModelGeometry.material(Color("b7a080"))
	var stations: Array[Vector3]
	if jet:
		stations = [Vector3(0.02, 0.02, -10), Vector3(0.9, 0.75, -6), Vector3(1.8, 1.3, -2), Vector3(2.1, 1.2, 4), Vector3(1.5, 0.85, 8), Vector3(0.02, 0.02, 8.1)]
	else:
		stations = [Vector3(0.03, 0.03, -6.8), Vector3(0.75, 0.7, -4.6), Vector3(1.15, 0.85, -1.0), Vector3(0.85, 0.7, 2.5), Vector3(0.3, 0.35, 5), Vector3(0.03, 0.03, 5.1)]
	ModelGeometry.mesh(self, "FacetedFuselage", ModelGeometry.hull(stations), Vector3.ZERO, skin)
	for side: float in [-1.0, 1.0]:
		var points := PackedVector2Array([Vector2(0.6, -2.8), Vector2(10.5, 3.0), Vector2(9.7, 5.4), Vector2(1.0, 3.3)]) if jet else PackedVector2Array([Vector2(0.7, -0.8), Vector2(7.8, 0.5), Vector2(7.5, 2.1), Vector2(0.7, 1.4)])
		var wing := ModelGeometry.mesh(self, "SweptWing" if jet else "LongWing", ModelGeometry.wing(points, 0.20), Vector3.ZERO, skin)
		wing.scale.x = side
		var tail_points := PackedVector2Array([Vector2(0.5, 4.0), Vector2(4.4 if jet else 3.0, 6.0 if jet else 5.0), Vector2(3.7 if jet else 2.8, 7.4 if jet else 5.7), Vector2(0.3, 6.5 if jet else 5.2)])
		var tail := ModelGeometry.mesh(self, "Tailplane", ModelGeometry.wing(tail_points, 0.16), Vector3(0, 0.4, 0), skin)
		tail.scale.x = side
		tail.rotation.z = side * deg_to_rad(58.0 if not jet else 5.0)
		ModelGeometry.box(self, "WingMark", Vector3(0.7, 0.035, 1.1), Vector3(side * (7 if jet else 5.5), 0.13, 2.8 if jet else 1.1), marking)
		if jet:
			var intake := ModelGeometry.mesh(self, "AirIntake", ModelGeometry.hull([Vector3(0.02, 0.02, -3.3), Vector3(0.65, 0.65, -3), Vector3(0.7, 0.6, 4.0), Vector3(0.02, 0.02, 4.2)]), Vector3(side * 1.8, -0.65, 0), underside)
			intake.scale = Vector3.ONE
			var fin := ModelGeometry.mesh(self, "TwinFin", ModelGeometry.wing(PackedVector2Array([Vector2(0, 3.8), Vector2(3.6, 6.0), Vector2(3.3, 7.6), Vector2(0, 7.3)]), 0.18), Vector3(side * 1.3, 0.7, 0), skin)
			fin.rotation.z = side * deg_to_rad(73.0)
			fin.scale.x = side
			var nozzle := ModelGeometry.cylinder(self, "ExhaustNozzle", 0.74, 1.3, Vector3(side * 1.25, 0, 7.9), underside)
			nozzle.rotation.x = PI * 0.5
	if jet:
		ModelGeometry.mesh(self, "Cockpit", ModelGeometry.hull([Vector3(0.02, 0.02, -6), Vector3(0.65, 0.9, -4), Vector3(0.7, 0.7, -1.5), Vector3(0.02, 0.02, -0.5)]), Vector3(0, 0.85, 0), glass)
	else:
		var sensor := SphereMesh.new()
		sensor.radius = 0.55
		sensor.height = 1.1
		sensor.radial_segments = 8
		sensor.rings = 4
		ModelGeometry.mesh(self, "OpticalTurret", sensor, Vector3(0, -0.8, -3), glass)
		ModelGeometry.box(self, "PusherPropeller", Vector3(0.15, 3.4, 0.12), Vector3(0, 0, 5.3), underside)
	var parts: Array[MeshInstance3D] = []
	for child: Node in get_children():
		if child is MeshInstance3D:
			var part := child as MeshInstance3D
			var finish := part.get_active_material(0) as StandardMaterial3D
			if finish != null and not finish.emission_enabled:
				parts.append(part)
	var combined := ModelGeometry.combine_static_parts(parts)
	_geometry[jet] = combined
	for part: MeshInstance3D in parts:
		part.free()
	_install_geometry(combined)

func _install_geometry(shapes: Array) -> void:
	for index: int in shapes.size():
		var shape := shapes[index] as ArrayMesh
		ModelGeometry.mesh(self, "Airframe" if index == 0 else "Airframe%d" % index, shape, Vector3.ZERO, shape.surface_get_material(0))
