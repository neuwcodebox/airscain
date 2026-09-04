class_name SupportManager
extends Node

signal task_completed(kind: StringName, unit: DefenseUnit)

var facilities: Array[DefenseUnit] = []
const RESUPPLY := "resupply"
const REPAIR := "repair"

var consumers: Dictionary[int, DefenseUnit] = {}
var tasks: Array[Dictionary] = []
var session: GameSession

func configure(session_value: GameSession) -> void:
	session = session_value

func reset() -> void:
	facilities.clear()
	consumers.clear()
	tasks.clear()

func register_asset(unit: DefenseUnit) -> void:
	consumers[unit.runtime_id] = unit
	if unit.service_range() > 0.0 and unit.support_slots() > 0:
		facilities.append(unit)

func request_resupply(unit: DefenseUnit) -> bool:
	if unit == null or not unit.uses_ammunition() or unit.relocation_manager != null and not unit.relocation_manager.task_status(unit).is_empty() or not consumers.has(unit.runtime_id) or not unit.ammunition_needs_resupply() or task_status(unit) != "" or service_facility_for(unit) == null:
		return false
	return _request_task(unit, RESUPPLY, unit.resupply_cost(), unit.resupply_work())

func request_repair(unit: DefenseUnit) -> bool:
	if unit == null or unit.relocation_manager != null and not unit.relocation_manager.task_status(unit).is_empty() or not consumers.has(unit.runtime_id) or unit.integrity <= 0.0 or unit.integrity >= unit.definition.maximum_integrity or task_status(unit) != "" or service_facility_for(unit) == null:
		return false
	return _request_task(unit, REPAIR, unit.repair_cost(), unit.repair_work())

func _request_task(unit: DefenseUnit, kind: String, cost: int, work: float) -> bool:
	if session == null or not session.try_spend(cost):
		return false
	tasks.append({"kind": kind, "target_defense_id": unit.runtime_id, "remaining_work": work})
	return true

func gameplay_tick(delta: float) -> void:
	var assignments: Dictionary = {}
	for index: int in tasks.size():
		var target := _task_target(index)
		var facility := service_facility_for(target)
		if facility == null:
			continue
		if not assignments.has(facility.runtime_id):
			assignments[facility.runtime_id] = []
		(assignments[facility.runtime_id] as Array).append(index)
	var completed_indices: Array[int] = []
	for facility: DefenseUnit in facilities:
		if not is_instance_valid(facility) or not assignments.has(facility.runtime_id):
			continue
		var assigned_indices: Array = assignments[facility.runtime_id]
		var active_count := mini(facility.support_slots(), assigned_indices.size())
		if active_count <= 0:
			continue
		var work_per_task := facility.support_capacity() / float(active_count)
		for assignment_index: int in active_count:
			var task_index := int(assigned_indices[assignment_index])
			var task: Dictionary = tasks[task_index]
			task.remaining_work = float(task.remaining_work) - work_per_task * delta
			tasks[task_index] = task
			if float(task.remaining_work) <= 0.0:
				completed_indices.append(task_index)
	completed_indices.sort()
	completed_indices.reverse()
	for task_index: int in completed_indices:
		_complete_task(task_index)

func service_facility_for(unit: DefenseUnit) -> DefenseUnit:
	if unit == null or not is_instance_valid(unit):
		return null
	return service_facility_for_position(unit.global_position)

func service_facility_for_position(position: Vector3) -> DefenseUnit:
	var nearest: DefenseUnit
	var nearest_distance := INF
	for facility: DefenseUnit in facilities:
		if not is_instance_valid(facility) or not facility.supports_position(position):
			continue
		var offset := Vector2(position.x - facility.global_position.x, position.z - facility.global_position.z)
		var distance := offset.length_squared()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = facility
	return nearest

func serviceable_units_from(position: Vector3, service_range: float, excluded: DefenseUnit = null) -> Array[DefenseUnit]:
	var result: Array[DefenseUnit] = []
	for unit: DefenseUnit in consumers.values():
		if not is_instance_valid(unit) or unit == excluded or unit.integrity <= 0.0:
			continue
		var offset := Vector2(unit.global_position.x - position.x, unit.global_position.z - position.z)
		if offset.length() > 0.01 and offset.length() <= service_range:
			result.append(unit)
	return result

func can_service(unit: DefenseUnit) -> bool:
	return service_facility_for(unit) != null

func _task_target(index: int) -> DefenseUnit:
	var target_id := int(tasks[index].target_defense_id)
	if not consumers.has(target_id) or not is_instance_valid(consumers[target_id]):
		return null
	return consumers[target_id]

func _complete_task(index: int) -> void:
	var task: Dictionary = tasks[index]
	var target := _task_target(index)
	var completed := false
	if target != null:
		if String(task.kind) == RESUPPLY and target.uses_ammunition():
			target.complete_resupply()
			completed = true
		elif String(task.kind) == REPAIR and target.integrity > 0.0:
			target.complete_repair()
			completed = true
	tasks.remove_at(index)
	if completed:
		task_completed.emit(StringName(task.kind), target)

func task_status(unit: DefenseUnit) -> String:
	for index: int in tasks.size():
		if int(tasks[index].target_defense_id) == unit.runtime_id:
			var label := "재보급" if String(tasks[index].kind) == RESUPPLY else "수리"
			return "%s 진행" % label if _task_is_active(index) else "%s 대기" % label
	return ""

func _task_is_active(task_index: int) -> bool:
	var target := _task_target(task_index)
	var facility := service_facility_for(target)
	if facility == null:
		return false
	var earlier_assignments := 0
	for index: int in task_index:
		if service_facility_for(_task_target(index)) == facility:
			earlier_assignments += 1
	return earlier_assignments < facility.support_slots()

func capture_state() -> Dictionary:
	return {"tasks": tasks.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	tasks.clear()
	for task: Dictionary in state.get("tasks", []):
		tasks.append({
			"kind": String(task.kind),
			"target_defense_id": int(task.target_defense_id),
			"remaining_work": float(task.remaining_work),
		})
