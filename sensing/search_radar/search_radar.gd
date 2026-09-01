class_name SearchRadar
extends DefenseUnit

@export var rotation_speed_degrees: float = 36.0

@onready var antenna: Node3D = $Antenna

func gameplay_tick(delta: float) -> void:
	if active:
		antenna.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
