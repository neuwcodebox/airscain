class_name SearchRadarDefinition
extends DefenseDefinition

@export var detection_range: float = 700.0
@export var scan_interval: float = 0.4
@export var sensor_quality: float = 0.9
@export var range_exponent: float = 4.0
@export var tracking_capacity: int = 12
@export var c2_range: float = 700.0
@export var minimum_detection_altitude: float = 0.0
@export var maximum_detection_altitude: float = 260.0
@export var range_overlay_color := Color(0.18, 0.95, 0.42, 0.72)
@export var terrain_coverage_tint := Color(0.18, 0.82, 1.0, 0.18)

func placement_c2_roles() -> int:
	return DefenseUnit.C2Role.SENSOR

func placement_c2_range() -> float:
	return c2_range

func catalog_group() -> StringName:
	return &"sensor"

func tactical_overlay_mode() -> StringName:
	return &"sensor"

func tactical_range() -> float:
	return detection_range

func tactical_overlay_color() -> Color:
	return range_overlay_color

func terrain_coverage_color() -> Color:
	return terrain_coverage_tint

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if detection_range <= 0.0 or scan_interval <= 0.0:
		return "레이더 거리와 탐지 주기는 0보다 커야 합니다"
	if sensor_quality <= 0.0 or sensor_quality > 1.0 or range_exponent <= 0.0 or tracking_capacity < 1 or c2_range <= 0.0 or minimum_detection_altitude < 0.0 or maximum_detection_altitude <= minimum_detection_altitude:
		return "레이더 품질 설정이 올바르지 않습니다"
	return ""

func runtime_state_validation_error(content_state: Dictionary) -> String:
	var cooldown: Variant = content_state.get("scan_cooldown", 0.0)
	var index: Variant = content_state.get("scan_index", 0)
	if not (cooldown is float or cooldown is int) or not is_finite(float(cooldown)) or float(cooldown) < 0.0:
		return "레이더 주사 상태가 올바르지 않습니다"
	if not (index is float or index is int) or not is_finite(float(index)) or float(index) != floorf(float(index)) or int(index) < 0:
		return "레이더 주사 상태가 올바르지 않습니다"
	var assignments: Variant = content_state.get("tracked_contacts", [])
	if not assignments is Array or assignments.size() > tracking_capacity:
		return "레이더 추적 배정 상태가 올바르지 않습니다"
	var keys: Dictionary[String, bool] = {}
	for value: Variant in assignments:
		if not value is Dictionary:
			return "레이더 추적 배정 상태가 올바르지 않습니다"
		var assignment := value as Dictionary
		var key := String(assignment.get("key", ""))
		var track_id: Variant = assignment.get("track_id", 0)
		if key.is_empty() or not (track_id is float or track_id is int) or not is_finite(float(track_id)) or float(track_id) != floorf(float(track_id)) or int(track_id) <= 0 or keys.has(key):
			return "레이더 추적 배정 상태가 올바르지 않습니다"
		keys[key] = true
	return ""
