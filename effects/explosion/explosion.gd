class_name ExplosionEffect
extends Node3D

var elapsed: float = 0.0
var duration: float = 3.2
var effect_radius: float = 10.0

@onready var flash: MeshInstance3D = $Flash
@onready var flash_halo: MeshInstance3D = $FlashHalo
@onready var shockwave: MeshInstance3D = $Shockwave
@onready var blast_light: OmniLight3D = $BlastLight
@onready var smoke: ShadowedSmokeParticles = $Smoke
@onready var sparks: GPUParticles3D = $Sparks

func setup(color: Color, radius: float) -> void:
	elapsed = 0.0
	effect_radius = radius
	var material := (flash.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	flash.material_override = material
	var halo_material := (flash_halo.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	halo_material.albedo_color = Color(color.r, color.g, color.b, 0.3)
	halo_material.emission = color
	flash_halo.material_override = halo_material
	var shockwave_material := (shockwave.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	shockwave_material.albedo_color.a = 0.9
	shockwave.material_override = shockwave_material
	flash.scale = Vector3.ONE * radius * 0.18
	flash_halo.scale = Vector3.ONE * radius * 0.42
	shockwave.scale = Vector3.ONE * radius * 0.12
	smoke.scale = Vector3.ONE * maxf(0.8, radius / 8.0)
	sparks.scale = Vector3.ONE * maxf(0.9, radius / 10.0)
	blast_light.light_color = color
	blast_light.omni_range = radius * 3.2
	smoke.emitting = true
	sparks.emitting = true

func _process(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / 0.7, 0.0, 1.0)
	flash.scale = Vector3.ONE * lerpf(effect_radius * 0.18, effect_radius, t)
	var material := flash.material_override as StandardMaterial3D
	material.albedo_color.a = 1.0 - t
	var halo_t := clampf(elapsed / 0.48, 0.0, 1.0)
	flash_halo.scale = Vector3.ONE * lerpf(effect_radius * 0.42, effect_radius * 1.35, halo_t)
	var halo_material := flash_halo.material_override as StandardMaterial3D
	halo_material.albedo_color.a = (1.0 - halo_t) * 0.3
	halo_material.emission.a = 1.0 - halo_t
	var shockwave_t := clampf(elapsed / 1.05, 0.0, 1.0)
	shockwave.scale = Vector3.ONE * lerpf(effect_radius * 0.12, effect_radius * 1.8, shockwave_t)
	var shockwave_material := shockwave.material_override as StandardMaterial3D
	shockwave_material.albedo_color.a = (1.0 - shockwave_t) * 0.9
	blast_light.light_energy = lerpf(18.0, 0.0, clampf(elapsed / 0.8, 0.0, 1.0))
	if elapsed >= duration:
		queue_free()
