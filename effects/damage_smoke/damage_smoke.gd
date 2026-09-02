class_name DamageSmokeEffect
extends Node3D

var smoke: GPUParticles3D
var smoke_middle: GPUParticles3D
var smoke_upper: GPUParticles3D
var fire: GPUParticles3D

func _ready() -> void:
	smoke = $Smoke
	smoke_middle = $SmokeMiddle
	smoke_upper = $SmokeUpper
	fire = $Fire

func set_damage_ratio(damage_ratio: float) -> void:
	if smoke == null:
		smoke = get_node("Smoke") as GPUParticles3D
	if smoke_upper == null:
		smoke_upper = get_node("SmokeUpper") as GPUParticles3D
	if smoke_middle == null:
		smoke_middle = get_node("SmokeMiddle") as GPUParticles3D
	if fire == null:
		fire = get_node("Fire") as GPUParticles3D
	var intensity := clampf(damage_ratio, 0.0, 1.0)
	smoke.amount = maxi(110, roundi(110.0 + intensity * 210.0))
	smoke.lifetime = lerpf(5.6, 8.4, intensity)
	smoke.scale = Vector3.ONE * lerpf(0.95, 1.8, intensity)
	smoke.emitting = intensity > 0.0
	smoke_middle.amount = maxi(70, roundi(70.0 + intensity * 125.0))
	smoke_middle.lifetime = lerpf(6.0, 9.0, intensity)
	smoke_middle.scale = smoke.scale * 0.8
	smoke_middle.emitting = intensity > 0.0
	smoke_upper.amount = maxi(55, roundi(55.0 + intensity * 105.0))
	smoke_upper.lifetime = lerpf(6.2, 9.2, intensity)
	smoke_upper.scale = smoke.scale * 0.65
	smoke_upper.emitting = intensity > 0.0
	fire.amount = maxi(8, roundi(8.0 + intensity * 24.0))
	fire.scale = Vector3.ONE * lerpf(0.8, 1.7, intensity)
	fire.emitting = intensity >= 0.35

func set_city_scale(scale_multiplier: float) -> void:
	set_damage_ratio(1.0)
	smoke.scale *= scale_multiplier
	smoke_middle.scale *= scale_multiplier
	smoke_upper.scale *= scale_multiplier
	fire.scale *= scale_multiplier
