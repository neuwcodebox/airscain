class_name SupportManager
extends Node

var facilities: Array[SupportFacility] = []
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
	if unit is SupportFacility:
		facilities.append(unit as SupportFacility)

func request_resupply(unit: ArmedDefenseUnit) -> bool:
	if unit == null or not consumers.has(unit.runtime_id) or unit.magazine.reserve >= unit.magazine.reserve_capacity or task_status(unit) != "":
		return false
	return _request_task(unit, RESUPPLY, unit.resupply_cost(), unit.resupply_work())

func request_repair(unit: DefenseUnit) -> bool:
	if unit == null or not consumers.has(unit.runtime_id) or unit.integrity <= 0.0 or unit.integrity >= unit.definition.maximum_integrity or task_status(unit) != "":
		return false
	return _request_task(unit, REPAIR, unit.repair_cost(), unit.repair_work())

func _request_task(unit: DefenseUnit, kind: String, cost: int, work: float) -> bool:
	if session == null or not session.try_spend(cost):
		return false
	tasks.append({"kind": kind, "target_defense_id": unit.runtime_id, "remaining_work": work})
	return true

func gameplay_tick(delta: float) -> void:
	var capacity := total_capacity()
	var task_count := mini(total_slots(), tasks.size())
	if capacity <= 0.0 or task_count <= 0:
		return
	var work_per_task := capacity / float(task_count)
	for index: int in range(task_count - 1, -1, -1):
		var task := tasks[index]
		task.remaining_work = float(task.remaining_work) - work_per_task * delta
		tasks[index] = task
		if float(task.remaining_work) <= 0.0:
			var target_id := int(task.target_defense_id)
			if consumers.has(target_id) and is_instance_valid(consumers[target_id]):
				var target := consumers[target_id]
				if String(task.kind) == RESUPPLY and target is ArmedDefenseUnit:
					(target as ArmedDefenseUnit).magazine.refill_reserve()
				elif String(task.kind) == REPAIR and target.integrity > 0.0:
					target.complete_repair()
			tasks.remove_at(index)

func total_capacity() -> float:
	var result := 0.0
	for facility: SupportFacility in facilities:
		if is_instance_valid(facility):
			result += facility.support_capacity()
	return result

func total_slots() -> int:
	var result := 0
	for facility: SupportFacility in facilities:
		if is_instance_valid(facility):
			result += facility.support_slots()
	return result

func task_status(unit: DefenseUnit) -> String:
	for index: int in tasks.size():
		if int(tasks[index].target_defense_id) == unit.runtime_id:
			var label := "재보급" if String(tasks[index].kind) == RESUPPLY else "수리"
			return "%s 진행" % label if index < total_slots() and total_capacity() > 0.0 else "%s 대기" % label
	return ""

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
