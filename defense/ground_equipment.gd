class_name GroundEquipment
extends Node3D
## Static support dressing placed beside an emplacement: a ribbed power container
## with a roof unit, an optional generator and a cable run toward the equipment.
## Content scenes choose placement; parts merge into cached per-material meshes.

@export var container_size := Vector3(2.4, 2.6, 6.0)
@export var generator: bool = true
## Local end point of the ground cable, or zero for none.
@export var cable_to := Vector3.ZERO

static var _geometry: Dictionary[String, Array] = {}

func _ready() -> void:
	var key := "%s|%s|%s" % [container_size, generator, cable_to]
	if not _geometry.has(key):
		_build()
	_geometry[key] = ModelGeometry.replace_static_children(self, _geometry.get(key, [] as Array[ArrayMesh]))

func _build() -> void:
	var body := ModelGeometry.material(Color("4d5747"), 0.15, 0.75)
	var trim := ModelGeometry.material(Color("2d3431"), 0.3, 0.6)
	var vent := ModelGeometry.material(Color("1b2022"), 0.2, 0.85)
	var size := container_size
	ModelGeometry.box(self, "Container", size, Vector3(0.0, size.y * 0.5, 0.0), body)
	var ribs := maxi(3, int(size.z / 0.9))
	for index: int in ribs:
		var z := -size.z * 0.5 + (float(index) + 0.5) * size.z / float(ribs)
		ModelGeometry.box(self, "Rib", Vector3(size.x + 0.08, size.y * 0.86, 0.14), Vector3(0.0, size.y * 0.5, z), trim)
	ModelGeometry.box(self, "Doors", Vector3(size.x * 0.9, size.y * 0.9, 0.1), Vector3(0.0, size.y * 0.5, size.z * 0.5 + 0.05), trim)
	ModelGeometry.box(self, "RoofUnit", Vector3(1.4, 0.7, 1.6), Vector3(0.0, size.y + 0.35, -size.z * 0.25), trim)
	ModelGeometry.box(self, "RoofGrille", Vector3(1.0, 0.06, 1.2), Vector3(0.0, size.y + 0.73, -size.z * 0.25), vent)
	if generator:
		var generator_center := Vector3(size.x * 0.5 + 1.2, 0.8, size.z * 0.18)
		ModelGeometry.box(self, "Generator", Vector3(1.6, 1.6, 2.6), generator_center, body)
		ModelGeometry.box(self, "GeneratorVent", Vector3(1.64, 0.9, 0.9), generator_center + Vector3(0.0, 0.1, -0.7), vent)
		ModelGeometry.cylinder(self, "Exhaust", 0.14, 1.3, generator_center + Vector3(0.4, 1.4, 0.8), vent)
	if cable_to != Vector3.ZERO:
		ModelGeometry.strut(self, "Cable", Vector3(-size.x * 0.5, 0.12, -size.z * 0.3), cable_to, 0.22, vent)
