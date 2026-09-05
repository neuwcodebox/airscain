extends Node3D

func _ready() -> void:
	var dark := ModelGeometry.material(Color("28342e"), 0.15)
	var steel := ModelGeometry.material(Color("8a9286"), 0.45)
	var warning := ModelGeometry.material(Color("c9a750"))
	var pale := ModelGeometry.material(Color("83907a"))
	ModelGeometry.box(self, "ServiceDoor", Vector3(7.5, 5.3, 0.18), Vector3(-2, 4, -3.13), dark)
	for slat: int in 7:
		ModelGeometry.box(self, "DoorSlat", Vector3(7.1, 0.40, 0.16), Vector3(-2, 1.65 + slat * 0.7, -3.24), steel)
	ModelGeometry.box(self, "WorkshopRoof", Vector3(12.6, 0.55, 9.5), Vector3(-2, 8.1, 1.5), pale)
	for index: int in 8:
		var x := 3.8 + float(index) * 0.62
		ModelGeometry.box(self, "ContainerRib", Vector3(0.12, 3.8, 0.16), Vector3(x, 3, -7.05), steel)
	for index: int in 6:
		ModelGeometry.box(self, "GeneratorLouvre", Vector3(3.8, 0.2, 0.15), Vector3(-6, 2.0 + index * 0.48, -7.3), dark)
	for side: float in [-1.0, 1.0]:
		ModelGeometry.cylinder(self, "ExhaustStack", 0.28, 4.0, Vector3(-6 + side, 6.2, -5), dark)
		ModelGeometry.box(self, "Bollard", Vector3(0.45, 1.4, 0.45), Vector3(-2 + side * 4.2, 1.3, -4.1), warning)
	for index: int in 3:
		ModelGeometry.box(self, "CargoCrate", Vector3(1.8, 1.5, 1.7), Vector3(5 + index * 0.8, 5.7, 4.1), pale)
