class_name TracerBurst
extends Node3D

@export var lifetime: float = 0.11
var age: float = 0.0

@onready var beam: MeshInstance3D = $Beam

func setup(from: Vector3, to: Vector3) -> void:
	global_position = from
	var distance := from.distance_to(to)
	if distance <= 0.01:
		queue_free()
		return
	look_at(to, Vector3.UP)
	beam.position = Vector3(0.0, 0.0, -distance * 0.5)
	beam.scale = Vector3(1.0, 1.0, distance)

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
