class_name ExplosionEffect
extends Node3D

var elapsed: float = 0.0
var duration: float = 2.2

func setup(color: Color, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	$Flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	$Flash.material_override = material
	$Flash.scale = Vector3.ONE * radius * 0.15
	$Smoke.scale = Vector3.ONE * maxf(0.6, radius / 10.0)
	$Sparks.scale = Vector3.ONE * maxf(0.7, radius / 12.0)
	$Smoke.emitting = true
	$Sparks.emitting = true

func _process(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / 0.55, 0.0, 1.0)
	$Flash.scale = Vector3.ONE * lerpf(1.0, 7.0, t)
	var material := $Flash.material_override as StandardMaterial3D
	material.albedo_color.a = 1.0 - t
	if elapsed >= duration:
		queue_free()
