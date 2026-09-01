class_name ProtectedObjective
extends Node3D

signal integrity_changed(current: int, maximum: int)
signal depleted(objective: ProtectedObjective)

var runtime_id: int
var definition: ObjectiveDefinition
var current_integrity: int
var exclusion_radius: float = 165.0

func setup(id_value: int, definition_value: ObjectiveDefinition) -> void:
	runtime_id = id_value
	definition = definition_value
	current_integrity = definition.maximum_integrity
	integrity_changed.emit(current_integrity, definition.maximum_integrity)

func apply_mission_damage(amount: int) -> bool:
	if current_integrity <= 0 or amount <= 0:
		return false
	current_integrity = maxi(0, current_integrity - amount)
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

