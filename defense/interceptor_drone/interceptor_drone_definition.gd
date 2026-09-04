class_name InterceptorDroneDefenseDefinition
extends DefenseDefinition

@export var attack_range: float = 280.0
@export var launch_interval: float = 1.5
@export var drone_speed: float = 95.0
@export var drone_turn_rate_degrees: float = 150.0
@export var drone_endurance: float = 14.0
@export var drone_damage: float = 58.0
@export var proximity_radius: float = 12.0
@export var drone_count: int = 3
@export var engagement_channels: int = 2
@export var recharge_duration: float = 16.0
@export var c2_range: float = 540.0

func placement_c2_roles() -> int:
	return DefenseUnit.C2Role.DEFENSE

func placement_c2_range() -> float:
	return c2_range

func tactical_overlay_mode() -> StringName:
	return &"weapon"

func tactical_range() -> float:
	return attack_range

func persistent_projectile_types() -> Array[StringName]:
	return [&"interceptor_drone"]

func runtime_state_validation_error(content_state: Dictionary) -> String:
	var available := int(content_state.get("available_drones", -1))
	var recharge: Variant = content_state.get("recharge_queue")
	if available < 0 or available > drone_count or not recharge is Array:
		return "요격드론 기지 상태가 올바르지 않습니다"
	for remaining: Variant in recharge:
		if float(remaining) <= 0.0:
			return "요격드론 재충전 상태가 올바르지 않습니다"
	return ""

func persistent_projectile_state_validation_error(projectile_type: StringName, state: Dictionary) -> String:
	if projectile_type != &"interceptor_drone":
		return super.persistent_projectile_state_validation_error(projectile_type, state)
	if int(state.get("state", -1)) < InterceptorDrone.State.OUTBOUND or int(state.get("state", -1)) > InterceptorDrone.State.RETURNING or float(state.get("age", -1.0)) < 0.0:
		return "요격드론 비행 상태가 올바르지 않습니다"
	return ""

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or launch_interval <= 0.0 or drone_speed <= 0.0 or drone_turn_rate_degrees <= 0.0 or drone_endurance <= 0.0 or drone_damage <= 0.0 or proximity_radius <= 0.0 or drone_count < 1 or engagement_channels < 1 or engagement_channels > drone_count or recharge_duration <= 0.0 or c2_range <= 0.0:
		return "요격드론 설정값이 올바르지 않습니다"
	return ""
