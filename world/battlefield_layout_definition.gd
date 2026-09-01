class_name BattlefieldLayoutDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var terrain_height_scale: float = 42.0
@export var noise_frequency: float = 0.0035
@export var coast_start: float = 0.72
@export var coast_end: float = 0.98
@export var city_blocks: int = 7
@export var minimum_building_height: float = 8.0
@export var maximum_building_height: float = 70.0
@export var rooftop_spacing: int = 6
@export var starting_budget_bonus: int = 0

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or terrain_height_scale <= 0.0 or noise_frequency <= 0.0 or coast_start <= 0.0 or coast_end <= coast_start or coast_end > 1.0 or city_blocks < 3 or minimum_building_height <= 0.0 or maximum_building_height < minimum_building_height or rooftop_spacing < 1 or starting_budget_bonus < 0:
		return "전장 레이아웃 설정값이 올바르지 않습니다"
	return ""
