extends Node3D

const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")

@export var speed: float = 420.0

var target_position: Vector3

func setup(target: Vector3) -> void:
	target_position = target
	if global_position.distance_squared_to(target_position) > 0.001:
		look_at(target_position, Vector3.UP)

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
	look_at(target_position, Vector3.UP)
	_sample_trail(previous, global_position)

func _sample_trail(from_position: Vector3, to_position: Vector3) -> void:
	var smoke := $SmokeTrail as GPUParticles3D
	smoke.call("sample_world_segment", from_position, to_position)

func _impact() -> void:
	var parent := get_parent()
	if parent != null:
		var smoke := $SmokeTrail as GPUParticles3D
		smoke.call("release_to", parent)
		var explosion := EXPLOSION_SCENE.instantiate() as ExplosionEffect
		parent.add_child(explosion)
		explosion.global_position = target_position
		explosion.setup(Color("ffb02e"), 8.0)
	queue_free()
