class_name TracerBurst
extends Node3D

@export var tracer_speed: float = 900.0
@export var tracer_count: int = 18
@export var tracer_spacing: float = 7.0
var age: float = 0.0
var distance: float = 0.0
var lifetime: float = 0.3
var tracers: Array[MeshInstance3D] = []

@onready var beam: MeshInstance3D = $Beam

func setup(from: Vector3, to: Vector3) -> void:
	global_position = from
	distance = from.distance_to(to)
	if distance <= 0.01:
		queue_free()
		return
	look_at(to, Vector3.UP)
	lifetime = (distance + float(tracer_count) * tracer_spacing) / tracer_speed
	tracers.append(beam)
	for index: int in range(1, tracer_count):
		var tracer := beam.duplicate() as MeshInstance3D
		add_child(tracer)
		tracers.append(tracer)
	_update_tracers()

func _process(delta: float) -> void:
	age += delta
	_update_tracers()
	if age >= lifetime:
		queue_free()

func _update_tracers() -> void:
	var head_distance := age * tracer_speed
	for index: int in tracers.size():
		var traveled := head_distance - float(index) * tracer_spacing
		var tracer := tracers[index]
		tracer.visible = traveled >= 0.0 and traveled <= distance
		if tracer.visible:
			var spread := Vector2(sin(float(index) * 2.31), cos(float(index) * 1.73)) * 0.42
			tracer.position = Vector3(spread.x, spread.y, -traveled)
