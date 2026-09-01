class_name LaserPulse
extends Node3D

@export var lifetime: float = 0.09
var remaining: float
@onready var beam: MeshInstance3D = $Beam

func setup(from: Vector3, to: Vector3) -> void:
	remaining = lifetime
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES)
	line.surface_add_vertex(from)
	line.surface_add_vertex(to)
	line.surface_end()
	beam.mesh = line

func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
