class_name CityDistrictDefinition
extends Resource

enum Role { CORE, RESIDENTIAL, INDUSTRIAL, TRANSPORT }

@export var id: StringName
@export var role := Role.CORE
@export var center: Vector2 = Vector2.ZERO
@export_range(-180.0, 180.0) var rotation_degrees: float = 0.0
@export var size: float = 480.0
@export var block_count: int = 13
@export var minimum_building_height: float = 8.0
@export var maximum_building_height: float = 70.0
@export_range(0.0, 4.0) var target_weight: float = 1.0

func validation_error() -> String:
	if id.is_empty() or not center.is_finite() or not is_finite(rotation_degrees) or size <= 0.0 or block_count < 3 or minimum_building_height <= 0.0 or maximum_building_height < minimum_building_height or target_weight <= 0.0:
		return "도시 지구 설정값이 올바르지 않습니다"
	return ""
