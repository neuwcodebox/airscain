class_name SmokePuffDistribution
extends RefCounted

class Sample:
	extends RefCounted

	var offset: Vector3
	var size_ratio: float
	var opacity_ratio: float
	var drift_direction: Vector3

	func _init(
			offset_value: Vector3,
			size_ratio_value: float,
			opacity_ratio_value: float,
			drift_direction_value: Vector3
	) -> void:
		offset = offset_value
		size_ratio = size_ratio_value
		opacity_ratio = opacity_ratio_value
		drift_direction = drift_direction_value

static func sample(serial: int, radius: float) -> Sample:
	var phase := _unit_value(serial, 0) * TAU
	var radius_ratio := sqrt(_unit_value(serial, 1))
	var height_jitter := lerpf(-0.45, 0.45, _unit_value(serial, 2))
	var offset := Vector3(cos(phase) * radius_ratio, height_jitter, sin(phase) * radius_ratio) * radius
	var size_ratio := lerpf(0.76, 1.3, _unit_value(serial, 3))
	var opacity_ratio := lerpf(0.62, 1.0, _unit_value(serial, 4))
	var drift_angle := _unit_value(serial, 5) * TAU
	var lateral_speed := lerpf(0.45, 1.1, _unit_value(serial, 6))
	var lift_speed := lerpf(0.28, 0.72, _unit_value(serial, 7))
	var drift_direction := Vector3(cos(drift_angle) * lateral_speed, lift_speed, sin(drift_angle) * lateral_speed)
	return Sample.new(offset, size_ratio, opacity_ratio, drift_direction)

static func casts_shadow(serial: int, stride: int) -> bool:
	var group := shadow_group(serial, stride)
	var selected_offset := mini(int(_unit_value(group + 1, 11) * float(stride)), stride - 1)
	return (serial - 1) % stride == selected_offset

static func shadow_group(serial: int, stride: int) -> int:
	return int((serial - 1) / stride)

static func _unit_value(serial: int, salt: int) -> float:
	var value := sin(float(serial) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return value - floorf(value)
