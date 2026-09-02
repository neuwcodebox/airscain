extends Node3D

var elapsed: float = 0.0
var duration: float = 2.2

func setup(countermeasure_type: StringName) -> void:
	var uses_flare := countermeasure_type == &"flare"
	$Flares.emitting = uses_flare
	$Chaff.emitting = not uses_flare
	$Reason.text = "플레어 기만" if uses_flare else "채프 기만"
	$Reason.modulate = Color(1.0, 0.72, 0.24) if uses_flare else Color(0.82, 0.92, 1.0)

func _process(delta: float) -> void:
	elapsed += delta
	$Reason.position.y = 9.0 + elapsed * 1.8
	$Reason.modulate.a = 1.0 - clampf(elapsed / duration, 0.0, 1.0)
	if elapsed >= duration:
		queue_free()
