class_name PlacementProfile
extends Resource

@export var footprint_radius: float = 10.0
@export var maximum_slope_degrees: float = 14.0
@export var boundary_margin: float = 15.0
@export var rooftop_allowed: bool = false

func validation_error() -> String:
	if footprint_radius <= 0.0 or maximum_slope_degrees < 0.0 or maximum_slope_degrees >= 90.0 or boundary_margin < 0.0:
		return "배치 profile 설정값이 올바르지 않습니다"
	return ""
