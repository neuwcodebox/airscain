class_name TurretAimer
extends RefCounted

static func aim(yaw_pivot: Node3D, elevation_pivot: Node3D, target_position: Vector3, yaw_speed_degrees: float, pitch_speed_degrees: float, alignment_degrees: float, delta: float, minimum_pitch_degrees: float = -5.0, maximum_pitch_degrees: float = 82.0) -> bool:
	var direction := target_position - yaw_pivot.global_position
	var horizontal_distance := Vector2(direction.x, direction.z).length()
	if direction.length_squared() <= 0.01:
		return true
	var desired_yaw := atan2(-direction.x, -direction.z)
	var desired_pitch := clampf(atan2(direction.y, horizontal_distance), deg_to_rad(minimum_pitch_degrees), deg_to_rad(maximum_pitch_degrees))
	yaw_pivot.rotation.y = rotate_toward(yaw_pivot.rotation.y, desired_yaw, deg_to_rad(yaw_speed_degrees) * delta)
	elevation_pivot.rotation.x = rotate_toward(elevation_pivot.rotation.x, desired_pitch, deg_to_rad(pitch_speed_degrees) * delta)
	var tolerance := deg_to_rad(alignment_degrees)
	return absf(angle_difference(yaw_pivot.rotation.y, desired_yaw)) <= tolerance and absf(angle_difference(elevation_pivot.rotation.x, desired_pitch)) <= tolerance
