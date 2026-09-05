class_name ExplosionEffect
extends Node3D

signal finished(effect: ExplosionEffect)
var reusable: bool = false

var elapsed: float = 0.0
var duration: float = ExplosionTimeline.TOTAL_DURATION
var effect_radius: float = 10.0

@onready var flash: MeshInstance3D = $Flash
@onready var flash_halo: MeshInstance3D = $FlashHalo
@onready var pressure_ring: MeshInstance3D = $PressureRing
@onready var shockwave: MeshInstance3D = $Shockwave
@onready var blast_light: OmniLight3D = $BlastLight
@onready var fireball: GPUParticles3D = $Fireball
@onready var smoke: ShadowedSmokeParticles = $Smoke
@onready var sparks: GPUParticles3D = $Sparks

var flash_material: StandardMaterial3D
var halo_material: StandardMaterial3D
var pressure_material: StandardMaterial3D
var shockwave_material: StandardMaterial3D
var fireball_material: StandardMaterial3D

static func spawn(parent: Node3D, position: Vector3, color: Color, radius: float) -> ExplosionEffect:
	for node: Node in parent.get_tree().get_nodes_in_group("combat_effect_pool"):
		if (node as Node3D).get_world_3d() == parent.get_world_3d():
			return node.call("spawn_explosion", parent, position, color, radius) as ExplosionEffect
	var effect := (load("res://effects/explosion/explosion.tscn") as PackedScene).instantiate() as ExplosionEffect
	parent.add_child(effect)
	effect.global_position = position
	effect.setup(color, radius)
	return effect

func deactivate() -> void:
	visible = false
	set_process(false)
	for particles: GPUParticles3D in [fireball, smoke, sparks]:
		particles.emitting = false
	smoke._sync_shadow_state()
	blast_light.visible = false

func setup(color: Color, radius: float) -> void:
	visible = true
	set_process(true)
	blast_light.visible = true
	elapsed = 0.0
	effect_radius = radius
	if flash_material == null:
		flash_material = _duplicate_colored_material(flash, color, 1.0)
		halo_material = _duplicate_colored_material(flash_halo, color, 0.5)
		pressure_material = _duplicate_colored_material(pressure_ring, color, 0.0)
		shockwave_material = _duplicate_colored_material(shockwave, color, 0.82)
	for material: StandardMaterial3D in [flash_material, halo_material, pressure_material, shockwave_material]:
		material.albedo_color = color
		material.emission = color
	_configure_fireball(color)
	smoke.scale = Vector3.ONE * maxf(0.8, radius / 8.0)
	sparks.scale = Vector3.ONE * maxf(0.9, radius / 10.0)
	fireball.scale = Vector3.ONE * maxf(0.85, radius / 9.0)
	blast_light.light_color = color
	blast_light.omni_range = radius * 4.0
	_apply_timeline(ExplosionTimeline.sample(0.0, effect_radius))
	fireball.restart()
	smoke.restart()
	sparks.restart()
	if smoke.shadow_particles != null:
		smoke.shadow_particles.restart()
	fireball.emitting = true
	smoke.emitting = true
	sparks.emitting = true

func _process(delta: float) -> void:
	elapsed += delta
	if flash.visible or flash_halo.visible or pressure_ring.visible or shockwave.visible or blast_light.visible or elapsed <= ExplosionTimeline.PRESSURE_DELAY:
		_apply_timeline(ExplosionTimeline.sample(elapsed, effect_radius))
	if elapsed >= duration:
		if reusable:
			deactivate()
			finished.emit(self)
		else:
			queue_free()

func _apply_timeline(state: ExplosionTimeline.State) -> void:
	_apply_layer(flash, flash_material, state.core_scale, state.core_alpha)
	_apply_layer(flash_halo, halo_material, state.halo_scale, state.halo_alpha)
	_apply_layer(pressure_ring, pressure_material, state.pressure_scale, state.pressure_alpha)
	_apply_layer(shockwave, shockwave_material, state.ground_wave_scale, state.ground_wave_alpha)
	if blast_light.visible or state.light_energy > 0.0:
		blast_light.light_energy = state.light_energy
	blast_light.visible = state.light_energy > 0.0

func _apply_layer(layer: MeshInstance3D, material: StandardMaterial3D, size: float, alpha: float) -> void:
	if layer.visible or alpha > 0.0 or material.albedo_color.a != alpha:
		layer.scale = Vector3.ONE * size
		_set_alpha(material, alpha)
	layer.visible = alpha > 0.0

func _duplicate_colored_material(mesh_instance: MeshInstance3D, color: Color, alpha: float) -> StandardMaterial3D:
	var material := (mesh_instance.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission = color
	mesh_instance.material_override = material
	return material

func _configure_fireball(color: Color) -> void:
	if fireball_material == null:
		var unique_mesh := fireball.draw_pass_1.duplicate() as QuadMesh
		fireball_material = (unique_mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		unique_mesh.material = fireball_material
		fireball.draw_pass_1 = unique_mesh
	var hot_rgb := color.lerp(Color.WHITE, 0.18)
	var hot_color := Color(hot_rgb.r, hot_rgb.g, hot_rgb.b, 0.68)
	fireball_material.albedo_color = hot_color
	fireball_material.emission = Color(hot_rgb.r, hot_rgb.g, hot_rgb.b, 1.0)

func _set_alpha(material: StandardMaterial3D, alpha: float) -> void:
	var color := material.albedo_color
	color.a = alpha
	material.albedo_color = color
	var emission := material.emission
	emission.a = alpha
	material.emission = emission
