class_name ThreatMover
extends RefCounted

var profile: ThreatMovementDefinition
var battlefield: Battlefield
var velocity: Vector3
var ballistic_origin: Vector3
var ballistic_target: Vector3
var ballistic_progress: float = 0.0
var ballistic_duration: float = 1.0
var ballistic_initialized: bool = false

func setup(profile_value: ThreatMovementDefinition, battlefield_value: Battlefield, initial_direction: Vector3) -> void:
	profile = profile_value
	battlefield = battlefield_value
	var horizontal_direction := Vector3(initial_direction.x, 0.0, initial_direction.z).normalized()
	velocity = horizontal_direction * profile.speed
	ballistic_initialized = false
	ballistic_progress = 0.0

func advance(unit: Node3D, body: Node3D, target: Vector3, speed_multiplier: float, delta: float, preserve_target_altitude: bool = false, force_terminal: bool = false) -> void:
	var effective_speed_multiplier := minf(speed_multiplier, profile.maximum_speed_multiplier)
	if profile.mode == ThreatMovementDefinition.Mode.BALLISTIC_ARC:
		_advance_ballistic(unit, body, target, effective_speed_multiplier, delta)
		return
	var desired_position := target
	var horizontal_to_target := Vector2(target.x - unit.global_position.x, target.z - unit.global_position.z)
	var terminal_phase := force_terminal or horizontal_to_target.length() <= profile.terminal_distance
	if preserve_target_altitude:
		desired_position.y = maxf(target.y, battlefield.flight_surface_height(target.x, target.z) + profile.cruise_altitude)
	elif not terminal_phase:
		desired_position.y = _cruise_height(unit.global_position, horizontal_to_target)
	else:
		desired_position.y = battlefield.flight_surface_height(target.x, target.z) + profile.terminal_altitude
	var desired_direction := unit.global_position.direction_to(desired_position)
	if desired_direction.length_squared() <= 0.0001:
		return
	var current_direction := velocity.normalized() if velocity.length_squared() > 0.0001 else desired_direction
	var angle := current_direction.angle_to(desired_direction)
	var terminal_turn_multiplier := 3.0 if terminal_phase and profile.mode == ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING else 1.0
	var turn_weight := 1.0 if angle <= 0.0001 else minf(1.0, deg_to_rad(profile.maximum_turn_rate_degrees) * terminal_turn_multiplier * delta / angle)
	var steered_direction := current_direction.slerp(desired_direction, turn_weight).normalized()
	var terminal_speed_scale := lerpf(0.35, 1.0, maxf(0.0, steered_direction.dot(desired_direction))) if terminal_phase else 1.0
	var movement_speed := profile.speed * effective_speed_multiplier * terminal_speed_scale
	var desired_vertical_speed := steered_direction.y * movement_speed
	var vertical_speed := move_toward(velocity.y, desired_vertical_speed, profile.maximum_climb_rate * delta)
	velocity = steered_direction * movement_speed
	velocity.y = vertical_speed
	var previous_position := unit.global_position
	var movement := velocity * delta
	if horizontal_to_target.length() <= profile.terminal_distance and previous_position.distance_to(desired_position) <= movement.length():
		unit.global_position = desired_position
		velocity = (unit.global_position - previous_position) / maxf(delta, 0.0001)
	else:
		unit.global_position += movement
	if preserve_target_altitude or not terminal_phase:
		var clearance_ratio := 0.6 if profile.mode == ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING else 0.35
		var safety_height := battlefield.flight_surface_height(unit.global_position.x, unit.global_position.z) + profile.cruise_altitude * clearance_ratio
		if unit.global_position.y < safety_height:
			unit.global_position.y = safety_height
			velocity.y = maxf(0.0, velocity.y)
	if velocity.length_squared() > 0.001:
		body.look_at(unit.global_position + velocity.normalized(), Vector3.UP)

