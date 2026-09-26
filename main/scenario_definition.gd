class_name ScenarioDefinition
extends Resource

@export var world_seed: int = 73129
@export var battlefield_size: float = 2400.0
@export var terrain_resolution: int = 97
@export var city_size: float = 330.0
@export var battlefield_layouts: Array[BattlefieldLayoutDefinition] = []
var selected_battlefield_layout_id: StringName = &""
@export var starting_budget: int = 1900
@export var objective_definition: ObjectiveDefinition
@export var available_defenses: Array[DefenseDefinition] = []
@export var threat_entries: Array[ThreatSpawnEntry] = []
@export var raid_archetypes: Array[RaidArchetypeDefinition] = []
## Sustained-operation phases in ascending threat level; each groups the unlocks up to the next phase.
@export var operation_briefings: Array[OperationBriefingDefinition] = []
## Threats are announced by intel at their unlock level and first fly this many levels later,
## giving players time to deploy the counter assets unlocked alongside the briefing.
@export var threat_intel_lead_levels: int = 0
@export var ambient_contacts: Array[ThreatDefinition] = []
@export var ambient_contacts_per_type: int = 4
@export var initial_spawn_interval: float = 12.0
@export_range(0.0, 1.0) var asset_suppression_chance: float = 0.35
@export var recon_followup_window: float = 90.0
@export_range(0.0, 1.0) var recon_followup_suppression_chance: float = 0.75
@export var opening_raid_interval: float = 30.0
@export var initial_raid_interval: float = 24.0
@export var minimum_raid_interval: float = 14.0
@export var raid_interval_pressure_reduction: float = 0.6
@export var pressure_step_duration: float = 90.0
@export var threat_budget_growth_per_level: float = 1.0
@export var speed_growth_duration: float = 1200.0
@export var maximum_speed_multiplier: float = 1.6
@export var active_threat_cap: int = 200
@export var support_interval: float = 90.0
@export var support_amount: int = 180
@export var support_amount_per_additional_district: int = 0
@export var attack_window_duration: float = 75.0
@export var recovery_duration: float = 45.0
@export var attack_window_reward: int = 120

func validation_error() -> String:
	if not is_finite(asset_suppression_chance) or asset_suppression_chance < 0.0 or asset_suppression_chance > 1.0:
		return "자산 제압 편성 확률이 올바르지 않습니다"
	if not is_finite(recon_followup_window) or recon_followup_window <= 0.0 or not is_finite(recon_followup_suppression_chance) or recon_followup_suppression_chance < 0.0 or recon_followup_suppression_chance > 1.0:
		return "정찰 후속 제압 설정이 올바르지 않습니다"
	if battlefield_size <= 0.0 or terrain_resolution < 2 or city_size <= 0.0 or city_size >= battlefield_size:
		return "전장 생성 설정이 올바르지 않습니다"
	if battlefield_layouts.is_empty():
		return "전장 레이아웃이 없습니다"
	var layout_ids: Dictionary[StringName, bool] = {}
	for layout: BattlefieldLayoutDefinition in battlefield_layouts:
		if layout == null or layout_ids.has(layout.id):
			return "전장 레이아웃이 없거나 ID가 중복됩니다"
		var layout_error := layout.validation_error()
		if not layout_error.is_empty():
			return layout_error
		layout_ids[layout.id] = true
	if not selected_battlefield_layout_id.is_empty() and not layout_ids.has(selected_battlefield_layout_id):
		return "선택한 전장 레이아웃을 찾을 수 없습니다"
	if threat_intel_lead_levels < 0:
		return "위협 첩보 선행 단계가 올바르지 않습니다"
	if starting_budget < 0 or initial_spawn_interval <= 0.0 or opening_raid_interval <= 0.0 or initial_raid_interval < minimum_raid_interval or minimum_raid_interval <= 0.0 or raid_interval_pressure_reduction < 0.0 or pressure_step_duration <= 0.0 or threat_budget_growth_per_level <= 0.0 or speed_growth_duration <= 0.0 or maximum_speed_multiplier < 1.0 or active_threat_cap < 1 or ambient_contacts_per_type < 0 or support_interval <= 0.0 or support_amount < 0 or support_amount_per_additional_district < 0 or attack_window_duration <= 0.0 or recovery_duration <= 0.0 or attack_window_reward < 0:
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
	var briefing_error := _briefing_validation_error()
	if not briefing_error.is_empty():
		return briefing_error
	for contact: ThreatDefinition in ambient_contacts:
		if contact == null:
			return "환경 접촉 Definition이 비어 있습니다"
		var contact_error := contact.validation_error()
		if not contact_error.is_empty():
			return contact_error
	return ""

