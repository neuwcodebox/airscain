class_name DamageSmokeEffect
extends Node3D

var smoke: GPUParticles3D
var smoke_middle: GPUParticles3D
var smoke_upper: GPUParticles3D
var fire: GPUParticles3D
var city_plume_enabled: bool = false
var city_plume_elapsed: float = 0.0
var city_middle_height: float = 70.0
var city_upper_height: float = 120.0

func _ready() -> void:
	smoke = $Smoke
	smoke_middle = $SmokeMiddle
	smoke_upper = $SmokeUpper
	fire = $Fire
	_configure_plume_layers()

func _process(delta: float) -> void:
	if not city_plume_enabled:
		return
	city_plume_elapsed += delta
	var middle_progress := fposmod(city_plume_elapsed, 5.5) / 5.5
	var upper_progress := fposmod(city_plume_elapsed, 8.0) / 8.0
	smoke_middle.position = Vector3(middle_progress * 8.0, lerpf(0.7, city_middle_height, middle_progress), middle_progress * 3.0)
	smoke_upper.position = Vector3(upper_progress * 18.0, lerpf(0.8, city_upper_height, upper_progress), upper_progress * 7.0)

func _configure_plume_layers() -> void:
	var lower_process := smoke.process_material.duplicate(true) as ParticleProcessMaterial
	smoke.process_material = lower_process
	var middle_process := lower_process.duplicate(true) as ParticleProcessMaterial
	middle_process.direction = Vector3(0.08, 1.0, 0.03).normalized()
	middle_process.gravity = Vector3(1.0, 0.7, 0.34)
	middle_process.initial_velocity_min = 14.0
	middle_process.initial_velocity_max = 20.0
	middle_process.spread = 24.0
	middle_process.damping_min = 0.08
	middle_process.damping_max = 0.25
	middle_process.turbulence_noise_strength = 3.8
	smoke_middle.process_material = middle_process
	var upper_process := lower_process.duplicate(true) as ParticleProcessMaterial
	upper_process.direction = Vector3(0.12, 1.0, 0.05).normalized()
	upper_process.gravity = Vector3(1.7, 0.5, 0.55)
	upper_process.initial_velocity_min = 18.0
	upper_process.initial_velocity_max = 26.0
	upper_process.spread = 29.0
	upper_process.damping_min = 0.04
	upper_process.damping_max = 0.14
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
	smoke.lifetime = lerpf(8.5, 11.5, intensity)
	smoke.scale = Vector3.ONE * lerpf(0.8, 1.45, intensity)
	smoke.emitting = intensity > 0.0
	smoke_middle.amount = maxi(100, roundi(100.0 + intensity * 160.0))
	smoke_middle.lifetime = lerpf(11.0, 15.0, intensity)
	smoke_middle.scale = smoke.scale
	smoke_middle.emitting = intensity > 0.0
	smoke_upper.amount = maxi(80, roundi(80.0 + intensity * 140.0))
	smoke_upper.lifetime = lerpf(14.0, 19.0, intensity)
	smoke_upper.scale = smoke.scale * 1.1
	smoke_upper.emitting = intensity > 0.0
	fire.amount = maxi(8, roundi(8.0 + intensity * 24.0))
	fire.scale = Vector3.ONE * lerpf(0.8, 1.7, intensity)
	fire.emitting = intensity >= 0.35

func set_city_scale(scale_multiplier: float, building_height: float = 30.0) -> void:
	set_damage_ratio(1.0)
	var height_ratio := clampf(building_height / 30.0, 0.75, 2.0)
	var lower_process := smoke.process_material as ParticleProcessMaterial
	var middle_process := smoke_middle.process_material as ParticleProcessMaterial
	var upper_process := smoke_upper.process_material as ParticleProcessMaterial
	lower_process.initial_velocity_min = 14.0 * height_ratio
	lower_process.initial_velocity_max = 21.0 * height_ratio
	middle_process.initial_velocity_min = 21.0 * height_ratio
	middle_process.initial_velocity_max = 30.0 * height_ratio
	upper_process.initial_velocity_min = 29.0 * height_ratio
	upper_process.initial_velocity_max = 40.0 * height_ratio
	smoke.amount = maxi(smoke.amount, 480)
	smoke_middle.amount = maxi(smoke_middle.amount, 520)
	smoke_upper.amount = maxi(smoke_upper.amount, 560)
	smoke_middle.lifetime = maxf(smoke_middle.lifetime, 17.0)
	smoke_upper.lifetime = maxf(smoke_upper.lifetime, 24.0)
	city_middle_height = maxf(70.0, building_height * 1.4)
	city_upper_height = maxf(120.0, building_height * 2.2)
	city_plume_elapsed = 0.0
	city_plume_enabled = true
	smoke.scale *= scale_multiplier
	smoke_middle.scale *= scale_multiplier
	smoke_upper.scale *= scale_multiplier
	fire.scale *= scale_multiplier
