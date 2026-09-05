class_name LaserPulse
extends Node3D

@export var lifetime: float = 0.18
var remaining: float
@onready var beam: MeshInstance3D = $Beam
@onready var glow_beam: MeshInstance3D = $GlowBeam
@onready var source_flash: MeshInstance3D = $SourceFlash
@onready var impact_flash: MeshInstance3D = $ImpactFlash
@onready var impact_light: OmniLight3D = $ImpactLight

func setup(from: Vector3, to: Vector3) -> void:
	remaining = lifetime
	var segment := to - from
	var length := segment.length()
	if length <= 0.001:
		queue_free()
		return
	global_position = from.lerp(to, 0.5)
	global_basis = Basis(Quaternion(Vector3.UP, segment / length))
	beam.scale.y = length
	glow_beam.scale.y = length
	source_flash.position.y = -length * 0.5
	impact_flash.position.y = length * 0.5
	impact_light.position.y = length * 0.5
	for mesh_instance: MeshInstance3D in [beam, glow_beam, source_flash, impact_flash]:
		mesh_instance.material_override = mesh_instance.material_override.duplicate() as Material
	(beam.material_override as StandardMaterial3D).emission_energy_multiplier = 24.0
	(source_flash.material_override as StandardMaterial3D).emission_energy_multiplier = 28.0
	(impact_flash.material_override as StandardMaterial3D).emission_energy_multiplier = 28.0

func _process(delta: float) -> void:
	remaining -= delta
	var intensity := clampf(remaining / lifetime, 0.0, 1.0)
	for mesh_instance: MeshInstance3D in [beam, source_flash, impact_flash]:
		var material := mesh_instance.material_override as StandardMaterial3D
		material.albedo_color.a = intensity
		material.emission_energy_multiplier = (24.0 if mesh_instance == beam else 28.0) * intensity
	(glow_beam.material_override as ShaderMaterial).set_shader_parameter("intensity", intensity)
	source_flash.scale = Vector3.ONE * lerpf(0.45, 1.0, intensity)
	impact_flash.scale = Vector3.ONE * lerpf(0.65, 1.35, intensity)
	impact_light.light_energy = 12.0 * intensity
	if remaining <= 0.0:
		queue_free()
