class_name ThreatMissionRuntime
extends RefCounted

enum Phase { INBOUND, ACTING, EGRESS }

var profile: ThreatMissionDefinition
var objective: ProtectedObjective
var target_asset: DefenseUnit
var target_defense_id: int = 0
var fixed_target: Vector3
var exit_point: Vector3
var phase := Phase.INBOUND
var action_elapsed: float = 0.0
var effect_applied: bool = false

func setup(profile_value: ThreatMissionDefinition, objective_value: ProtectedObjective, target_point: Vector3, target_asset_value: DefenseUnit, exit_point_value: Vector3) -> void:
	profile = profile_value
	objective = objective_value
	target_asset = target_asset_value
	target_defense_id = target_asset.runtime_id if target_asset != null else 0
	fixed_target = target_point
	exit_point = exit_point_value
	phase = Phase.INBOUND
	action_elapsed = 0.0
	effect_applied = false

func navigation_target() -> Vector3:
	if phase == Phase.EGRESS:
		return exit_point
	if target_asset != null and is_instance_valid(target_asset):
		return target_asset.global_position
	return fixed_target

func gameplay_tick(unit_position: Vector3, delta: float) -> bool:
	var target := navigation_target()
	var action_distance := unit_position.distance_to(target + Vector3.UP * 2.0)
	if profile.type == ThreatMissionDefinition.Type.RECONNAISSANCE:
		action_distance = Vector2(unit_position.x - target.x, unit_position.z - target.z).length()
	if action_distance > profile.action_distance:
		return false
	if phase == Phase.EGRESS:
		return true
	if phase == Phase.INBOUND:
		phase = Phase.ACTING
	if profile.type == ThreatMissionDefinition.Type.RECONNAISSANCE:
		action_elapsed += delta
		if action_elapsed < profile.action_duration:
			return false
		effect_applied = true
	else:
		_apply_effect(unit_position)
	if profile.type == ThreatMissionDefinition.Type.IMPACT:
		return true
	phase = Phase.EGRESS
	return false

func capture_state() -> Dictionary:
	return {"target_defense_id": target_defense_id, "fixed_target": SaveDocument.vector3_to_data(fixed_target), "exit_point": SaveDocument.vector3_to_data(exit_point), "phase": int(phase), "action_elapsed": action_elapsed, "effect_applied": effect_applied}

func restore_state(state: Dictionary, profile_value: ThreatMissionDefinition, objective_value: ProtectedObjective, defense_by_id: Dictionary[int, DefenseUnit]) -> void:
	profile = profile_value
	objective = objective_value
	target_defense_id = int(state.get("target_defense_id", 0))
	target_asset = defense_by_id.get(target_defense_id) as DefenseUnit
	fixed_target = SaveDocument.vector3_from_data(state.get("fixed_target", []))
	exit_point = SaveDocument.vector3_from_data(state.get("exit_point", []))
	phase = int(state.get("phase", Phase.INBOUND)) as Phase
	action_elapsed = float(state.get("action_elapsed", 0.0))
	effect_applied = bool(state.get("effect_applied", false))

func _apply_effect(unit_position: Vector3) -> void:
	if effect_applied:
		return
	effect_applied = true
	if target_asset != null and is_instance_valid(target_asset):
		target_asset.receive_damage(profile.damage)
	elif profile.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
		return
	else:
		objective.apply_surface_impact(roundi(profile.damage), unit_position)
