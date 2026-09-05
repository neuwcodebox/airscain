extends Node3D

func _ready() -> void:
	var shell := ModelGeometry.material(Color("8a9188"), 0.5, 0.45)
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := ModelGeometry.material(Color("3f5356"), 0.35)
	var feed := ModelGeometry.material(Color("383b46"), 0.4)
	var profile: Array[Vector3] = [Vector3(0.1, 0.1, 0.5), Vector3(1.6, 1.6, 0.25), Vector3(3.1, 3.1, -0.5), Vector3(4.6, 4.6, -1.7)]
	ModelGeometry.mesh(self, "ParabolicReflector", ModelGeometry.hull(profile), Vector3.ZERO, shell)
	for side: float in [-1.0, 1.0]:
		ModelGeometry.strut(self, "FeedSupport", Vector3(side * 4.3, 0, -1.6), Vector3(0, 0, -4.2), 0.22, frame)
		ModelGeometry.box(self, "ElevationYoke", Vector3(0.7, 5.5, 1.1), Vector3(side * 4.9, -1.4, 0.5), frame)
	ModelGeometry.box(self, "Emitter", Vector3(0.9, 0.9, 1.5), Vector3(0, 0, -3.8), feed)
