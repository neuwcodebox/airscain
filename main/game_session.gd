class_name GameSession
extends Node

enum Phase { PREPARATION, RUNNING, GAME_OVER }

signal budget_changed(amount: int)
signal phase_changed(phase: Phase)
signal statistics_changed
signal defense_placed(unit: DefenseUnit)
signal support_received(amount: int, reason: String)

var phase := Phase.PREPARATION
var budget: int = 0
var survival_time: float = 0.0
var neutralized_count: int = 0
var defense_count: int = 0
var highest_pressure: int = 1
var current_pressure: int = 1
var simulation_speed: float = 1.0
var next_defense_id: int = 1
var support_interval: float = 90.0
var support_amount: int = 180
var next_support_at: float = 90.0
var support_payment_count: int = 0
var completed_attack_windows: int = 0
var total_support_received: int = 0
var unlimited_budget: bool = false

func reset(starting_budget: int, support_interval_value: float = 90.0, support_amount_value: int = 180) -> void:
	phase = Phase.PREPARATION
	budget = starting_budget
	survival_time = 0.0
	neutralized_count = 0
	defense_count = 0
	highest_pressure = 1
	current_pressure = 1
	simulation_speed = 1.0
	next_defense_id = 1
	support_interval = support_interval_value
	support_amount = support_amount_value
	next_support_at = support_interval
	support_payment_count = 0
	completed_attack_windows = 0
	total_support_received = 0
	unlimited_budget = false
	budget_changed.emit(budget)
	phase_changed.emit(phase)
	statistics_changed.emit()

func start_defense() -> bool:
	if phase != Phase.PREPARATION or defense_count < 1:
		return false
	phase = Phase.RUNNING
	phase_changed.emit(phase)
	return true

func gameplay_delta(delta: float) -> float:
	if phase != Phase.RUNNING:
		return 0.0
	var result := delta * simulation_speed
	survival_time += result
	while survival_time >= next_support_at:
		_grant_support(support_amount, "정기 작전 지원")
		support_payment_count += 1
		next_support_at += support_interval
	statistics_changed.emit()
	return result

func request_placement(definition: DefenseDefinition, position: Vector3, battlefield: Battlefield, defense_parent: Node3D, registry: ThreatRegistry, projectile_parent: Node3D) -> Dictionary:
	if phase == Phase.GAME_OVER:
		return {"success": false, "reason": "게임이 종료되었습니다"}
	if definition == null or definition.placement_profile == null:
		return {"success": false, "reason": "잘못된 방어 수단입니다"}
	if definition.unlock_pressure_level > current_pressure:
		return {"success": false, "reason": "전투 강도 %d에서 해금됩니다" % definition.unlock_pressure_level}
	if not unlimited_budget and budget < definition.price:
		return {"success": false, "reason": "예산이 부족합니다"}
	var validation := battlefield.placement_result(position, definition.placement_profile)
	if not validation.valid:
		return {"success": false, "reason": validation.reason}
	var unit := definition.scene.instantiate() as DefenseUnit
	if unit == null:
		return {"success": false, "reason": "방어 수단을 생성할 수 없습니다"}
	defense_parent.add_child(unit)
	unit.global_position = battlefield.snap_placement_position(position, definition.placement_profile)
	unit.setup(next_defense_id, definition)
	unit.configure_combat(registry, projectile_parent)
	next_defense_id += 1
	battlefield.register_occupancy(unit.global_position, definition.placement_profile.footprint_radius)
	if not unlimited_budget:
		budget -= definition.price
	defense_count += 1
	budget_changed.emit(budget)
	statistics_changed.emit()
	defense_placed.emit(unit)
	return {"success": true, "reason": "배치 완료", "unit": unit}

func register_threat_resolution(_threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	if neutralized and _threat.definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
		neutralized_count += 1
		budget += reward
		budget_changed.emit(budget)
	statistics_changed.emit()

func update_pressure(level: int) -> void:
	current_pressure = maxi(current_pressure, level)
	highest_pressure = maxi(highest_pressure, current_pressure)
	statistics_changed.emit()

func grant_attack_window_reward(amount: int) -> void:
	if phase != Phase.RUNNING:
		return
	completed_attack_windows += 1
	_grant_support(amount, "공격 구간 방어 보상")

func _grant_support(amount: int, reason: String) -> void:
	if amount <= 0 or phase == Phase.GAME_OVER:
		return
	budget += amount
	total_support_received += amount
	budget_changed.emit(budget)
	support_received.emit(amount, reason)

func end_game() -> void:
	if phase == Phase.GAME_OVER:
		return
	phase = Phase.GAME_OVER
	phase_changed.emit(phase)
	statistics_changed.emit()

func set_simulation_speed(value: float) -> void:
	if phase != Phase.GAME_OVER and (is_zero_approx(value) or is_equal_approx(value, 1.0) or is_equal_approx(value, 2.0) or is_equal_approx(value, 4.0)):
		simulation_speed = value
		statistics_changed.emit()

func try_spend(amount: int) -> bool:
	if amount < 0 or phase == Phase.GAME_OVER or not unlimited_budget and budget < amount:
		return false
	if unlimited_budget:
		return true
	budget -= amount
	budget_changed.emit(budget)
	statistics_changed.emit()
	return true

func capture_state() -> Dictionary:
	return {
		"phase": int(phase),
		"budget": budget,
		"survival_time": survival_time,
		"neutralized_count": neutralized_count,
		"defense_count": defense_count,
		"highest_pressure": highest_pressure,
		"current_pressure": current_pressure,
		"simulation_speed": simulation_speed,
		"next_defense_id": next_defense_id,
		"support_interval": support_interval,
		"support_amount": support_amount,
		"next_support_at": next_support_at,
		"support_payment_count": support_payment_count,
		"completed_attack_windows": completed_attack_windows,
		"total_support_received": total_support_received,
	}

func restore_state(state: Dictionary) -> void:
	phase = int(state.phase) as Phase
	budget = int(state.budget)
	survival_time = float(state.survival_time)
	neutralized_count = int(state.neutralized_count)
	defense_count = int(state.defense_count)
	highest_pressure = int(state.highest_pressure)
	current_pressure = int(state.current_pressure)
	simulation_speed = float(state.simulation_speed)
	next_defense_id = int(state.next_defense_id)
	support_interval = float(state.support_interval)
	support_amount = int(state.support_amount)
	next_support_at = float(state.next_support_at)
	support_payment_count = int(state.support_payment_count)
	completed_attack_windows = int(state.completed_attack_windows)
	total_support_received = int(state.total_support_received)
	budget_changed.emit(budget)
	phase_changed.emit(phase)
	statistics_changed.emit()
