extends GPUParticles3D

const SHADOW_NODE_NAME := "SmokeShadow"
const SHADOW_SHADER := preload("res://effects/smoke_shadow.gdshader")

var shadow_particles: GPUParticles3D
var shadow_material: ShaderMaterial
var current_shadow_opacity_ratio: float = 1.0

func _ready() -> void:
	_create_shadow_particles()
	set_process(true)

func _process(_delta: float) -> void:
	_sync_shadow_state()

func emit_smoke_particle(
		particle_transform: Transform3D,
		velocity: Vector3,
		particle_color: Color,
		custom: Color,
		flags: int
) -> void:
	emit_particle(particle_transform, velocity, particle_color, custom, flags)
	if shadow_particles != null:
		shadow_particles.emit_particle(particle_transform, velocity, particle_color, custom, flags)

func set_shadow_opacity_ratio(ratio: float) -> void:
	if shadow_material == null:
		return
	current_shadow_opacity_ratio = clampf(ratio, 0.0, 1.0)
	shadow_material.set_shader_parameter("opacity_ratio", current_shadow_opacity_ratio)

func _create_shadow_particles() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var source_mesh := draw_pass_1
	if source_mesh == null or source_mesh.get_surface_count() == 0:
		return
	var source_material := source_mesh.surface_get_material(0)
	if source_material is not StandardMaterial3D:
		return

	var shadow_mesh := source_mesh.duplicate() as Mesh
	var standard_material := source_material as StandardMaterial3D
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = SHADOW_SHADER
	shadow_material.set_shader_parameter("billboard_enabled", standard_material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED)
	shadow_mesh.surface_set_material(0, shadow_material)

	shadow_particles = GPUParticles3D.new()
	shadow_particles.name = SHADOW_NODE_NAME
	shadow_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shadow_particles.amount = amount
	shadow_particles.amount_ratio = amount_ratio
	shadow_particles.lifetime = lifetime
	shadow_particles.one_shot = one_shot
	shadow_particles.preprocess = preprocess
	shadow_particles.explosiveness = explosiveness
	shadow_particles.randomness = randomness
	shadow_particles.visibility_aabb = visibility_aabb
	shadow_particles.local_coords = local_coords
	shadow_particles.fixed_fps = fixed_fps
	shadow_particles.fract_delta = fract_delta
	shadow_particles.interp_to_end = interp_to_end
	shadow_particles.speed_scale = speed_scale
	shadow_particles.process_material = process_material
	shadow_particles.draw_pass_1 = shadow_mesh
	shadow_particles.use_fixed_seed = true
	use_fixed_seed = true
	shadow_particles.seed = seed
	add_child(shadow_particles)
	shadow_particles.emitting = emitting

func _sync_shadow_state() -> void:
	if shadow_particles == null:
		return
	shadow_particles.amount_ratio = amount_ratio
	shadow_particles.speed_scale = speed_scale
	if shadow_particles.emitting != emitting:
		shadow_particles.emitting = emitting
