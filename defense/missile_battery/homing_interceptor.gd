class_name HomingInterceptor
extends Node3D

var target: ThreatUnit
var speed: float = 180.0
var turn_rate: float = deg_to_rad(240.0)
var maximum_lifetime: float = 5.0
var damage: float = 100.0
var age: float = 0.0
var velocity: Vector3 = Vector3.FORWARD

func configure(target_value: ThreatUnit, definition: MissileBatteryDefinition, initial_direction: Vector3) -> void:
	target = target_value
	speed = definition.interceptor_speed
	turn_rate = deg_to_rad(definition.interceptor_turn_rate_degrees)
	maximum_lifetime = definition.interceptor_lifetime
	damage = definition.interceptor_damage
	velocity = initial_direction.normalized() * speed

func gameplay_tick(delta: float) -> void:
	if not is_instance_valid(target) or not target.is_targetable():
		queue_free()
		return
	age += delta
	if age >= maximum_lifetime:
		queue_free()
		return
	var previous := global_position
	var desired := global_position.direction_to(target.get_aim_position())
	var current := velocity.normalized()
	var angle := current.angle_to(desired)
	var direction := desired if angle <= turn_rate * delta else current.slerp(desired, (turn_rate * delta) / angle)
	velocity = direction.normalized() * speed
	global_position += velocity * delta
	look_at(global_position + velocity, Vector3.UP)
	var nearest := Geometry3D.get_closest_point_to_segment(target.get_aim_position(), previous, global_position)
	if nearest.distance_to(target.get_aim_position()) <= 6.0:
		target.receive_damage(damage)
		queue_free()
