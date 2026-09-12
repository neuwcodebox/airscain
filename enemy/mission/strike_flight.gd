class_name StrikeFlight
extends RefCounted
## Flight state only: no scene nodes, damage, audio, or particle dependencies.

enum Mode { DIRECT, BOMB, MISSILE }
enum Result { FLYING, IMPACT, EXPIRED }

const GRAVITY := 9.8
const IGNITION_DELAY := 0.18
const MAXIMUM_STEP := 1.0 / 120.0
const MISSILE_TERMINAL_DISTANCE := 200.0
const MISSILE_LOFT_HEIGHT := 250.0

var mode := Mode.DIRECT
var velocity := Vector3.ZERO
var elapsed: float = 0.0
var speed: float = 420.0
var acceleration: float = 260.0
var result := Result.FLYING

func powered() -> bool:
	return mode == Mode.DIRECT or mode == Mode.MISSILE and elapsed >= IGNITION_DELAY

func advance(position: Vector3, target: Vector3, battlefield: Battlefield, delta: float) -> Vector3:
	if result != Result.FLYING or delta <= 0.0:
		return position
	if mode == Mode.DIRECT:
		if position.distance_to(target) <= speed * delta:
			result = Result.IMPACT
			return target
		return position + position.direction_to(target) * speed * delta
	var previous_velocity := velocity
	elapsed += delta
	if mode == Mode.BOMB or elapsed < IGNITION_DELAY:
		velocity.y -= GRAVITY * delta
	else:
		var desired := position.direction_to(_guidance_point(position, target, battlefield))
		var direction := velocity.normalized()
		var angle := direction.angle_to(desired)
		if angle > 0.0001:
			direction = direction.slerp(desired, minf(1.0, deg_to_rad(100.0) * delta / angle))
		velocity = direction * move_toward(velocity.length(), speed, acceleration * delta)
	var next := position + (previous_velocity + velocity) * (0.5 * delta)
	var impact := surface_impact(battlefield, position, next)
	if not impact.is_empty():
		result = Result.IMPACT
		return impact.position
	if mode == Mode.MISSILE and Geometry3D.get_closest_point_to_segment(target, position, next).distance_to(target) <= 4.0:
		result = Result.IMPACT
		return target
	if mode == Mode.BOMB and battlefield == null and next.y <= target.y and velocity.y < 0.0:
		result = Result.IMPACT
		return position.lerp(next, clampf((position.y - target.y) / maxf(0.0001, position.y - next.y), 0.0, 1.0))
	if elapsed >= 20.0:
		result = Result.EXPIRED
	return next

func _guidance_point(position: Vector3, target: Vector3, battlefield: Battlefield) -> Vector3:
	var point := target
	var horizontal := Vector2(position.x - target.x, position.z - target.z)
	if horizontal.length() > MISSILE_TERMINAL_DISTANCE:
		var outward := horizontal.normalized() * MISSILE_TERMINAL_DISTANCE
		point.x += outward.x
		point.z += outward.y
		point.y += MISSILE_LOFT_HEIGHT
		if battlefield != null:
			var ahead := position + velocity.normalized() * 80.0
			point.y = maxf(point.y, battlefield.flight_surface_height(ahead.x, ahead.z) + 30.0)
	return point

static func surface_impact(battlefield: Battlefield, from: Vector3, to: Vector3) -> Dictionary:
	if battlefield == null:
		return {}
	var impact := battlefield.building_segment_impact(from, to)
	var terrain := battlefield.terrain_segment_impact(from, to)
	if not terrain.is_empty() and (impact.is_empty() or from.distance_squared_to(terrain.position) < from.distance_squared_to(impact.position)):
		return terrain
	return impact

func capture_state() -> Dictionary:
	return {"speed": speed, "flight_mode": int(mode), "velocity": SaveDocument.vector3_to_data(velocity), "elapsed": elapsed}

func restore_state(state: Dictionary) -> void:
	speed = float(state.speed)
	mode = int(state.get("flight_mode", Mode.DIRECT)) as Mode
	velocity = SaveDocument.vector3_from_data(state.get("velocity", [0, 0, 0]))
	elapsed = float(state.get("elapsed", 0.0))
	result = Result.FLYING

static func state_validation_error(state: Dictionary) -> String:
	if not is_finite(float(state.get("speed", 0.0))) or float(state.get("speed", 0.0)) <= 0.0:
		return "공대지 탄 비행 상태가 올바르지 않습니다"
	if int(state.get("flight_mode", Mode.DIRECT)) not in Mode.values() or not is_finite(float(state.get("elapsed", 0.0))) or float(state.get("elapsed", 0.0)) < 0.0:
		return "투발 무장 비행 단계가 올바르지 않습니다"
	if int(state.get("flight_mode", Mode.DIRECT)) != Mode.DIRECT:
		var data: Variant = state.get("velocity")
		if not SaveDocument.is_valid_vector3_data(data):
			return "투발 무장 속도가 올바르지 않습니다"
	return ""
