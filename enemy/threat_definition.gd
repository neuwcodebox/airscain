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
@export_range(0, 4) var false_echo_count: int = 0
@export var false_echo_radius: float = 0.0
@export var jamming_range: float = 0.0
@export_range(0.0, 1.0) var jamming_strength: float = 0.0
@export_range(0.0, 1.0) var flare_effectiveness: float = 0.0
@export_range(0.0, 1.0) var chaff_effectiveness: float = 0.0
@export var countermeasure_charges: int = 0

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene == null:
		return "위협 Definition의 필수 참조가 없습니다"
	if neutralization_reward < 0 or radar_signature < 0.0 or radar_signature > 1.0:
		return "위협 보상 또는 signature 설정이 올바르지 않습니다"
	if false_echo_count < 0 or false_echo_count > 4 or (false_echo_count > 0 and false_echo_radius <= 0.0):
		return "기만 반사 설정이 올바르지 않습니다"
	if jamming_range < 0.0 or jamming_strength < 0.0 or jamming_strength > 1.0 or (jamming_strength > 0.0 and jamming_range <= 0.0):
		return "재밍 설정이 올바르지 않습니다"
	if flare_effectiveness < 0.0 or flare_effectiveness > 1.0 or chaff_effectiveness < 0.0 or chaff_effectiveness > 1.0 or countermeasure_charges < 0:
		return "대응책 설정이 올바르지 않습니다"
	return ""
