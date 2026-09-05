class_name RelocationManager
extends Node

signal relocation_started(unit: DefenseUnit)
signal relocation_completed(unit: DefenseUnit)

var battlefield: Battlefield
var units: Dictionary[int, DefenseUnit] = {}
var tasks: Array[Dictionary] = []

func configure(battlefield_value: Battlefield) -> void:
	battlefield = battlefield_value

func reset() -> void:
	units.clear()
	tasks.clear()

func register_asset(unit: DefenseUnit) -> void:
	units[unit.runtime_id] = unit

func request_relocation(unit: DefenseUnit, destination: Vector3) -> bool:
	if unit == null or not units.has(unit.runtime_id) or not unit.can_request_relocation():
		return false
	var result := battlefield.placement_result(destination, unit.definition.placement_profile)
	if not result.valid:
		return false
	var target := Vector3(destination.x, battlefield.terrain_height(destination.x, destination.z), destination.z)
	battlefield.register_occupancy(target, unit.definition.placement_profile.footprint_radius)
	unit.active = false
	tasks.append({"target_defense_id": unit.runtime_id, "origin": SaveDocument.vector3_to_data(unit.global_position), "destination": SaveDocument.vector3_to_data(target), "remaining": unit.definition.relocation_duration})
	relocation_started.emit(unit)
	return true

func gameplay_tick(delta: float) -> void:
	for index: int in range(tasks.size() - 1, -1, -1):
		var task := tasks[index]
		task.remaining = float(task.remaining) - delta
		tasks[index] = task
		if float(task.remaining) <= 0.0:
			tasks.remove_at(index)
			_complete_task(task)

func task_status(unit: DefenseUnit) -> String:
	for task: Dictionary in tasks:
		if int(task.target_defense_id) == unit.runtime_id:
			return "재배치 %.1f초" % float(task.remaining)
	return ""

func capture_state() -> Dictionary:
	return {"tasks": tasks.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	tasks.clear()
	for saved_task: Dictionary in state.get("tasks", []):
		var task := {"target_defense_id": int(saved_task.target_defense_id), "origin": saved_task.origin, "destination": saved_task.destination, "remaining": float(saved_task.remaining)}
		tasks.append(task)
		var target_id := int(task.target_defense_id)
		if units.has(target_id):
			units[target_id].active = false
			battlefield.register_occupancy(SaveDocument.vector3_from_data(task.destination), units[target_id].definition.placement_profile.footprint_radius)

func _complete_task(task: Dictionary) -> void:
	var target_id := int(task.target_defense_id)
	if not units.has(target_id) or not is_instance_valid(units[target_id]):
		return
	var unit := units[target_id]
	battlefield.unregister_occupancy(SaveDocument.vector3_from_data(task.origin), unit.definition.placement_profile.footprint_radius)
	unit.global_position = SaveDocument.vector3_from_data(task.destination)
	unit.active = unit.operational_ratio() >= 0.35
	relocation_completed.emit(unit)
