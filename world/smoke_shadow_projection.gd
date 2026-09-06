class_name SmokeShadowProjection
extends Node

const MAP_SIZE: int = 2048
const STRENGTH: float = 0.28
var viewport: SubViewport
var camera: Camera3D
var sun: DirectionalLight3D
var battlefield: Battlefield
var receivers: Array[ShaderMaterial] = []
var _check_remaining: float = 0.0

func configure(light: DirectionalLight3D, field: Battlefield) -> void:
	sun = light
	battlefield = field
	sun.shadow_caster_mask &= ~SmokeShadowFactory.SMOKE_LAYER
	var main_camera := sun.get_viewport().get_camera_3d()
	if main_camera != null:
		main_camera.cull_mask &= ~SmokeShadowFactory.SMOKE_LAYER
	viewport = SubViewport.new()
	viewport.name = "SmokeShadowMap"
	viewport.size = Vector2i(MAP_SIZE, MAP_SIZE)
	viewport.world_3d = sun.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	add_child(viewport)
	camera = Camera3D.new()
	camera.cull_mask = SmokeShadowFactory.SMOKE_LAYER
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.WHITE
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	viewport.add_child(camera)
	configure_receivers()
	update_projection()
	# Allocate and clear the render target during startup, not on the first impact.
	_check_remaining = 0.1
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func configure_receivers() -> void:
	receivers = [battlefield.terrain.material_override as ShaderMaterial]
	receivers.append_array(battlefield.smoke_shadow_materials)
	for material: ShaderMaterial in receivers:
		material.set_shader_parameter("smoke_shadow_map", viewport.get_texture())

func _process(delta: float) -> void:
	_check_remaining -= delta
	if _check_remaining <= 0.0:
		_check_remaining = 0.1
		update_projection()

func update_projection() -> void:
	var enabled := sun.visible and sun.light_energy > 0.0 and SmokeShadowFactory.has_visible_casters(sun.get_world_3d())
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	var extent := battlefield.battlefield_size * 1.5
	camera.size = extent
	camera.near = 0.1
	camera.far = extent * 3.0
	camera.global_transform = Transform3D(sun.global_basis, sun.global_basis.z * extent * 1.5)
	var projection := camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse())
	for material: ShaderMaterial in receivers:
		material.set_shader_parameter("smoke_shadow_projection", projection)
		material.set_shader_parameter("smoke_shadow_strength", STRENGTH * sun.shadow_opacity if enabled else 0.0)
