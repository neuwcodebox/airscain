class_name OperationBriefingController
extends Node
## Sustained-operation phase briefings: announces each phase once when its threat level is reached.

signal briefing_delivered(briefing: OperationBriefingDefinition)

var scenario: ScenarioDefinition
var enabled: bool = false
var delivered_ids: Array[StringName] = []

func configure(scenario_value: ScenarioDefinition, enabled_value: bool) -> void:
	scenario = scenario_value
	enabled = enabled_value
	delivered_ids.clear()

## Delivers every undelivered phase at or below the reached threat level, in phase order.
func pressure_reached(level: int) -> void:
	if not enabled or scenario == null:
		return
	for briefing: OperationBriefingDefinition in scenario.operation_briefings:
		if briefing.unlock_level <= level and not delivered_ids.has(briefing.id):
			delivered_ids.append(briefing.id)
			briefing_delivered.emit(briefing)

func delivered_briefings() -> Array[OperationBriefingDefinition]:
	var result: Array[OperationBriefingDefinition] = []
	if scenario == null:
		return result
	for briefing: OperationBriefingDefinition in scenario.operation_briefings:
		if delivered_ids.has(briefing.id):
			result.append(briefing)
	return result

func capture_state() -> Dictionary:
	var ids: Array[String] = []
	for briefing: OperationBriefingDefinition in delivered_briefings():
		ids.append(String(briefing.id))
	return {"delivered": ids}

func restore_state(state: Dictionary) -> void:
	delivered_ids.clear()
	for value: Variant in state.get("delivered", []):
		var briefing_id := StringName(String(value))
		if not delivered_ids.has(briefing_id):
			delivered_ids.append(briefing_id)

static func validation_error(state: Variant, scenario_value: ScenarioDefinition) -> String:
	if not state is Dictionary or not (state as Dictionary).get("delivered") is Array:
		return "작전 브리핑 상태가 올바르지 않습니다"
	var valid_ids: Dictionary[StringName, bool] = {}
	for briefing: OperationBriefingDefinition in scenario_value.operation_briefings:
		valid_ids[briefing.id] = true
	var seen: Dictionary[StringName, bool] = {}
	for value: Variant in state.delivered:
		var briefing_id := StringName(String(value))
		if not value is String or not valid_ids.has(briefing_id) or seen.has(briefing_id):
			return "작전 브리핑 상태가 올바르지 않습니다"
		seen[briefing_id] = true
	return ""

## Legacy operations saved before briefings existed treat every phase they already reached as delivered.
static func legacy_state(scenario_value: ScenarioDefinition, reached_level: int) -> Dictionary:
	var ids: Array = []
	for briefing: OperationBriefingDefinition in scenario_value.operation_briefings:
		if briefing.unlock_level <= reached_level:
			ids.append(String(briefing.id))
	return {"delivered": ids}
