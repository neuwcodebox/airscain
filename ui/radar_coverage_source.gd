class_name RadarCoverageSource
extends RefCounted

const POSITION_TOLERANCE_SQUARED := 0.0001
const RADIUS_TOLERANCE := 0.01

var key: String
var position: Vector3
var radius: float
var color: Color

func _init(key_value: String, position_value: Vector3, radius_value: float, color_value: Color) -> void:
	key = key_value
	position = position_value
	radius = radius_value
	color = color_value

func matches(other: RadarCoverageSource) -> bool:
	return other != null \
		and key == other.key \
		and position.distance_squared_to(other.position) <= POSITION_TOLERANCE_SQUARED \
		and absf(radius - other.radius) <= RADIUS_TOLERANCE \
		and color.is_equal_approx(other.color)
