class_name MissileVfxWarmup
extends SubViewport

signal completed

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")
const WARMUP_POSITION := Vector3(0.0, 0.0, -8.0)

func _init() -> void:
	name = "MissileVfxWarmup"
	size = Vector2i(32, 32)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _ready() -> void:
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	interceptor.position = WARMUP_POSITION
	add_child(interceptor)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	smoke.sample_world_segment(WARMUP_POSITION + Vector3.LEFT * 2.0, WARMUP_POSITION + Vector3.RIGHT * 2.0)

	await get_tree().process_frame
	await get_tree().process_frame
	completed.emit()
	queue_free()
