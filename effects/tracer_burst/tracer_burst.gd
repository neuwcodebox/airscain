class_name TracerBurst
extends Node3D

@export var tracer_speed: float = 1100.0
@export var tracer_count: int = 48
@export var tracer_spacing: float = 4.0
@export var muzzle_spread_radius: float = 0.28
@export var target_spread_radius: float = 5.2
var age: float = 0.0
var distance: float = 0.0
var lifetime: float = 0.3
var tracers: Array[MeshInstance3D] = []
var tracer_glows: Array[MeshInstance3D] = []

@onready var beam: MeshInstance3D = $Beam
@onready var glow_beam: MeshInstance3D = $GlowBeam

func setup(from: Vector3, to: Vector3) -> void:
	global_position = from
	distance = from.distance_to(to)
	if distance <= 0.01:
		queue_free()
		return
	look_at(to, Vector3.UP)
	lifetime = (distance + float(tracer_count) * tracer_spacing) / tracer_speed
	tracers.append(beam)
	tracer_glows.append(glow_beam)
	for index: int in range(1, tracer_count):
		var tracer := beam.duplicate() as MeshInstance3D
		var tracer_glow := glow_beam.duplicate() as MeshInstance3D
		add_child(tracer)
		add_child(tracer_glow)
		tracers.append(tracer)
		tracer_glows.append(tracer_glow)
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
		var tracer_glow := tracer_glows[index]
		tracer.visible = traveled >= 0.0 and traveled <= distance
		tracer_glow.visible = tracer.visible
		if tracer.visible:
			var progress := clampf(traveled / distance, 0.0, 1.0)
			var phase := float(index) * 2.399963
			var radial_ratio := 0.35 + 0.65 * fposmod(float(index) * 0.618034, 1.0)
			var spread_radius := lerpf(muzzle_spread_radius, target_spread_radius, progress) * radial_ratio
			var spread := Vector2(cos(phase), sin(phase)) * spread_radius
			tracer.position = Vector3(spread.x, spread.y, -traveled)
			tracer_glow.position = tracer.position
