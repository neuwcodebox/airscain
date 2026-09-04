class_name AttackUavDefinition
extends ThreatDefinition

@export var maximum_health: float = 100.0
@export var movement: ThreatMovementDefinition
@export var mission: ThreatMissionDefinition
@export var visual_color: Color = Color(0.72, 0.18, 0.12, 1.0)

func runtime_state_validation_error(content_state: Dictionary, defense_ids: Dictionary[int, bool]) -> String:
	var movement_state: Dictionary = content_state.get("movement", {})
	var mission_state: Dictionary = content_state.get("mission", {})
	var mission_target_id := int(mission_state.get("target_defense_id", 0))
	var mission_phase := int(mission_state.get("phase", -1))
	if not _valid_vector_data(content_state.get("target_point")) or not _valid_vector_data(movement_state.get("velocity")) or not _valid_vector_data(mission_state.get("fixed_target")) or not _valid_vector_data(mission_state.get("exit_point")) or float(content_state.get("speed_multiplier", 0.0)) <= 0.0:
		return "위협 이동 또는 임무 상태가 올바르지 않습니다"
	if movement.mode == ThreatMovementDefinition.Mode.BALLISTIC_ARC:
		var ballistic_progress := float(movement_state.get("ballistic_progress", -1.0))
		if not _valid_vector_data(movement_state.get("ballistic_origin")) or not _valid_vector_data(movement_state.get("ballistic_target")) or ballistic_progress < 0.0 or ballistic_progress > 1.0 or float(movement_state.get("ballistic_duration", 0.0)) <= 0.0 or not movement_state.get("ballistic_initialized", null) is bool:
			return "탄도 위협 비행 상태가 올바르지 않습니다"
	if mission_target_id != 0 and not defense_ids.has(mission_target_id) or mission_phase < ThreatMissionRuntime.Phase.INBOUND or mission_phase > ThreatMissionRuntime.Phase.EGRESS or float(mission_state.get("action_elapsed", -1.0)) < 0.0:
		return "위협 임무 대상 또는 진행 상태가 올바르지 않습니다"
	return ""

func _valid_vector_data(value: Variant) -> bool:
	return value is Array and value.size() == 3

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if maximum_health <= 0.0 or movement == null or mission == null:
		return "공격 UAV 구성 참조가 올바르지 않습니다"
	var movement_error := movement.validation_error()
	if not movement_error.is_empty():
		return movement_error
	var mission_error := mission.validation_error()
	if not mission_error.is_empty():
		return mission_error
	return ""