func capture_state() -> Dictionary:
	return {"velocity": SaveDocument.vector3_to_data(velocity), "ballistic_origin": SaveDocument.vector3_to_data(ballistic_origin), "ballistic_target": SaveDocument.vector3_to_data(ballistic_target), "ballistic_progress": ballistic_progress, "ballistic_duration": ballistic_duration, "ballistic_initialized": ballistic_initialized}

func restore_state(state: Dictionary, profile_value: ThreatMovementDefinition, battlefield_value: Battlefield) -> void:
	profile = profile_value
	battlefield = battlefield_value
	velocity = SaveDocument.vector3_from_data(state.get("velocity", []))
	ballistic_origin = SaveDocument.vector3_from_data(state.get("ballistic_origin", []))
	ballistic_target = SaveDocument.vector3_from_data(state.get("ballistic_target", []))
	ballistic_progress = float(state.get("ballistic_progress", 0.0))
	ballistic_duration = float(state.get("ballistic_duration", 1.0))
	ballistic_initialized = bool(state.get("ballistic_initialized", false))

func _advance_ballistic(unit: Node3D, body: Node3D, target: Vector3, speed_multiplier: float, delta: float) -> void:
	if not ballistic_initialized:
		ballistic_origin = unit.global_position
		ballistic_target = Vector3(target.x, battlefield.flight_surface_height(target.x, target.z) + profile.terminal_altitude, target.z)
		ballistic_duration = maxf(0.1, Vector2(ballistic_target.x - ballistic_origin.x, ballistic_target.z - ballistic_origin.z).length() / (profile.speed * speed_multiplier))
		ballistic_initialized = true
	var previous := unit.global_position
	ballistic_progress = minf(1.0, ballistic_progress + delta / ballistic_duration)
	var horizontal_progress := 0.0
	var altitude := ballistic_origin.y
	var apex_altitude := maxf(ballistic_origin.y, ballistic_target.y) + profile.ballistic_apex
	if ballistic_progress < profile.ballistic_boost_fraction:
		var phase := ballistic_progress / profile.ballistic_boost_fraction
		horizontal_progress = lerpf(0.0, 0.07, phase * phase)
		altitude = lerpf(ballistic_origin.y, apex_altitude, 1.0 - pow(1.0 - phase, 2.0))
	elif ballistic_progress < profile.ballistic_reentry_fraction:
		var phase := (ballistic_progress - profile.ballistic_boost_fraction) / (profile.ballistic_reentry_fraction - profile.ballistic_boost_fraction)
		horizontal_progress = lerpf(0.07, 0.70, phase)
		altitude = lerpf(apex_altitude, ballistic_target.y + profile.ballistic_apex * 0.82, smoothstep(0.0, 1.0, phase))
	else:
		var phase := (ballistic_progress - profile.ballistic_reentry_fraction) / (1.0 - profile.ballistic_reentry_fraction)
		horizontal_progress = lerpf(0.70, 1.0, phase)
		altitude = lerpf(ballistic_target.y + profile.ballistic_apex * 0.82, ballistic_target.y, phase * phase)
	unit.global_position = ballistic_origin.lerp(ballistic_target, horizontal_progress)
	unit.global_position.y = altitude
	velocity = (unit.global_position - previous) / maxf(delta, 0.0001)
	if velocity.length_squared() > 0.001:
		body.look_at(unit.global_position + velocity.normalized(), Vector3.UP)

func ballistic_phase() -> StringName:
	if not ballistic_initialized or ballistic_progress < profile.ballistic_boost_fraction:
		return &"boost"
	if ballistic_progress < profile.ballistic_reentry_fraction:
		return &"midcourse"
	return &"reentry"

func _cruise_height(position: Vector3, horizontal_to_target: Vector2) -> float:
	var terrain_height := battlefield.flight_surface_height(position.x, position.z)
	if profile.mode == ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING and horizontal_to_target.length_squared() > 0.001:
		var direction := horizontal_to_target.normalized()
		var lookahead_position := Vector2(position.x, position.z) + direction * profile.terrain_lookahead
		terrain_height = maxf(terrain_height, battlefield.flight_surface_height(lookahead_position.x, lookahead_position.y))
	return terrain_height + profile.cruise_altitude
