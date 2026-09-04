class_name DamageSmokeEffect
extends Node3D

const REFERENCE_SOURCE_HEIGHT := 30.0
const CITY_PARTICLE_COUNT := 1500
const CITY_LIFETIME := 18.0

@onready var smoke: ShadowedSmokeParticles = $Smoke
@onready var fire: GPUParticles3D = $Fire

func set_damage_ratio(damage_ratio: float) -> void:
	var intensity := clampf(damage_ratio, 0.0, 1.0)
	smoke.amount = CITY_PARTICLE_COUNT
	smoke.amount_ratio = lerpf(0.17, 0.47, intensity)
	smoke.lifetime = lerpf(9.0, 13.0, intensity)
	smoke.scale = Vector3.ONE * lerpf(0.75, 1.25, intensity)
	smoke.emitting = intensity > 0.0
	fire.amount = maxi(8, roundi(8.0 + intensity * 24.0))
	fire.scale = Vector3.ONE * lerpf(0.8, 1.7, intensity)
	fire.emitting = intensity >= 0.35

func set_city_scale(scale_multiplier: float, source_height: float = REFERENCE_SOURCE_HEIGHT) -> void:
	set_damage_ratio(1.0)
	var height_ratio := clampf(source_height / REFERENCE_SOURCE_HEIGHT, 0.65, 2.0)
	smoke.amount = CITY_PARTICLE_COUNT
	smoke.amount_ratio = 1.0
	smoke.lifetime = CITY_LIFETIME
	var height_scale := remap(height_ratio, 0.65, 2.0, 0.85, 1.3)
	smoke.scale = Vector3.ONE * scale_multiplier * height_scale
	fire.scale *= scale_multiplier
