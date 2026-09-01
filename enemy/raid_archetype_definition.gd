class_name RaidArchetypeDefinition
extends Resource

@export var id: StringName
@export var unlock_level: int = 1
@export var selection_weight: float = 1.0
@export var phase_entries: Array[ThreatSpawnEntry] = []
@export var phase_delays: Array[float] = []

func validation_error() -> String:
	if id.is_empty() or unlock_level < 1 or selection_weight <= 0.0 or phase_entries.is_empty() or phase_entries.size() != phase_delays.size():
		return "공격 archetype 구성이 올바르지 않습니다"
	var previous_delay := -1.0
	for index: int in phase_entries.size():
		if phase_entries[index] == null or phase_delays[index] < 0.0 or phase_delays[index] < previous_delay:
			return "공격 archetype 단계 또는 지연시간이 올바르지 않습니다"
		previous_delay = phase_delays[index]
	return ""
