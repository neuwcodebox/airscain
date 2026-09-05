class_name ShadowedSmokeParticles
extends GPUParticles3D

const SHADOW_NODE_NAME := "SmokeShadow"

var shadow_particles: GPUParticles3D
var shadow_material: ShaderMaterial
var current_shadow_opacity_ratio: float = 1.0

func _ready() -> void:
	_create_shadow_particles()
	set_process(true)

func _process(_delta: float) -> void:
	_sync_shadow_state()

func set_shadow_opacity_ratio(ratio: float) -> void:
	if shadow_material == null:
		return
	current_shadow_opacity_ratio = clampf(ratio, 0.0, 1.0)
	shadow_material.set_shader_parameter("opacity_ratio", current_shadow_opacity_ratio)

func _create_shadow_particles() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proxy := SmokeShadowFactory.create(draw_pass_1)
	if proxy == null:
		return
	shadow_material = proxy.material

	shadow_particles = GPUParticles3D.new()
	shadow_particles.name = SHADOW_NODE_NAME
	shadow_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
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
	shadow_particles.draw_pass_1 = proxy.mesh
	shadow_particles.use_fixed_seed = true
	use_fixed_seed = true
	shadow_particles.seed = seed
	add_child(shadow_particles)
	shadow_particles.emitting = emitting

func _sync_shadow_state() -> void:
	if shadow_particles == null:
		return
	if shadow_particles.amount != amount:
		shadow_particles.amount = amount
	if not is_equal_approx(shadow_particles.amount_ratio, amount_ratio):
		shadow_particles.amount_ratio = amount_ratio
	if not is_equal_approx(shadow_particles.lifetime, lifetime):
		shadow_particles.lifetime = lifetime
	if not is_equal_approx(shadow_particles.speed_scale, speed_scale):
		shadow_particles.speed_scale = speed_scale
	if shadow_particles.emitting != emitting:
		shadow_particles.emitting = emitting
