class_name LingeringSmokeTrail
extends GPUParticles3D

var release_remaining: float = -1.0

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

func _process(delta: float) -> void:
	release_remaining -= delta
	if release_remaining <= 0.0:
		queue_free()
