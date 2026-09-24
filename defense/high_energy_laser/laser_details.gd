extends Node3D
## Static dressing for the laser's rotating assemblies. The glowing emitter stays a
## separate node; the beam director encloses it so only its lens face shows.

@export_enum("turret", "director") var part: String = "turret"

static var _geometry: Dictionary[String, Array] = {}

func _ready() -> void:
	if not _geometry.has(part):
		_build()
	_geometry[part] = ModelGeometry.replace_static_children(self, _geometry.get(part, [] as Array[ArrayMesh]))

func _build() -> void:
	var hull := ModelGeometry.material(Color("34484b"), 0.45, 0.45)
	var dark := ModelGeometry.material(Color("1c2426"), 0.35, 0.55)
	var sensor := ModelGeometry.material(Color("0f1416"), 0.6, 0.2)
	match part:
		"turret":
			for side: float in [-1.0, 1.0]:
				ModelGeometry.box(self, "Cheek", Vector3(0.7, 4.2, 6.6), Vector3(side * 3.8, -0.1, 0.3), hull)
				ModelGeometry.box(self, "Trunnion", Vector3(0.9, 1.6, 1.6), Vector3(side * 2.2, 0.0, -4.4), dark)
			ModelGeometry.box(self, "Radiator", Vector3(6.2, 3.6, 0.5), Vector3(0.0, -0.2, 4.3), dark)
			for slat: int in 6:
				ModelGeometry.box(self, "RadiatorSlat", Vector3(6.0, 0.14, 0.3), Vector3(0.0, -1.6 + float(slat) * 0.55, 4.62), hull)
			ModelGeometry.box(self, "RoofHatch", Vector3(2.4, 0.25, 2.2), Vector3(-1.4, 2.62, 1.4), dark)
			ModelGeometry.box(self, "SensorMount", Vector3(0.8, 1.0, 0.8), Vector3(2.0, 3.0, -2.4), hull)
			ModelGeometry.box(self, "SensorHead", Vector3(1.5, 1.2, 1.4), Vector3(2.0, 4.0, -2.4), hull)
			ModelGeometry.box(self, "SensorWindow", Vector3(1.1, 0.8, 0.1), Vector3(2.0, 4.0, -3.12), sensor)
		"director":
			var barrel := ModelGeometry.cylinder(self, "DirectorBarrel", 1.9, 5.8, Vector3(0.0, 0.0, -6.05), hull)
			barrel.rotation.x = PI * 0.5
			var hood := ModelGeometry.cylinder(self, "LensHood", 2.15, 0.6, Vector3(0.0, 0.0, -8.7), dark)
			hood.rotation.x = PI * 0.5
			for ring: int in 3:
				var band := ModelGeometry.cylinder(self, "CoolingBand", 2.0, 0.28, Vector3(0.0, 0.0, -4.0 - float(ring) * 1.3), dark)
				band.rotation.x = PI * 0.5
			ModelGeometry.box(self, "Spine", Vector3(0.6, 0.5, 5.0), Vector3(0.0, 2.05, -6.0), dark)
