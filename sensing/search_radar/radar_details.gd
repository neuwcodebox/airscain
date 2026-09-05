extends Node3D

@export var tracking_panel: bool = false

func _ready() -> void:
	var frame := ModelGeometry.material(Color("53665c"), 0.35)
	var dark := ModelGeometry.material(Color("253633"), 0.2)
	var rubber := ModelGeometry.material(Color("222b2b"))
	var metal := ModelGeometry.material(Color("a3aaa0"), 0.65, 0.4)
	var root := get_parent() as Node3D
	for side: float in [-1.0, 1.0]:
		ModelGeometry.box(self, "EquipmentCabinet", Vector3(2.8, 3.0, 4.6), Vector3(side * 3.0, 3, 0.5), frame)
		ModelGeometry.strut(self, "Outrigger", Vector3(side * 2, 2, 0), Vector3(side * 6.5, 0.8, 2.8), 0.65, frame)
		ModelGeometry.box(self, "GroundFoot", Vector3(2, 0.35, 2), Vector3(side * 6.5, 0.35, 2.8), rubber)
		ModelGeometry.strut(self, "MastBrace", Vector3(side * 3.0, 2.8, 0), Vector3(0, 8.5, 0), 0.35, metal)
		for vent: int in 5:
			ModelGeometry.box(self, "CabinetVent", Vector3(2.2, 0.13, 0.12), Vector3(side * 3, 2.3 + vent * 0.35, -1.85), dark)
	for rung: int in 7:
		ModelGeometry.box(self, "LadderRung", Vector3(1.6, 0.16, 0.25), Vector3(0, 2.5 + rung * 0.9, 1.7), metal)
	var antenna := root.get_node("Antenna") as Node3D
	var face := antenna.get_node("Face") as MeshInstance3D
	face.material_override = dark
	var grid := Node3D.new()
	grid.name = "PanelModules"
	grid.transform = face.transform
	antenna.add_child(grid)
	var width := 6.4 if tracking_panel else 10.8
	var height := 4.4 if tracking_panel else 3.7
	var count := 5 if tracking_panel else 8
	for column: int in count:
		for row: int in 3:
			var position := Vector3((float(column) + 0.5) * width / count - width * 0.5, (float(row) - 1.0) * height / 3.0, -0.18)
			ModelGeometry.box(grid, "AntennaModule", Vector3(width / count * 0.80, height / 3.0 * 0.79, 0.12), position, frame)
	ModelGeometry.strut(antenna, "RearBraceLeft", Vector3(-width * 0.44, -1.4, 0.6), Vector3(0, 1.8, 1.8), 0.28, metal)
	ModelGeometry.strut(antenna, "RearBraceRight", Vector3(width * 0.44, -1.4, 0.6), Vector3(0, 1.8, 1.8), 0.28, metal)
