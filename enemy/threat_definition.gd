class_name ThreatDefinition
extends Resource

enum Affiliation { UNKNOWN, FRIENDLY, NEUTRAL, HOSTILE }

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var neutralization_reward: int = 30
@export var signature_class: StringName = &"air_contact"
@export_range(0.0, 1.0) var radar_signature: float = 0.7
@export var affiliation := Affiliation.HOSTILE

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene == null:
		return "위협 Definition의 필수 참조가 없습니다"
	if neutralization_reward < 0 or radar_signature < 0.0 or radar_signature > 1.0:
		return "위협 보상 또는 signature 설정이 올바르지 않습니다"
	return ""
