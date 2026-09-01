class_name SupportManager
extends Node

var facilities: Array[SupportFacility] = []
var consumers: Dictionary[int, ArmedDefenseUnit] = {}
var tasks: Array[Dictionary] = []
var session: GameSession

func configure(session_value: GameSession) -> void:
	session = session_value

func reset() -> void:
	facilities.clear()
	consumers.clear()
	tasks.clear()

func register_asset(unit: DefenseUnit) -> void:
	if unit is SupportFacility:
		facilities.append(unit as SupportFacility)
	elif unit is ArmedDefenseUnit:
		consumers[unit.runtime_id] = unit as ArmedDefenseUnit

func request_resupply(unit: ArmedDefenseUnit) -> bool:
	if unit == null or not consumers.has(unit.runtime_id) or unit.magazine.reserve >= unit.magazine.reserve_capacity or task_status(unit) != "":
		return false
	if session == null or not session.try_spend(unit.resupply_cost()):
		return false
	tasks.append({
		"target_defense_id": unit.runtime_id,
		"remaining_work": unit.resupply_work(),
	})
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
				consumers[target_id].magazine.refill_reserve()
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

func task_status(unit: ArmedDefenseUnit) -> String:
	for index: int in tasks.size():
		if int(tasks[index].target_defense_id) == unit.runtime_id:
			return "재보급 진행" if index < total_slots() and total_capacity() > 0.0 else "재보급 대기"
	return ""

func capture_state() -> Dictionary:
	return {"tasks": tasks.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	tasks.clear()
	for task: Dictionary in state.get("tasks", []):
		tasks.append({
			"target_defense_id": int(task.target_defense_id),
			"remaining_work": float(task.remaining_work),
		})
