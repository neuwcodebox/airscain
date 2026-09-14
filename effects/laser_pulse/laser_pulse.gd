class_name LaserPulse
extends Node3D

@export var lifetime: float = 0.18
var remaining: float
var emitting: bool = false
var _elapsed: float = 0.0
@onready var beam: MeshInstance3D = $Beam
@onready var glow_beam: MeshInstance3D = $GlowBeam
@onready var source_flash: MeshInstance3D = $SourceFlash
@onready var impact_flash: MeshInstance3D = $ImpactFlash
@onready var impact_light: OmniLight3D = $ImpactLight

func setup(from: Vector3, to: Vector3) -> void:
	_prepare_instance_materials()
	sustain(from, to)

func sustain(from: Vector3, to: Vector3) -> void:
	_prepare_instance_materials()
	remaining = lifetime
	emitting = true
	var segment := to - from
	var length := segment.length()
	if length <= 0.001:
		stop()
		return
	global_position = from.lerp(to, 0.5)
	global_basis = Basis(Quaternion(Vector3.UP, segment / length))
	_update_visual(length, 1.0)
	source_flash.position.y = -length * 0.5
	impact_flash.position.y = length * 0.5
	impact_light.position.y = length * 0.5

func stop() -> void:
	emitting = false
	remaining = minf(remaining, lifetime)

func _prepare_instance_materials() -> void:
	if beam.material_override.resource_local_to_scene:
		return
	for mesh_instance: MeshInstance3D in [beam, glow_beam, source_flash, impact_flash]:
		mesh_instance.material_override = mesh_instance.material_override.duplicate() as Material
		mesh_instance.material_override.resource_local_to_scene = true
	(beam.material_override as StandardMaterial3D).emission_energy_multiplier = 24.0
	(source_flash.material_override as StandardMaterial3D).emission_energy_multiplier = 28.0
	(impact_flash.material_override as StandardMaterial3D).emission_energy_multiplier = 28.0

func _process(delta: float) -> void:
	_elapsed += delta
	remaining -= delta
	var intensity := clampf(remaining / lifetime, 0.0, 1.0)
	_update_visual(beam.scale.y, intensity)
	if remaining <= 0.0:
		queue_free()

func _update_visual(length: float, intensity: float) -> void:
	var static_noise := sin(_elapsed * 47.0) * 0.55 + sin(_elapsed * 83.0 + 1.7) * 0.3 + sin(_elapsed * 131.0 + 0.4) * 0.15
	var core_width := 1.0 + static_noise * 0.16
	var halo_width := 1.0 + static_noise * 0.1
	beam.scale = Vector3(core_width, length, core_width)
	glow_beam.scale = Vector3(halo_width, length, 1.0)
	for mesh_instance: MeshInstance3D in [beam, source_flash, impact_flash]:
		var material := mesh_instance.material_override as StandardMaterial3D
		material.albedo_color.a = intensity
		var base_energy := 24.0 if mesh_instance == beam else 28.0
		material.emission_energy_multiplier = base_energy * intensity * (1.0 + static_noise * 0.08)
	(glow_beam.material_override as ShaderMaterial).set_shader_parameter("intensity", intensity * (1.0 + static_noise * 0.12))
	source_flash.scale = Vector3.ONE * lerpf(0.45, 1.0 + static_noise * 0.08, intensity)
	impact_flash.scale = Vector3.ONE * lerpf(0.65, 1.35 + static_noise * 0.12, intensity)
	impact_light.light_energy = 12.0 * intensity * (1.0 + static_noise * 0.14)
