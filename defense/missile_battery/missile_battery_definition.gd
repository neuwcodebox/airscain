class_name MissileBatteryDefinition
extends DefenseDefinition

@export var attack_range: float = 300.0
@export var fire_interval: float = 2.2
@export var engagement_channels: int = 2
@export var maximum_interceptors_per_track: int = 2
@export var c2_range: float = 600.0
@export var minimum_engagement_altitude: float = 0.0
@export var maximum_engagement_altitude: float = 450.0
@export var munitions: Array[MissileMunitionDefinition] = []

func placement_c2_roles() -> int:
	return DefenseUnit.C2Role.DEFENSE

func placement_c2_range() -> float:
	return c2_range

func catalog_group() -> StringName:
	return &"missile"

func tactical_overlay_mode() -> StringName:
	return &"weapon"

func tactical_range() -> float:
	return attack_range

func has_ammunition_state() -> bool:
	return true

func persistent_projectile_types() -> Array[StringName]:
	return [&"homing_interceptor"]

func runtime_state_validation_error(content_state: Dictionary) -> String:
	var magazine_states: Variant = content_state.get("munition_magazines")
	var munition_mode := StringName(String(content_state.get("munition_mode", "")))
	if not magazine_states is Dictionary or munition_mode != &"auto" and not _munition_definition_map().has(munition_mode):
		return "탄종 선택 또는 재고 상태가 올바르지 않습니다"
	for munition: MissileMunitionDefinition in munitions:
		var magazine_error := WeaponMagazine.validation_error(magazine_states.get(String(munition.id)))
		if not magazine_error.is_empty():
			return "%s: %s" % [munition.id, magazine_error]
	return ""

func persistent_projectile_state_validation_error(projectile_type: StringName, state: Dictionary) -> String:
	if projectile_type != &"homing_interceptor":
		return super.persistent_projectile_state_validation_error(projectile_type, state)
	var maximum_lifetime := float(state.get("maximum_lifetime", 0.0))
	var age := float(state.get("age", -1.0))
	if float(state.get("speed", 0.0)) <= 0.0 or float(state.get("turn_rate", 0.0)) <= 0.0 or maximum_lifetime <= 0.0 or float(state.get("damage", 0.0)) <= 0.0 or float(state.get("proximity_radius", 0.0)) <= 0.0 or age < 0.0 or age >= maximum_lifetime:
		return "요격체 비행 상태가 올바르지 않습니다"
	return ""

func _munition_definition_map() -> Dictionary[StringName, MissileMunitionDefinition]:
	var result: Dictionary[StringName, MissileMunitionDefinition] = {}
	for munition: MissileMunitionDefinition in munitions:
		result[munition.id] = munition
	return result

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or fire_interval <= 0.0 or engagement_channels < 1 or maximum_interceptors_per_track < 1 or maximum_interceptors_per_track > engagement_channels or c2_range <= 0.0 or minimum_engagement_altitude < 0.0 or maximum_engagement_altitude <= minimum_engagement_altitude or munitions.is_empty():
		return "미사일 포대 설정값은 0보다 커야 합니다"
	var ids: Dictionary[StringName, bool] = {}
	for munition: MissileMunitionDefinition in munitions:
		if munition == null or ids.has(munition.id):
			return "미사일 탄종이 없거나 ID가 중복됩니다"
		var munition_error := munition.validation_error()
		if not munition_error.is_empty():
			return munition_error
		ids[munition.id] = true
	return ""
