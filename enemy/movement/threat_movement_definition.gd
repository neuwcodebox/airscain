class_name ThreatMovementDefinition
extends Resource

enum Mode { ALTITUDE_HOLD, TERRAIN_FOLLOWING, BALLISTIC_ARC }

@export var mode := Mode.ALTITUDE_HOLD
@export var speed: float = 30.0
@export var maximum_speed_multiplier: float = 2.0
@export var cruise_altitude: float = 70.0
@export var terminal_distance: float = 120.0
@export var maximum_turn_rate_degrees: float = 90.0
@export var maximum_climb_rate: float = 35.0
@export var terrain_lookahead: float = 80.0
@export var ballistic_apex: float = 300.0

func validation_error() -> String:
	if speed <= 0.0 or maximum_speed_multiplier < 1.0 or cruise_altitude <= 0.0 or terminal_distance <= 0.0 or maximum_turn_rate_degrees <= 0.0 or maximum_climb_rate <= 0.0 or terrain_lookahead < 0.0 or ballistic_apex <= 0.0:
		return "위협 이동 프로필이 올바르지 않습니다"
	return ""
