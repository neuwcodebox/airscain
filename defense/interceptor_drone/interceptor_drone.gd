class_name InterceptorDrone
extends Node3D

const INTERCEPT_GUIDANCE := preload("res://defense/intercept_guidance.gd")

enum State { OUTBOUND, RETURNING }

var base_owner: InterceptorDroneDefense
var target_track: PlayerTrack
var registry: ThreatRegistry
var owner_defense_id: int
var state := State.OUTBOUND
var speed: float
var turn_rate: float
var endurance: float
var damage: float
var proximity_radius: float
var age: float = 0.0
var velocity := Vector3.FORWARD

func configure(owner_value: InterceptorDroneDefense, track: PlayerTrack, registry_value: ThreatRegistry, definition: InterceptorDroneDefenseDefinition) -> void:
	base_owner = owner_value
	owner_defense_id = base_owner.runtime_id
	target_track = track
	registry = registry_value
	speed = definition.drone_speed
	turn_rate = deg_to_rad(definition.drone_turn_rate_degrees)
	endurance = definition.drone_endurance
	damage = definition.drone_damage
	proximity_radius = definition.proximity_radius
	velocity = global_position.direction_to(track.estimated_position).normalized() * speed

func gameplay_tick(delta: float) -> void:
	if base_owner == null or not is_instance_valid(base_owner):
		queue_free()
		return
	age += delta
	if state == State.OUTBOUND and (target_track == null or target_track.state == PlayerTrack.State.LOST or age >= endurance):
		_begin_returning()
	var destination := INTERCEPT_GUIDANCE.lead_point(global_position, speed, target_track.estimated_position, target_track.estimated_velocity, 2.4) if state == State.OUTBOUND else base_owner.global_position + Vector3.UP * 6.0
	var desired := global_position.direction_to(destination)
	var current := velocity.normalized()
	var angle := current.angle_to(desired)
	var direction := desired if angle <= turn_rate * delta else current.slerp(desired, turn_rate * delta / angle)
	velocity = direction.normalized() * speed
	var previous := global_position
	global_position += velocity * delta
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)
	if state == State.OUTBOUND:
		for threat: ThreatUnit in registry.get_active():
			var target_position := threat.get_aim_position()
			if Geometry3D.get_closest_point_to_segment(target_position, previous, global_position).distance_to(target_position) <= proximity_radius:
				threat.receive_damage(damage)
				_begin_returning()
				break
	elif global_position.distance_to(destination) <= 8.0:
		base_owner.recover_drone(self)
		queue_free()

func _begin_returning() -> void:
	if state == State.RETURNING:
		return
	state = State.RETURNING
	if target_track != null:
		base_owner.release_engagement(target_track.track_id)

func capture_state() -> Dictionary:
	return {"type": "interceptor_drone", "owner_defense_id": owner_defense_id, "target_track_id": target_track.track_id if target_track != null else -1, "position": SaveDocument.vector3_to_data(global_position), "velocity": SaveDocument.vector3_to_data(velocity), "state": int(state), "age": age}

func restore_state(data: Dictionary, owner_value: InterceptorDroneDefense, track: PlayerTrack, registry_value: ThreatRegistry) -> void:
	configure(owner_value, track, registry_value, owner_value.drone_definition())
	global_position = SaveDocument.vector3_from_data(data.position)
	velocity = SaveDocument.vector3_from_data(data.velocity)
	state = int(data.state) as State
	age = float(data.age)
