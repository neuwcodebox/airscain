class_name ThreatDefinition
extends Resource

enum Affiliation { UNKNOWN, FRIENDLY, NEUTRAL, HOSTILE }

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var approach_audio_event: StringName
@export var loop_audio_event: StringName
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
@export var countermeasure_evasion_distance: float = 0.0
@export var countermeasure_charges: int = 0
@export_range(0.0, 2.0) var electronic_vulnerability: float = 1.0
@export_range(0.1, 1.0) var missile_fuze_response: float = 1.0
@export var adaptive_knowledge_role: StringName
@export_range(0.0, 4.0, 0.1) var adaptive_knowledge_weight: float = 1.0
@export var requires_role_knowledge: bool = false
@export var resolution_profile: ThreatResolutionProfile
@export_range(1.0, 4.0, 0.1) var high_neutralization_weight: float = 1.0

func spawn_radius_multiplier() -> float:
	return 2.25

func has_resolution_explosion() -> bool:
	return resolution_profile == null or resolution_profile.explosion

func wreck_tint() -> Color:
	return resolution_profile.wreck_color if resolution_profile != null else Color(0.45, 0.16, 0.1)

func spawn_altitude() -> float:
	return 70.0

func estimated_approach_seconds(_distance: float, _speed_multiplier: float) -> float:
	return 0.0

func mission_definition() -> ThreatMissionDefinition:
	return null

func released_threat_definitions() -> Array[ThreatDefinition]:
	return []

func shares_city_impact_target() -> bool:
	return false

func runtime_state_validation_error(_content_state: Dictionary, _defense_ids: Dictionary[int, bool]) -> String:
	return ""

func validation_error() -> String:
	if resolution_profile != null:
		var effect_error := resolution_profile.validation_error()
		if not effect_error.is_empty():
			return effect_error
	if not is_finite(missile_fuze_response) or missile_fuze_response < 0.1 or missile_fuze_response > 1.0:
		return "미사일 신관 반응 설정이 올바르지 않습니다"
	if id.is_empty() or display_name.is_empty() or scene == null:
		return "위협 Definition의 필수 참조가 없습니다"
	if neutralization_reward < 0 or radar_signature < 0.0 or radar_signature > 1.0:
		return "위협 보상 또는 signature 설정이 올바르지 않습니다"
	if false_echo_count < 0 or false_echo_count > 4 or (false_echo_count > 0 and false_echo_radius <= 0.0):
		return "기만 반사 설정이 올바르지 않습니다"
	if jamming_range < 0.0 or jamming_strength < 0.0 or jamming_strength > 1.0 or (jamming_strength > 0.0 and jamming_range <= 0.0):
		return "재밍 설정이 올바르지 않습니다"
	if not is_finite(countermeasure_evasion_distance) or countermeasure_evasion_distance < 0.0:
		return "회피 기동 거리가 올바르지 않습니다"
	if flare_effectiveness < 0.0 or flare_effectiveness > 1.0 or chaff_effectiveness < 0.0 or chaff_effectiveness > 1.0 or countermeasure_charges < 0 or electronic_vulnerability < 0.0 or electronic_vulnerability > 2.0:
		return "대응책 설정이 올바르지 않습니다"
	if adaptive_knowledge_weight < 0.0 or high_neutralization_weight < 1.0 or requires_role_knowledge and adaptive_knowledge_role.is_empty():
		return "적응형 공격 가중치 설정이 올바르지 않습니다"
	return ""

func countermeasure_state_validation_error(state: Dictionary) -> String:
	for key: String in ["cooldown", "evasion"]:
		var value: Variant = state.get(key, 0.0)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.6:
			return "대응탄 시간 상태가 올바르지 않습니다"
	if String(state.get("kind", "")) not in ["", "flare", "chaff"]:
		return "대응탄 종류가 올바르지 않습니다"
	var origin: Variant = state.get("origin", [0, 0, 0])
	if not origin is Array or origin.size() != 3:
		return "대응탄 위치가 올바르지 않습니다"
	for value: Variant in origin:
		if not (value is float or value is int) or not is_finite(float(value)):
			return "대응탄 위치가 올바르지 않습니다"
	return ""
