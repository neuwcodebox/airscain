class_name ThreatMover
extends RefCounted

var profile: ThreatMovementDefinition
var battlefield: Battlefield
var velocity: Vector3

func setup(profile_value: ThreatMovementDefinition, battlefield_value: Battlefield, initial_direction: Vector3) -> void:
	profile = profile_value
	battlefield = battlefield_value
	var horizontal_direction := Vector3(initial_direction.x, 0.0, initial_direction.z).normalized()
	velocity = horizontal_direction * profile.speed

func advance(unit: Node3D, body: Node3D, target: Vector3, speed_multiplier: float, delta: float) -> void:
	var desired_position := target
	var horizontal_to_target := Vector2(target.x - unit.global_position.x, target.z - unit.global_position.z)
	if horizontal_to_target.length() > profile.terminal_distance:
		desired_position.y = _cruise_height(unit.global_position, horizontal_to_target)
	else:
		desired_position.y = battlefield.terrain_height(target.x, target.z) + 2.0
	var desired_direction := unit.global_position.direction_to(desired_position)
	if desired_direction.length_squared() <= 0.0001:
		return
	var current_direction := velocity.normalized() if velocity.length_squared() > 0.0001 else desired_direction
	var angle := current_direction.angle_to(desired_direction)
	var turn_weight := 1.0 if angle <= 0.0001 else minf(1.0, deg_to_rad(profile.maximum_turn_rate_degrees) * delta / angle)
	var steered_direction := current_direction.slerp(desired_direction, turn_weight).normalized()
	var desired_vertical_speed := steered_direction.y * profile.speed * speed_multiplier
	var vertical_speed := move_toward(velocity.y, desired_vertical_speed, profile.maximum_climb_rate * delta)
	velocity = steered_direction * profile.speed * speed_multiplier
	velocity.y = vertical_speed
	unit.global_position += velocity * delta
	if profile.mode == ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING:
		var safety_height := battlefield.terrain_height(unit.global_position.x, unit.global_position.z) + profile.cruise_altitude * 0.6
		if unit.global_position.y < safety_height:
			unit.global_position.y = safety_height
			velocity.y = maxf(0.0, velocity.y)
	if velocity.length_squared() > 0.001:
		body.look_at(unit.global_position + velocity.normalized(), Vector3.UP)

func capture_state() -> Dictionary:
	return {"velocity": SaveDocument.vector3_to_data(velocity)}

func restore_state(state: Dictionary, profile_value: ThreatMovementDefinition, battlefield_value: Battlefield) -> void:
	profile = profile_value
	battlefield = battlefield_value
	velocity = SaveDocument.vector3_from_data(state.get("velocity", []))

func _cruise_height(position: Vector3, horizontal_to_target: Vector2) -> float:
	var terrain_height := battlefield.terrain_height(position.x, position.z)
	if profile.mode == ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING and horizontal_to_target.length_squared() > 0.001:
		var direction := horizontal_to_target.normalized()
		var lookahead_position := Vector2(position.x, position.z) + direction * profile.terrain_lookahead
		terrain_height = maxf(terrain_height, battlefield.terrain_height(lookahead_position.x, lookahead_position.y))
	return terrain_height + profile.cruise_altitude
