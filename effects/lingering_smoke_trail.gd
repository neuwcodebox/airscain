class_name LingeringSmokeTrail
extends GPUParticles3D

@export_range(0.5, 20.0, 0.5) var sample_spacing: float = 3.0

var release_remaining: float = -1.0
var sample_remainder: float = 0.0
var emitted_sample_count: int = 0
var last_emitted_world_position: Vector3

func _ready() -> void:
	set_process(false)

func release_to(new_parent: Node) -> void:
	if new_parent == null or not is_instance_valid(new_parent):
		queue_free()
		return
	reparent(new_parent, true)
	emitting = false
	release_remaining = lifetime * 1.15
	set_process(true)

func sample_world_segment(from_position: Vector3, to_position: Vector3) -> void:
	var segment := to_position - from_position
	var distance := segment.length()
	if distance <= 0.001:
		return
	var direction := segment / distance
	var cursor := sample_spacing - sample_remainder
	while cursor <= distance:
		var world_position := from_position + direction * cursor
		emit_particle(Transform3D(Basis.IDENTITY, world_position), Vector3.ZERO, Color.WHITE, Color.WHITE, EMIT_FLAG_POSITION)
		last_emitted_world_position = world_position
		emitted_sample_count += 1
		cursor += sample_spacing
	sample_remainder = fposmod(sample_remainder + distance, sample_spacing)

func _process(delta: float) -> void:
	release_remaining -= delta
	if release_remaining <= 0.0:
		queue_free()
