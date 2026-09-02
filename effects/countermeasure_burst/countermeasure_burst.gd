extends Node3D

var elapsed: float = 0.0
var duration: float = 8.0

func setup(countermeasure_type: StringName) -> void:
	var uses_flare := countermeasure_type == &"flare"
	$Flares.emitting = uses_flare
	$Chaff.emitting = not uses_flare
	$ChaffGlints.emitting = not uses_flare

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
