class_name HomingInterceptor
extends Node3D

var target_track: PlayerTrack
var registry: ThreatRegistry
var owner_defense_id: int
var speed: float = 200.0
var turn_rate: float = deg_to_rad(240.0)
var maximum_lifetime: float = 5.0
var damage: float = 100.0
var proximity_radius: float = 15.0
var age: float = 0.0
var velocity: Vector3 = Vector3.FORWARD

func configure(track_value: PlayerTrack, registry_value: ThreatRegistry, definition: MissileBatteryDefinition, initial_direction: Vector3, owner_id: int = 0) -> void:
	target_track = track_value
	registry = registry_value
	owner_defense_id = owner_id
	speed = definition.interceptor_speed
	turn_rate = deg_to_rad(definition.interceptor_turn_rate_degrees)
	maximum_lifetime = definition.interceptor_lifetime
	damage = definition.interceptor_damage
	proximity_radius = definition.proximity_radius
	velocity = initial_direction.normalized() * speed

func gameplay_tick(delta: float) -> void:
	if target_track == null or target_track.state == PlayerTrack.State.LOST:
		queue_free()
		return
	age += delta
	if age >= maximum_lifetime:
		queue_free()
		return
	var previous := global_position
	var desired := global_position.direction_to(target_track.estimated_position)
	var current := velocity.normalized()
	var angle := current.angle_to(desired)
	var direction := desired if angle <= turn_rate * delta else current.slerp(desired, (turn_rate * delta) / angle)
	velocity = direction.normalized() * speed
	global_position += velocity * delta
	look_at(global_position + velocity, Vector3.UP)
	for threat: ThreatUnit in registry.get_active():
		var physical_position := threat.get_aim_position()
		var nearest := Geometry3D.get_closest_point_to_segment(physical_position, previous, global_position)
		if nearest.distance_to(physical_position) <= proximity_radius:
			threat.receive_damage(damage)
			queue_free()
			return

func capture_state() -> Dictionary:
	return {
		"type": "homing_interceptor",
		"owner_defense_id": owner_defense_id,
		"target_track_id": target_track.track_id if target_track != null else -1,
		"position": SaveDocument.vector3_to_data(global_position),
		"velocity": SaveDocument.vector3_to_data(velocity),
		"speed": speed,
		"turn_rate": turn_rate,
		"maximum_lifetime": maximum_lifetime,
		"damage": damage,
		"proximity_radius": proximity_radius,
		"age": age,
	}

func restore_state(state: Dictionary, track: PlayerTrack, registry_value: ThreatRegistry) -> void:
	target_track = track
	registry = registry_value
	owner_defense_id = int(state.owner_defense_id)
	global_position = SaveDocument.vector3_from_data(state.position)
	velocity = SaveDocument.vector3_from_data(state.velocity)
	speed = float(state.speed)
	turn_rate = float(state.turn_rate)
	maximum_lifetime = float(state.maximum_lifetime)
	damage = float(state.damage)
	proximity_radius = float(state.proximity_radius)
	age = float(state.age)
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)
