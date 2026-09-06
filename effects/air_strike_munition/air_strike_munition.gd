extends Node3D

const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")

@export var speed: float = 420.0

var target_position: Vector3
var objective: ProtectedObjective
var damage: int
var target_asset: DefenseUnit
var target_defense_id: int = 0
var targets_city: bool = true
var impacted: bool = false

static func state_validation_error(state: Dictionary) -> String:
	for field: String in ["position", "target_position"]:
		var value: Variant = state.get(field)
		if not value is Array or value.size() != 3:
			return "공대지 탄 비행 위치가 올바르지 않습니다"
	if not is_finite(float(state.get("speed", 0.0))) or float(state.get("speed", 0.0)) <= 0.0 or int(state.get("damage", 0)) <= 0:
		return "공대지 탄 비행 상태가 올바르지 않습니다"
	if not state.get("targets_city", true) is bool or bool(state.get("targets_city", true)) and int(state.get("target_defense_id", 0)) != 0:
		return "공대지 탄의 타격 종류가 올바르지 않습니다"
	return ""

func setup(target: Vector3, objective_value: ProtectedObjective, damage_value: int, asset: DefenseUnit = null, city: bool = true) -> void:
	target_position = target
	objective = objective_value
	damage = maxi(1, damage_value)
	target_asset = asset
	target_defense_id = asset.runtime_id if is_instance_valid(asset) else 0
	targets_city = city
	if global_position.distance_squared_to(target_position) > 0.001:
		_orient_to_target()

func capture_state() -> Dictionary:
	return {
		"type": "air_strike_munition",
		"position": SaveDocument.vector3_to_data(global_position),
		"target_position": SaveDocument.vector3_to_data(target_position),
		"speed": speed,
		"damage": damage,
		"target_defense_id": target_defense_id,
		"targets_city": targets_city,
	}

func restore_state(state: Dictionary, objective_value: ProtectedObjective, defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	global_position = SaveDocument.vector3_from_data(state.position)
	speed = float(state.speed)
	setup(SaveDocument.vector3_from_data(state.target_position), objective_value, int(state.damage), defense_by_id.get(int(state.get("target_defense_id", 0))), bool(state.get("targets_city", true)))

func _process(delta: float) -> void:
	if impacted:
		return
	var previous := global_position
	var distance := global_position.distance_to(target_position)
	var travel := speed * delta
	if distance <= travel:
		global_position = target_position
		_sample_trail(previous, global_position)
		_impact()
		return
	global_position += global_position.direction_to(target_position) * travel
	_orient_to_target()
	_sample_trail(previous, global_position)

func _orient_to_target() -> void:
	var direction := global_position.direction_to(target_position)
	var up_direction := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	look_at(target_position, up_direction)

func _sample_trail(from_position: Vector3, to_position: Vector3) -> void:
	var smoke := $SmokeTrail as LingeringSmokeTrail
	smoke.sample_world_segment(from_position, to_position)

func _impact() -> void:
	if impacted:
		return
	impacted = true
	if not targets_city:
		if is_instance_valid(target_asset) and target_asset.active and target_asset.global_position.distance_to(target_position) <= maxf(8.0, target_asset.definition.placement_profile.footprint_radius):
			target_asset.receive_damage(damage)
	elif objective != null and is_instance_valid(objective):
		objective.apply_surface_impact(damage, target_position)
	var parent := get_parent()
	if parent != null:
		var smoke := $SmokeTrail as LingeringSmokeTrail
		smoke.release_to(parent)
		ExplosionEffect.spawn(parent as Node3D, target_position, Color("ffb02e"), 8.0)
	queue_free()
