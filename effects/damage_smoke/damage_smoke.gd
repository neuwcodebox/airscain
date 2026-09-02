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
	_configure_plume_layers()

func _configure_plume_layers() -> void:
	var lower_process := smoke.process_material as ParticleProcessMaterial
	var middle_process := lower_process.duplicate(true) as ParticleProcessMaterial
	middle_process.direction = Vector3(0.1, 1.0, 0.04).normalized()
	middle_process.gravity = Vector3(0.85, 0.62, 0.3)
	middle_process.initial_velocity_min = 9.0
	middle_process.initial_velocity_max = 14.0
	middle_process.spread = 24.0
	middle_process.turbulence_noise_strength = 3.8
	smoke_middle.process_material = middle_process
	var upper_process := lower_process.duplicate(true) as ParticleProcessMaterial
	upper_process.direction = Vector3(0.18, 1.0, 0.07).normalized()
	upper_process.gravity = Vector3(1.15, 0.38, 0.42)
	upper_process.initial_velocity_min = 11.0
	upper_process.initial_velocity_max = 17.0
	upper_process.spread = 29.0
	upper_process.damping_min = 0.08
	upper_process.damping_max = 0.24
	upper_process.turbulence_noise_strength = 4.6
	upper_process.turbulence_influence_min = 0.6
	upper_process.turbulence_influence_max = 1.0
	smoke_upper.process_material = upper_process

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
	smoke.amount = maxi(120, roundi(120.0 + intensity * 180.0))
	smoke.lifetime = lerpf(7.0, 10.0, intensity)
	smoke.scale = Vector3.ONE * lerpf(0.8, 1.45, intensity)
	smoke.emitting = intensity > 0.0
	smoke_middle.amount = maxi(85, roundi(85.0 + intensity * 140.0))
	smoke_middle.lifetime = lerpf(8.5, 12.0, intensity)
	smoke_middle.scale = smoke.scale * 0.9
	smoke_middle.emitting = intensity > 0.0
	smoke_upper.amount = maxi(65, roundi(65.0 + intensity * 100.0))
	smoke_upper.lifetime = lerpf(10.0, 14.0, intensity)
	smoke_upper.scale = smoke.scale * 0.85
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
