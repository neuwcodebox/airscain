extends Node3D

const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")

@export var speed: float = 420.0

var target_position: Vector3
var objective: ProtectedObjective
var damage: int

func setup(target: Vector3, objective_value: ProtectedObjective, damage_value: int) -> void:
	target_position = target
	objective = objective_value
	damage = maxi(1, damage_value)
	if global_position.distance_squared_to(target_position) > 0.001:
		_orient_to_target()

func capture_state() -> Dictionary:
	return {
		"type": "air_strike_munition",
		"position": SaveDocument.vector3_to_data(global_position),
		"target_position": SaveDocument.vector3_to_data(target_position),
		"speed": speed,
		"damage": damage,
	}

func restore_state(state: Dictionary, objective_value: ProtectedObjective) -> void:
	global_position = SaveDocument.vector3_from_data(state.position)
	speed = float(state.speed)
	setup(SaveDocument.vector3_from_data(state.target_position), objective_value, int(state.damage))

func _process(delta: float) -> void:
	var previous := global_position
	var distance := global_position.distance_to(target_position)
	var travel := speed * delta
	if distance <= travel:
		global_position = target_position
		_sample_trail(previous, global_position)
		_impact()
		return
	global_position += global_position.direction_to(target_position) * travel
	_orient_to_target()
	_sample_trail(previous, global_position)

func _orient_to_target() -> void:
	var direction := global_position.direction_to(target_position)
	var up_direction := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	look_at(target_position, up_direction)

func _sample_trail(from_position: Vector3, to_position: Vector3) -> void:
	var smoke := $SmokeTrail as GPUParticles3D
	smoke.call("sample_world_segment", from_position, to_position)

func _impact() -> void:
	if objective != null and is_instance_valid(objective):
		objective.apply_surface_impact(damage, target_position)
	var parent := get_parent()
	if parent != null:
		var smoke := $SmokeTrail as GPUParticles3D
		smoke.call("release_to", parent)
		var explosion := EXPLOSION_SCENE.instantiate() as ExplosionEffect
		parent.add_child(explosion)
		explosion.global_position = target_position
		explosion.setup(Color("ffb02e"), 8.0)
	queue_free()
