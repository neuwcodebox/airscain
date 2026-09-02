class_name DamageSmokeEffect
extends Node3D

var smoke: GPUParticles3D
var fire: GPUParticles3D

func _ready() -> void:
	smoke = $Smoke
	fire = $Fire

func set_damage_ratio(damage_ratio: float) -> void:
	if smoke == null:
		smoke = get_node("Smoke") as GPUParticles3D
	if fire == null:
		fire = get_node("Fire") as GPUParticles3D
	var intensity := clampf(damage_ratio, 0.0, 1.0)
	smoke.amount = maxi(24, roundi(24.0 + intensity * 84.0))
	smoke.lifetime = lerpf(2.4, 5.0, intensity)
	smoke.scale = Vector3.ONE * lerpf(1.15, 2.8, intensity)
	smoke.emitting = intensity > 0.0
	fire.amount = maxi(8, roundi(8.0 + intensity * 24.0))
	fire.scale = Vector3.ONE * lerpf(0.8, 1.7, intensity)
	fire.emitting = intensity >= 0.35

func set_city_scale(scale_multiplier: float) -> void:
	set_damage_ratio(1.0)
	smoke.scale *= scale_multiplier
	fire.scale *= scale_multiplier
