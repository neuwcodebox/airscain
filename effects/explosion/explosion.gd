class_name ExplosionEffect
extends Node3D

var elapsed: float = 0.0
var duration: float = 3.2
var effect_radius: float = 10.0

func setup(color: Color, radius: float) -> void:
	effect_radius = radius
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
	$Flash.scale = Vector3.ONE * radius * 0.18
	$Shockwave.scale = Vector3.ONE * radius * 0.12
	$Smoke.scale = Vector3.ONE * maxf(0.8, radius / 8.0)
	$Sparks.scale = Vector3.ONE * maxf(0.9, radius / 10.0)
	$BlastLight.light_color = color
	$BlastLight.omni_range = radius * 3.2
	$Smoke.emitting = true
	$Sparks.emitting = true

func _process(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / 0.7, 0.0, 1.0)
	$Flash.scale = Vector3.ONE * lerpf(effect_radius * 0.18, effect_radius, t)
	var material := $Flash.material_override as StandardMaterial3D
	material.albedo_color.a = 1.0 - t
	var shockwave_t := clampf(elapsed / 1.05, 0.0, 1.0)
	$Shockwave.scale = Vector3.ONE * lerpf(effect_radius * 0.12, effect_radius * 1.8, shockwave_t)
	var shockwave_material := $Shockwave.material_override as StandardMaterial3D
	shockwave_material.albedo_color.a = (1.0 - shockwave_t) * 0.9
	$BlastLight.light_energy = lerpf(12.0, 0.0, clampf(elapsed / 0.8, 0.0, 1.0))
	if elapsed >= duration:
		queue_free()