func battlefield_layout() -> BattlefieldLayoutDefinition:
	if not selected_battlefield_layout_id.is_empty():
		for layout: BattlefieldLayoutDefinition in battlefield_layouts:
			if layout.id == selected_battlefield_layout_id:
				return layout
	return battlefield_layouts[posmod(world_seed, battlefield_layouts.size())]

func battlefield_layout_by_id(layout_id: StringName) -> BattlefieldLayoutDefinition:
	for layout: BattlefieldLayoutDefinition in battlefield_layouts:
		if layout.id == layout_id:
			return layout
	return null

func regular_support_amount(layout: BattlefieldLayoutDefinition) -> int:
	return support_amount + maxi(0, layout.city_districts.size() - 1) * support_amount_per_additional_district

## Level at which an announced threat may join automatic raids.
## The operation opens with a raid, so opening-level threats fly immediately.
func threat_flight_level(entry: ThreatSpawnEntry) -> int:
	return entry.unlock_level if entry.unlock_level <= 1 else entry.unlock_level + threat_intel_lead_levels

func is_threat_available(entry: ThreatSpawnEntry, level: int) -> bool:
	return threat_flight_level(entry) <= level

func _briefing_validation_error() -> String:
	var ids: Dictionary[StringName, bool] = {}
	var previous_level := 0
	for briefing: OperationBriefingDefinition in operation_briefings:
		if briefing == null or ids.has(briefing.id):
			return "작전 브리핑이 없거나 ID가 중복됩니다"
		var error := briefing.validation_error()
		if not error.is_empty():
			return error
		if briefing.unlock_level <= previous_level or previous_level == 0 and briefing.unlock_level != 1:
			return "작전 브리핑은 1단계부터 해금 단계 오름차순이어야 합니다"
		ids[briefing.id] = true
		previous_level = briefing.unlock_level
	if not operation_briefings.is_empty():
		for entry: ThreatSpawnEntry in threat_entries:
			if entry.threat_definition.briefing_note.is_empty():
				return "브리핑에 소개할 위협 설명이 없습니다: %s" % entry.threat_definition.id
	return ""

## Last threat level covered by a briefing phase, or -1 when the phase is open-ended.
func briefing_last_level(briefing: OperationBriefingDefinition) -> int:
	var index := operation_briefings.find(briefing)
	if index < 0 or index + 1 >= operation_briefings.size():
		return -1
	return operation_briefings[index + 1].unlock_level - 1

## Threats first unlocked within the phase, in scenario order and without duplicate definitions.
func briefing_threats(briefing: OperationBriefingDefinition) -> Array[ThreatDefinition]:
	var result: Array[ThreatDefinition] = []
	var last_level := briefing_last_level(briefing)
	for entry: ThreatSpawnEntry in threat_entries:
		if entry.unlock_level >= briefing.unlock_level and (last_level < 0 or entry.unlock_level <= last_level) and not result.has(entry.threat_definition):
			result.append(entry.threat_definition)
	return result

## Defenses first unlocked within the phase, in catalog order.
func briefing_defenses(briefing: OperationBriefingDefinition) -> Array[DefenseDefinition]:
	var result: Array[DefenseDefinition] = []
	var last_level := briefing_last_level(briefing)
	for definition: DefenseDefinition in available_defenses:
		if definition.unlock_pressure_level >= briefing.unlock_level and (last_level < 0 or definition.unlock_pressure_level <= last_level):
			result.append(definition)
	return result
