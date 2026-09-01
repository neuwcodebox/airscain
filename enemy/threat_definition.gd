class_name ThreatDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var neutralization_reward: int = 30

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene == null:
		return "위협 Definition의 필수 참조가 없습니다"
	if neutralization_reward < 0:
		return "무력화 보상은 음수일 수 없습니다"
	return ""
