class_name AirLaunchedMissileDefinition
extends ThreatDefinition

@export var maximum_health: float = 24.0
@export var flight_speed: float = 200.0
@export var flight_acceleration: float = 40.0

func runtime_state_validation_error(state: Dictionary, defense_ids: Dictionary[int, bool]) -> String:
	var target_id := int(state.get("target_defense_id", 0))
	if target_id != 0 and not defense_ids.has(target_id):
		return "공대지 미사일의 표적 참조가 올바르지 않습니다"
	if int(state.get("flight_mode", -1)) != StrikeFlight.Mode.MISSILE:
		return "공대지 미사일의 비행 방식이 올바르지 않습니다"
	return AirStrikeMunition.state_validation_error(state)

func validation_error() -> String:
	if not is_finite(maximum_health) or maximum_health <= 0.0 or not is_finite(flight_speed) or flight_speed <= 0.0 or not is_finite(flight_acceleration) or flight_acceleration <= 0.0:
		return "공대지 미사일 성능이 올바르지 않습니다"
	return super.validation_error()
