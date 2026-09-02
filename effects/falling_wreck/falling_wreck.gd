class_name FallingWreckEffect
extends Node3D

var velocity: Vector3
var ground_height: float
var elapsed: float = 0.0
var impacted: bool = false

@onready var wreck: Node3D = $Wreck
@onready var smoke: GPUParticles3D = $SmokeTrail
@onready var impact_flash: MeshInstance3D = $ImpactFlash

func setup(color: Color, initial_velocity: Vector3, ground_height_value: float) -> void:
	velocity = initial_velocity * 0.55 + Vector3(0.0, -4.0, 0.0)
	ground_height = ground_height_value
	for child: Node in wreck.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
		material.albedo_color = color.darkened(0.45)
		mesh_instance.material_override = material
	smoke.emitting = true

func _process(delta: float) -> void:
	elapsed += delta
	if not impacted:
		velocity += Vector3.DOWN * 34.0 * delta
		global_position += velocity * delta
		wreck.rotate_x(delta * 4.2)
		wreck.rotate_z(delta * 3.4)
		if global_position.y <= ground_height + 1.0:
			global_position.y = ground_height + 1.0
			impacted = true
			wreck.visible = false
			smoke.emitting = false
			impact_flash.visible = true
			elapsed = 0.0
	else:
		var impact_t := clampf(elapsed / 0.55, 0.0, 1.0)
		impact_flash.scale = Vector3.ONE * lerpf(1.0, 8.0, impact_t)
		var material := impact_flash.material_override as StandardMaterial3D
		material.albedo_color.a = 1.0 - impact_t
		if elapsed >= 1.4:
			queue_free()
	if not impacted and elapsed >= 5.0:
		queue_free()
