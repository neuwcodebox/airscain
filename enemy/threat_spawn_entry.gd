class_name ThreatSpawnEntry
extends Resource

@export var threat_definition: ThreatDefinition
@export var unlock_level: int = 1
@export var selection_weight: float = 1.0
@export var group_size: int = 1

func validation_error() -> String:
	if threat_definition == null:
		return "위협 spawn 항목에 Definition이 없습니다"
	if unlock_level < 1 or selection_weight <= 0.0 or group_size < 1:
		return "위협 spawn 해금 단계 또는 가중치가 올바르지 않습니다"
	return threat_definition.validation_error()
