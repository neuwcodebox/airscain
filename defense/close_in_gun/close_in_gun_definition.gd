class_name CloseInGunDefinition
extends DefenseDefinition

@export var attack_range: float = 260.0
@export var burst_interval: float = 0.28
@export var burst_damage: float = 24.0
@export var base_accuracy: float = 0.92
@export var rounds_per_burst: int = 12
@export var rounds_per_second: float = 45.0
@export var muzzle_velocity: float = 620.0
@export var shell_lifetime: float = 1.05
@export var fuze_radius: float = 3.5
@export var preferred_class: StringName = &"small_uav"
@export var preferred_target_match: float = 1.0
@export var other_target_match: float = 0.28
@export var c2_range: float = 500.0
@export var magazine_capacity: int = 120
@export var reserve_ammunition: int = 120
@export var reload_duration: float = 2.5
@export var resupply_cost: int = 2
@export var resupply_work: float = 12.0

func placement_c2_roles() -> int:
	return DefenseUnit.C2Role.DEFENSE

func engagement_reservation_kind() -> StringName:
	return EngagementCoordinator.FIRE_SUPPORT

func placement_c2_range() -> float:
	return c2_range

func tactical_overlay_mode() -> StringName:
	return &"weapon"

func tactical_range() -> float:
	return attack_range

func has_ammunition_state() -> bool:
	return true

func migrate_runtime_state(content_state: Dictionary, version: int) -> Dictionary:
	var result := super.migrate_runtime_state(content_state, version)
	if version < 18:
		result.gunfire = []
	return result

func runtime_state_validation_error(content_state: Dictionary) -> String:
	var error := WeaponMagazine.validation_error(content_state.get("magazine"))
	return error if not error.is_empty() else GunfireRuntime.validation_error(content_state.get("gunfire"))

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or burst_interval <= 0.0 or burst_damage <= 0.0 or base_accuracy <= 0.0 or base_accuracy > 1.0 or rounds_per_burst < 1 or rounds_per_burst > 32 or rounds_per_second <= 0.0 or float(rounds_per_burst) / rounds_per_second > burst_interval or muzzle_velocity <= 0.0 or shell_lifetime <= attack_range / muzzle_velocity or fuze_radius <= 0.0 or preferred_class.is_empty() or preferred_target_match <= 0.0 or other_target_match < 0.0 or c2_range <= 0.0 or magazine_capacity < 1 or reserve_ammunition < 0 or reload_duration <= 0.0 or resupply_cost < 0 or resupply_work <= 0.0:
		return "근접방어기관포 설정값이 올바르지 않습니다"
	return ""
