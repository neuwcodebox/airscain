extends RefCounted

static func lead_point(origin: Vector3, interceptor_speed: float, target_position: Vector3, target_velocity: Vector3, maximum_lookahead: float) -> Vector3:
	if interceptor_speed <= 0.0 or maximum_lookahead <= 0.0:
		return target_position
	var relative := target_position - origin
	var a := target_velocity.length_squared() - interceptor_speed * interceptor_speed
	var b := 2.0 * relative.dot(target_velocity)
	var c := relative.length_squared()
	var intercept_time := -1.0
	if absf(a) <= 0.0001:
		if absf(b) > 0.0001:
			intercept_time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			var first := (-b - root) / (2.0 * a)
			var second := (-b + root) / (2.0 * a)
			if first > 0.0:
				intercept_time = first
			if second > 0.0 and (intercept_time < 0.0 or second < intercept_time):
				intercept_time = second
	if intercept_time <= 0.0:
		intercept_time = relative.length() / interceptor_speed
	return target_position + target_velocity * minf(intercept_time, maximum_lookahead)
