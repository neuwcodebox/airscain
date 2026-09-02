class_name ProtectedObjective
extends Node3D

signal integrity_changed(current: int, maximum: int)
signal depleted(objective: ProtectedObjective)

const DAMAGE_SMOKE_SCENE := preload("res://effects/damage_smoke/damage_smoke.tscn")
const DAMAGE_SMOKE_OFFSETS: Array[Vector3] = [
	Vector3(-54.0, 18.0, -38.0),
	Vector3(48.0, 18.0, 32.0),
	Vector3(-20.0, 18.0, 58.0),
	Vector3(62.0, 18.0, -46.0),
]

var runtime_id: int
var definition: ObjectiveDefinition
var current_integrity: int
var exclusion_radius: float = 165.0
var damage_smoke_effects: Array[Node3D] = []

func setup(id_value: int, definition_value: ObjectiveDefinition) -> void:
	runtime_id = id_value
	definition = definition_value
	current_integrity = definition.maximum_integrity
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)

func apply_mission_damage(amount: int) -> bool:
	if current_integrity <= 0 or amount <= 0:
		return false
	current_integrity = maxi(0, current_integrity - amount)
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)
	if current_integrity == 0:
		depleted.emit(self)
	return true

func get_target_point(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var radius := sqrt(rng.randf()) * exclusion_radius * 0.72
	return global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

func excludes_placement(world_position: Vector3, radius: float) -> bool:
	var flat_delta := Vector2(world_position.x - global_position.x, world_position.z - global_position.z)
	return flat_delta.length() < exclusion_radius + radius

func restore_integrity(value: int) -> void:
	current_integrity = clampi(value, 0, definition.maximum_integrity)
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)

func _sync_damage_visuals() -> void:
	for index: int in range(damage_smoke_effects.size() - 1, -1, -1):
		if not is_instance_valid(damage_smoke_effects[index]):
			damage_smoke_effects.remove_at(index)
	var damage_ratio := 1.0 - float(current_integrity) / maxf(1.0, float(definition.maximum_integrity))
	var desired_count := mini(DAMAGE_SMOKE_OFFSETS.size(), ceili(damage_ratio * float(DAMAGE_SMOKE_OFFSETS.size())))
	while damage_smoke_effects.size() < desired_count:
		var index := damage_smoke_effects.size()
		var effect := DAMAGE_SMOKE_SCENE.instantiate() as Node3D
		add_child(effect)
		effect.position = DAMAGE_SMOKE_OFFSETS[index]
		effect.call("set_city_scale", 3.5)
		damage_smoke_effects.append(effect)
	while damage_smoke_effects.size() > desired_count:
		var effect: Node3D = damage_smoke_effects.pop_back()
		effect.queue_free()
