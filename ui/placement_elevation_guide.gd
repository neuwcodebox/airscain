class_name PlacementElevationGuide
extends Node3D
## Presentation of supplied measurements; does not query or mutate the battlefield.

var label: Label3D
var guide_material: Material

func _ready() -> void:
	label = Label3D.new()
	label.name = "ElevationLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = preload("res://ui/fonts/NanumSquareB.ttf")
	label.font_size = 28
	label.pixel_size = 0.00065
	label.outline_size = 6
	label.no_depth_test = true
	label.fixed_size = true
	label.position.y = 22.0
	add_child(label)
	var stem := MeshInstance3D.new()
	var line := CylinderMesh.new()
	line.top_radius = 0.12
	line.bottom_radius = 0.12
	line.height = 12.0
	line.radial_segments = 4
	stem.mesh = line
	stem.position = Vector3(0, 7, 0)
	stem.material_override = guide_material
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stem)

func show_measurements(altitude: float, slope: float) -> void:
	label.text = "해발 %.0fm · 지형 경사 %.0f°" % [altitude, slope]
