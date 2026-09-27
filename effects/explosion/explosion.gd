class_name ExplosionEffect
extends Node3D

signal finished(effect: ExplosionEffect)
const MAX_LIGHTS := 3
static var light_holders: Array[ExplosionEffect] = []

var reusable: bool = false
var elapsed: float = 0.0
var duration: float = ExplosionTimeline.TOTAL_DURATION
var effect_radius: float = 10.0
var ground_contact: bool = false
var owns_light: bool = false

@onready var flash: MeshInstance3D = $Flash
@onready var blast_light: OmniLight3D = $BlastLight
@onready var smoke: GPUParticles3D = $Smoke
@onready var sparks: GPUParticles3D = $Sparks
@onready var debris: GPUParticles3D = $Debris
@onready var dust: GPUParticles3D = $Dust

var flash_material: StandardMaterial3D
var puff_material: ShaderMaterial
var puff_process: ParticleProcessMaterial
var spark_process: ParticleProcessMaterial
var debris_process: ParticleProcessMaterial

func _ready() -> void:
	SmokeShadowFactory.register_caster(smoke)
	smoke.layers |= 1

static func spawn(parent: Node3D, position: Vector3, color: Color, radius: float, ground: bool = false, direction: Vector3 = Vector3.ZERO, normal: Vector3 = Vector3.UP) -> ExplosionEffect:
	for node: Node in parent.get_tree().get_nodes_in_group("combat_effect_pool"):
		var pool := node as CombatEffectPool
		if pool != null and pool.get_world_3d() == parent.get_world_3d():
			return pool.spawn_explosion(parent, position, color, radius, ground, direction, normal)
	var effect := (load("res://effects/explosion/explosion.tscn") as PackedScene).instantiate() as ExplosionEffect
	parent.add_child(effect)
	effect.global_position = position
	effect.setup(color, radius, ground, direction, normal)
	return effect

func deactivate() -> void:
	_release_light()
	visible = false
	set_process(false)
	for particles: GPUParticles3D in [smoke, sparks, debris, dust]:
		particles.emitting = false
	blast_light.visible = false

func setup(color: Color, radius: float, ground: bool = false, direction: Vector3 = Vector3.ZERO, normal: Vector3 = Vector3.UP) -> void:
	_release_light()
	visible = true
	set_process(true)
	elapsed = 0.0
	effect_radius = radius
	ground_contact = ground
	if flash_material == null:
		flash_material = (flash.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		flash.material_override = flash_material
		var mesh := smoke.draw_pass_1.duplicate() as QuadMesh
		puff_material = (mesh.material as ShaderMaterial).duplicate() as ShaderMaterial
		mesh.material = puff_material
		smoke.draw_pass_1 = mesh
		puff_process = smoke.process_material.duplicate() as ParticleProcessMaterial
		smoke.process_material = puff_process
		spark_process = sparks.process_material.duplicate() as ParticleProcessMaterial
		sparks.process_material = spark_process
		debris_process = debris.process_material.duplicate() as ParticleProcessMaterial
		debris.process_material = debris_process
	flash_material.albedo_color = Color(1.0, 0.94, 0.76, 1.0)
	flash_material.emission = Color(1.0, 0.92, 0.67, 1.0)
	puff_material.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	var travel := direction.normalized() if direction.length_squared() > 0.01 else Vector3.ZERO
	puff_process.direction = (travel * 0.65 + Vector3.UP * 0.35).normalized()
	puff_process.spread = 115.0 if travel != Vector3.ZERO else 160.0
	spark_process.direction = (travel + Vector3.UP * 0.25).normalized() if travel != Vector3.ZERO else Vector3.UP
	debris_process.direction = spark_process.direction
	smoke.scale = Vector3.ONE * maxf(0.8, radius / 9.0)
	sparks.scale = Vector3.ONE * maxf(0.9, radius / 10.0)
	debris.scale = Vector3.ONE * maxf(0.8, radius / 10.0)
	dust.visible = ground
	if ground:
		var up := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
		dust.basis = Basis(Quaternion(Vector3.UP, up))
		dust.scale = Vector3.ONE * maxf(0.8, radius / 10.0)
	blast_light.light_color = Color(1.0, 0.76, 0.48)
	blast_light.omni_range = radius * (5.0 if ground else 3.0)
	_claim_light()
	_apply_timeline(ExplosionTimeline.sample(0.0, radius, ground))
	for particles: GPUParticles3D in [smoke, sparks, debris]:
		particles.restart()
		particles.emitting = true
	if ground:
		dust.restart()
		dust.emitting = true
	else:
		dust.emitting = false

func prepare_preview(delta: float) -> void:
	_process(delta)

func _process(delta: float) -> void:
	var previous := elapsed
	elapsed += delta
	if elapsed <= ExplosionTimeline.LIGHT_DURATION + maxf(delta, 0.0):
		_apply_timeline(ExplosionTimeline.sample(elapsed, effect_radius, ground_contact, previous))
	if elapsed >= duration:
		if reusable:
			deactivate()
			finished.emit(self)
		else:
			_release_light()
			queue_free()

func _apply_timeline(state: ExplosionTimeline.State) -> void:
	flash.scale = Vector3.ONE * state.core_scale
	var color := flash_material.albedo_color
	color.a = state.core_alpha
	flash_material.albedo_color = color
	flash.visible = state.core_alpha > 0.001
	blast_light.light_energy = state.light_energy
	blast_light.visible = owns_light and state.light_energy > 0.001

func _claim_light() -> void:
	for index: int in range(light_holders.size() - 1, -1, -1):
		if not is_instance_valid(light_holders[index]) or not light_holders[index].owns_light:
			light_holders.remove_at(index)
	if light_holders.size() >= MAX_LIGHTS:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var new_distance := camera.global_position.distance_squared_to(global_position)
		var furthest: ExplosionEffect = null
		var furthest_distance := new_distance * 1.3
		for effect: ExplosionEffect in light_holders:
			var distance := camera.global_position.distance_squared_to(effect.global_position)
			if distance > furthest_distance:
				furthest = effect
				furthest_distance = distance
		if furthest == null:
			return
		furthest._release_light()
	owns_light = true
	light_holders.append(self)

func _release_light() -> void:
	if not owns_light:
		return
	owns_light = false
	blast_light.visible = false
	light_holders.erase(self)

func _exit_tree() -> void:
	_release_light()
