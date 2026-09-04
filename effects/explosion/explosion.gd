class_name ExplosionEffect
extends Node3D

var elapsed: float = 0.0
var duration: float = 3.2
var effect_radius: float = 10.0

func setup(color: Color, radius: float) -> void:
	elapsed = 0.0
	effect_radius = radius
	var material := ($Flash.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	$Flash.material_override = material
	var halo_material := ($FlashHalo.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	halo_material.albedo_color = Color(color.r, color.g, color.b, 0.3)
	halo_material.emission = color
	$FlashHalo.material_override = halo_material
	var shockwave_material := ($Shockwave.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	shockwave_material.albedo_color.a = 0.9
	$Shockwave.material_override = shockwave_material
	$Flash.scale = Vector3.ONE * radius * 0.18
	$FlashHalo.scale = Vector3.ONE * radius * 0.42
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
	var halo_t := clampf(elapsed / 0.48, 0.0, 1.0)
	$FlashHalo.scale = Vector3.ONE * lerpf(effect_radius * 0.42, effect_radius * 1.35, halo_t)
	var halo_material := $FlashHalo.material_override as StandardMaterial3D
	halo_material.albedo_color.a = (1.0 - halo_t) * 0.3
	halo_material.emission.a = 1.0 - halo_t
	var shockwave_t := clampf(elapsed / 1.05, 0.0, 1.0)
	$Shockwave.scale = Vector3.ONE * lerpf(effect_radius * 0.12, effect_radius * 1.8, shockwave_t)
	var shockwave_material := $Shockwave.material_override as StandardMaterial3D
	shockwave_material.albedo_color.a = (1.0 - shockwave_t) * 0.9
	$BlastLight.light_energy = lerpf(18.0, 0.0, clampf(elapsed / 0.8, 0.0, 1.0))
	if elapsed >= duration:
		queue_free()
