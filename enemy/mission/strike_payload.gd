class_name StrikePayload
extends RefCounted
## Resolved impact policy shared by interceptable missiles and untracked bombs.

var objective: ProtectedObjective
var target_asset: DefenseUnit
var target_defense_id: int = 0
var targets_city: bool = true
var damage: int = 1
var applied: bool = false

func setup(objective_value: ProtectedObjective, damage_value: int, asset: DefenseUnit, city: bool) -> void:
	objective = objective_value
	damage = maxi(1, damage_value)
	target_asset = asset
	target_defense_id = asset.runtime_id if is_instance_valid(asset) else 0
	targets_city = city
	applied = false

func apply_impact(position: Vector3) -> void:
	if applied:
		return
	applied = true
	if not targets_city:
		if is_instance_valid(target_asset) and target_asset.active and target_asset.global_position.distance_to(position) <= maxf(8.0, target_asset.definition.placement_profile.footprint_radius):
			target_asset.receive_damage(damage)
	elif is_instance_valid(objective):
		objective.apply_surface_impact(damage, position)

func capture_state() -> Dictionary:
	return {"damage": damage, "target_defense_id": target_defense_id, "targets_city": targets_city}

func restore_state(state: Dictionary, objective_value: ProtectedObjective, defenses: Dictionary[int, DefenseUnit]) -> void:
	setup(objective_value, int(state.damage), defenses.get(int(state.get("target_defense_id", 0))), bool(state.get("targets_city", true)))

static func state_validation_error(state: Dictionary) -> String:
	if int(state.get("damage", 0)) <= 0:
		return "공대지 탄 피해량이 올바르지 않습니다"
	if not state.get("targets_city", true) is bool or bool(state.get("targets_city", true)) and int(state.get("target_defense_id", 0)) != 0:
		return "공대지 탄의 타격 종류가 올바르지 않습니다"
	return ""
