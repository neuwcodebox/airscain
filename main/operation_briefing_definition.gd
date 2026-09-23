class_name OperationBriefingDefinition
extends Resource
## One sustained-operation phase announced by an intelligence briefing.
## The threats and assets it introduces come from the scenario unlock data.

@export var id: StringName
@export var unlock_level: int = 1
@export var title: String
@export_multiline var intel: String
@export_multiline var recommendation: String

func validation_error() -> String:
	if id.is_empty() or title.is_empty() or intel.is_empty() or recommendation.is_empty():
		return "작전 브리핑 Definition의 필수 문구가 없습니다"
	if unlock_level < 1:
		return "작전 브리핑 해금 단계가 올바르지 않습니다"
	return ""
