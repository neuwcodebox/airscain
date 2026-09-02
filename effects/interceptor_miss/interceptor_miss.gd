class_name InterceptorMissEffect
extends Node3D

var elapsed: float = 0.0
var duration: float = 1.8

func setup(color: Color, reason: String) -> void:
	var material := $Flash.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	$Flash.material_override = material
	$Smoke.emitting = true
	$Reason.text = reason

func _process(delta: float) -> void:
	elapsed += delta
	var fade := clampf(elapsed / 0.55, 0.0, 1.0)
	$Flash.scale = Vector3.ONE * lerpf(0.8, 4.5, fade)
	var material := $Flash.material_override as StandardMaterial3D
	material.albedo_color.a = 1.0 - fade
	$Reason.modulate.a = 1.0 - clampf(elapsed / duration, 0.0, 1.0)
	if elapsed >= duration:
		queue_free()
