extends Node3D

func _ready() -> void:
	var metal := ModelGeometry.material(Color("8b978d"), 0.3)
	var dark := ModelGeometry.material(Color("24373c"), 0.2)
	var stone := ModelGeometry.material(Color("636e64"))
	var roof := ModelGeometry.material(Color("a4aaa0"))
	ModelGeometry.box(self, "Foundation", Vector3(19.5, 0.65, 15), Vector3(0, 0.32, 0), stone)
	ModelGeometry.box(self, "Entrance", Vector3(2.5, 3.7, 0.24), Vector3(5.8, 2.0, -7.18), dark)
	ModelGeometry.box(self, "EntryCanopy", Vector3(4.0, 0.4, 2.6), Vector3(5.8, 4.2, -6.3), roof)
	for step: int in 3:
		ModelGeometry.box(self, "EntryStep", Vector3(3.3, 0.18 * (step + 1), 0.5), Vector3(5.8, 0.09 * (step + 1), -7.7 + step * 0.4), stone)
	for division: int in 6:
		ModelGeometry.box(self, "WindowFrame", Vector3(0.28, 2.5, 0.25), Vector3(-6.4 + division * 2.3, 4.2, -7.2), metal)
	for side: float in [-1.0, 1.0]:
		ModelGeometry.box(self, "RoofRail", Vector3(0.3, 1.0, 11), Vector3(side * 7.0, 8.3, 0), metal)
		ModelGeometry.box(self, "RoofCooling", Vector3(2.8, 1.4, 3.0), Vector3(side * 4.8, 8.6, 2), dark)
		ModelGeometry.strut(self, "AntennaStay", Vector3(side * 4, 8, 0), Vector3(0, 13.0, 0), 0.14, metal)
	var dome := get_parent().get_node("Dome") as MeshInstance3D
	dome.material_override = roof
	ModelGeometry.strut(self, "WhipAntenna", Vector3(-6, 8, -4), Vector3(-6, 14.5, -4), 0.13, dark)
	ModelGeometry.box(self, "RoofAccess", Vector3(3.2, 1.5, 2.8), Vector3(2, 8.8, 3), stone)
