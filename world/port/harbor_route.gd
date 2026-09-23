class_name HarborRoute
extends RefCounted

const SHORE_STEPS := 80
const COAST_SAMPLES := 64
const MINIMUM_WATER_DEPTH := 3.0
const BERTH_OFFSET := 130.0
const CRUISE_SPEED := 8.0
const DOCK_SPEED := 0.9

var shore: Vector2
var berth: Vector2
var seaward: Vector2
var along_quay: Vector2
var sea_level: float
var inbound: PackedVector3Array = PackedVector3Array()
var outbound: PackedVector3Array = PackedVector3Array()
var inbound_times: PackedFloat32Array = PackedFloat32Array()
var outbound_times: PackedFloat32Array = PackedFloat32Array()

var inbound_duration: float:
	get: return inbound_times[inbound_times.size() - 1] if not inbound_times.is_empty() else 0.0

var outbound_duration: float:
	get: return outbound_times[outbound_times.size() - 1] if not outbound_times.is_empty() else 0.0

static func plan(field: Battlefield) -> HarborRoute:
	var best: HarborRoute
	var best_score := INF
	var sea := field.generator.sea_level
	var half := field.battlefield_size * 0.5
	for district: CityDistrict in field.city_districts:
		for sample_index: int in COAST_SAMPLES:
			var angle := TAU * float(sample_index) / float(COAST_SAMPLES)
			var outward := Vector2(cos(angle), sin(angle))
			var prior := district.center
			var prior_height := field.terrain_height(prior.x, prior.y)
			for step_index: int in range(1, SHORE_STEPS + 1):
				var distance := half * 1.5 * float(step_index) / float(SHORE_STEPS)
				var sample := district.center + outward * distance
				var height := field.terrain_height(sample.x, sample.y)
				if prior_height > sea and height <= sea:
					var shore_point := prior.lerp(sample, clampf((prior_height - sea) / maxf(prior_height - height, 0.001), 0.0, 1.0))
					for side: float in [-1.0, 1.0]:
						var candidate := HarborRoute.new()
						candidate.shore = shore_point
						candidate.berth = shore_point + outward * BERTH_OFFSET
						candidate.seaward = outward
						candidate.along_quay = Vector2(-outward.y, outward.x) * side
						candidate.sea_level = sea
						candidate._build(field.battlefield_size)
						if not candidate._has_clear_water(field):
							continue
						var role_bonus := 110.0 if district.definition.role in [CityDistrictDefinition.Role.INDUSTRIAL, CityDistrictDefinition.Role.TRANSPORT] else 0.0
						var score := distance - role_bonus
						if score < best_score:
							best = candidate
							best_score = score
					break
				prior = sample
				prior_height = height
	return best

func _build(battlefield_size: float) -> void:
	var far := berth + seaward * (battlefield_size * 2.3) - along_quay * 400.0
	var turn := berth + seaward * 540.0 - along_quay * 300.0
	inbound = _append_line(inbound, far, turn, 96)
	inbound = _append_curve(inbound, turn, berth + seaward * 330.0 - along_quay * 330.0, berth - along_quay * 130.0, berth, 64)
	var exit_turn := berth + seaward * 540.0 + along_quay * 300.0
	outbound = _append_curve(outbound, berth, berth + along_quay * 130.0, berth + seaward * 330.0 + along_quay * 330.0, exit_turn, 64)
	outbound = _append_line(outbound, exit_turn, berth + seaward * (battlefield_size * 2.3) + along_quay * 400.0, 96)
	inbound_times = _travel_times(inbound, true)
	outbound_times = _travel_times(outbound, false)

func _has_clear_water(field: Battlefield) -> bool:
	for path: PackedVector3Array in [inbound, outbound]:
		for point: Vector3 in path:
			if field.terrain_height(point.x, point.z) > sea_level - MINIMUM_WATER_DEPTH:
				return false
	return true

func _append_line(points: PackedVector3Array, start: Vector2, finish: Vector2, count: int) -> PackedVector3Array:
	for index: int in range(count + 1):
		var point := start.lerp(finish, float(index) / float(count))
		points.append(Vector3(point.x, sea_level, point.y))
	return points

func _append_curve(points: PackedVector3Array, start: Vector2, control_a: Vector2, control_b: Vector2, finish: Vector2, count: int) -> PackedVector3Array:
	if points.is_empty():
		points.append(Vector3(start.x, sea_level, start.y))
	for index: int in range(1, count + 1):
		var t := float(index) / float(count)
		var inverse := 1.0 - t
		var point := start * inverse * inverse * inverse + control_a * 3.0 * inverse * inverse * t + control_b * 3.0 * inverse * t * t + finish * t * t * t
		points.append(Vector3(point.x, sea_level, point.y))
	return points

func _travel_times(points: PackedVector3Array, inbound_path: bool) -> PackedFloat32Array:
	var result := PackedFloat32Array([0.0])
	var distances := PackedFloat32Array([0.0])
	for index: int in range(1, points.size()):
		distances.append(distances[index - 1] + points[index - 1].distance_to(points[index]))
	var total := distances[distances.size() - 1]
	for index: int in range(1, points.size()):
		var berth_distance := total - distances[index] if inbound_path else distances[index]
		var speed := lerpf(DOCK_SPEED, CRUISE_SPEED, smoothstep(0.0, 150.0, berth_distance))
		result.append(result[index - 1] + (distances[index] - distances[index - 1]) / speed)
	return result

func inbound_pose(elapsed: float) -> Transform3D:
	return _pose_at(inbound, inbound_times, elapsed)

func outbound_pose(elapsed: float) -> Transform3D:
	return _pose_at(outbound, outbound_times, elapsed)

func _pose_at(points: PackedVector3Array, times: PackedFloat32Array, elapsed: float) -> Transform3D:
	var time := clampf(elapsed, 0.0, times[times.size() - 1])
	var low := 0
	var high := times.size() - 1
	while high - low > 1:
		var midpoint := (low + high) / 2
		if times[midpoint] <= time:
			low = midpoint
		else:
			high = midpoint
	var weight := inverse_lerp(times[low], times[high], time)
	var position := points[low].lerp(points[high], weight)
	var direction := (points[high] - points[low]).normalized()
	return Transform3D(Basis.looking_at(direction, Vector3.UP), position)
