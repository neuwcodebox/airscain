class_name CombatVfxWarmup
extends SubViewport

signal completed

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")
const WARMUP_POSITION := Vector3(0.0, 0.0, -8.0)

func _init() -> void:
	name = "CombatVfxWarmup"
	size = Vector2i(32, 32)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _ready() -> void:
	_add_camera_and_light()
	_add_shadow_receiver()
	_add_interceptor_sample()
	_add_explosion_sample()
	await get_tree().process_frame
	await get_tree().process_frame
	completed.emit()
	queue_free()

func _add_camera_and_light() -> void:
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

func _add_shadow_receiver() -> void:
	var receiver := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	receiver.mesh = plane
	receiver.position = WARMUP_POSITION + Vector3.DOWN * 3.0
	add_child(receiver)

func _add_interceptor_sample() -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	interceptor.position = WARMUP_POSITION
	add_child(interceptor)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	smoke.sample_world_segment(WARMUP_POSITION + Vector3.LEFT * 2.0, WARMUP_POSITION + Vector3.RIGHT * 2.0)

func _add_explosion_sample() -> void:
	var explosion := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	explosion.position = WARMUP_POSITION + Vector3.RIGHT * 3.0
	add_child(explosion)
	explosion.setup(Color(1.0, 0.35, 0.06), 2.0)
	explosion._process(0.18)
