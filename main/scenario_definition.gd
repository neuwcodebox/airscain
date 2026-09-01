class_name ScenarioDefinition
extends Resource

@export var world_seed: int = 73129
@export var battlefield_size: float = 2400.0
@export var terrain_resolution: int = 97
@export var city_size: float = 330.0
@export var starting_budget: int = 620
@export var objective_definition: ObjectiveDefinition
@export var available_defenses: Array[DefenseDefinition] = []
@export var threat_entries: Array[ThreatSpawnEntry] = []
@export var raid_archetypes: Array[RaidArchetypeDefinition] = []
@export var ambient_contacts: Array[ThreatDefinition] = []
@export var ambient_contacts_per_type: int = 4
@export var initial_spawn_interval: float = 4.0
@export var active_threat_cap: int = 200

func validation_error() -> String:
	if battlefield_size <= 0.0 or terrain_resolution < 2 or city_size <= 0.0 or city_size >= battlefield_size:
		return "전장 생성 설정이 올바르지 않습니다"
	if starting_budget < 0 or initial_spawn_interval <= 0.0 or active_threat_cap < 1 or ambient_contacts_per_type < 0:
		return "게임 진행 설정이 올바르지 않습니다"
	if objective_definition == null:
		return "보호 목표 Definition이 없습니다"
	var objective_error := objective_definition.validation_error()
	if not objective_error.is_empty():
		return objective_error
	if available_defenses.is_empty():
		return "구매 가능한 방어 수단이 없습니다"
	for defense: DefenseDefinition in available_defenses:
		if defense == null:
			return "방어 수단 Definition이 비어 있습니다"
		var defense_error := defense.validation_error()
		if not defense_error.is_empty():
			return defense_error
	if threat_entries.is_empty():
		return "위협 spawn 항목이 없습니다"
	for entry: ThreatSpawnEntry in threat_entries:
		if entry == null:
			return "위협 spawn 항목이 비어 있습니다"
		var entry_error := entry.validation_error()
		if not entry_error.is_empty():
			return entry_error
	for archetype: RaidArchetypeDefinition in raid_archetypes:
		if archetype == null:
			return "공격 archetype이 비어 있습니다"
		var archetype_error := archetype.validation_error()
		if not archetype_error.is_empty():
			return archetype_error
		for phase_entry: ThreatSpawnEntry in archetype.phase_entries:
			if not threat_entries.has(phase_entry):
				return "공격 archetype 단계가 시나리오 위협 목록에 없습니다"
	for contact: ThreatDefinition in ambient_contacts:
		if contact == null:
			return "환경 접촉 Definition이 비어 있습니다"
		var contact_error := contact.validation_error()
		if not contact_error.is_empty():
			return contact_error
	return ""
