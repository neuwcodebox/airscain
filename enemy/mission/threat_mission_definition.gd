class_name ThreatMissionDefinition
extends Resource

enum Type { IMPACT, RECONNAISSANCE, STRIKE_AND_EXIT }
enum TargetRole { CITY, SENSOR, COMMAND, SUPPORT, WEAPON }

@export var type := Type.IMPACT
@export var target_role := TargetRole.CITY
@export var damage: float = 10.0
@export var action_distance: float = 5.0
@export var action_duration: float = 0.0
@export_range(0.1, 1.0) var orbit_radius_ratio: float = 0.82
@export var area_recon: bool = false
@export var acquisition_range: float = 0.0
@export var released_missile: AirLaunchedMissileDefinition
@export_range(5.0, 60.0) var launch_cone_degrees: float = 25.0

func knowledge_role() -> StringName:
	match target_role:
		TargetRole.SENSOR: return &"sensor"
		TargetRole.COMMAND: return &"command"
		TargetRole.SUPPORT: return &"support"
		TargetRole.WEAPON: return &"weapon"
	return &""

func validation_error() -> String:
	if not is_finite(orbit_radius_ratio) or orbit_radius_ratio < 0.1 or orbit_radius_ratio > 1.0:
		return "체공 반경 설정이 올바르지 않습니다"
	if area_recon and type != Type.RECONNAISSANCE:
		return "구역 정찰은 정찰 임무에서만 사용할 수 있습니다"
	if not is_finite(launch_cone_degrees) or launch_cone_degrees < 5.0 or launch_cone_degrees > 60.0:
		return "투발 방향 설정이 올바르지 않습니다"
	if released_missile != null:
		if type != Type.STRIKE_AND_EXIT:
			return "투발 무장은 투발 후 이탈 임무에만 설정할 수 있습니다"
		var weapon_error := released_missile.validation_error()
		if not weapon_error.is_empty():
			return weapon_error
	if type not in Type.values() or target_role not in TargetRole.values() or not is_finite(acquisition_range) or acquisition_range < 0.0:
		return "위협 임무 역할 또는 획득 범위가 올바르지 않습니다"
	if acquisition_range > 0.0 and (type == Type.RECONNAISSANCE or target_role == TargetRole.CITY or acquisition_range <= action_distance):
		return "관측 기반 타격 임무의 획득 범위가 올바르지 않습니다"
	if damage < 0.0 or action_distance <= 0.0 or action_duration < 0.0:
		return "위협 임무 프로필이 올바르지 않습니다"
	if type == Type.IMPACT and damage <= 0.0:
		return "충돌 임무 피해량이 올바르지 않습니다"
	return ""
