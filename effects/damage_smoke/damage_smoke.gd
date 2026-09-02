class_name DamageSmokeEffect
extends Node3D

var smoke: GPUParticles3D

func _ready() -> void:
	smoke = $Smoke

func set_damage_ratio(damage_ratio: float) -> void:
	if smoke == null:
		smoke = get_node("Smoke") as GPUParticles3D
	var intensity := clampf(damage_ratio, 0.0, 1.0)
	smoke.amount = maxi(4, roundi(6.0 + intensity * 18.0))
	smoke.lifetime = lerpf(1.0, 2.2, intensity)
	smoke.scale = Vector3.ONE * lerpf(0.7, 1.5, intensity)
	smoke.emitting = intensity > 0.0
