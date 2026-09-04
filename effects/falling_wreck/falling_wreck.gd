class_name FallingWreckEffect
extends Node3D

var velocity: Vector3
var ground_height: float
var elapsed: float = 0.0
var impacted: bool = false
var impact_flash_enabled: bool = true
var smoke_released: bool = false

@onready var wreck: Node3D = $Wreck
@onready var body: MeshInstance3D = $Wreck/Body
@onready var wing: MeshInstance3D = $Wreck/Wing
@onready var smoke: LingeringSmokeTrail = $SmokeTrail
@onready var impact_flash: MeshInstance3D = $ImpactFlash

func setup(color: Color, initial_velocity: Vector3, ground_height_value: float, wreck_scale: float = 1.0, smoke_enabled: bool = true, flash_enabled: bool = true) -> void:
	velocity = initial_velocity * 0.55 + Vector3(0.0, -4.0, 0.0)
	ground_height = ground_height_value
	impact_flash_enabled = flash_enabled
	wreck.scale = Vector3.ONE * wreck_scale
	_set_wreck_material(body, color)
	_set_wreck_material(wing, color)
	impact_flash.material_override = impact_flash.material_override.duplicate() as StandardMaterial3D
	smoke.emitting = smoke_enabled

func _set_wreck_material(mesh_instance: MeshInstance3D, color: Color) -> void:
	var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = color.darkened(0.45)
	mesh_instance.material_override = material

func _process(delta: float) -> void:
	elapsed += delta
	if not impacted:
		var previous_position := global_position
		velocity += Vector3.DOWN * 34.0 * delta
		global_position += velocity * delta
		smoke.sample_world_segment(previous_position, global_position)
		wreck.rotate_x(delta * 4.2)
		wreck.rotate_z(delta * 3.4)
		if global_position.y <= ground_height + 1.0:
			global_position.y = ground_height + 1.0
			impacted = true
			wreck.visible = false
			_release_smoke()
			impact_flash.visible = impact_flash_enabled
			elapsed = 0.0
	else:
		var impact_t := clampf(elapsed / 0.55, 0.0, 1.0)
		impact_flash.scale = Vector3.ONE * lerpf(1.0, 8.0, impact_t)
		var material := impact_flash.material_override as StandardMaterial3D
		material.albedo_color.a = 1.0 - impact_t
		if elapsed >= 1.4:
			queue_free()
	if not impacted and elapsed >= 5.0:
		_release_smoke()
		queue_free()

func _release_smoke() -> void:
	if smoke_released or not is_instance_valid(smoke):
		return
	smoke_released = true
	smoke.release_to(get_parent())
