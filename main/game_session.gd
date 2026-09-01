class_name GameSession
extends Node

enum Phase { PREPARATION, RUNNING, GAME_OVER }

signal budget_changed(amount: int)
signal phase_changed(phase: Phase)
signal statistics_changed
signal defense_placed(unit: DefenseUnit)

var phase := Phase.PREPARATION
var budget: int = 0
var survival_time: float = 0.0
var neutralized_count: int = 0
var defense_count: int = 0
var highest_pressure: int = 1
var simulation_speed: float = 1.0
var next_defense_id: int = 1

func reset(starting_budget: int) -> void:
	phase = Phase.PREPARATION
	budget = starting_budget
	survival_time = 0.0
	neutralized_count = 0
	defense_count = 0
	highest_pressure = 1
	simulation_speed = 1.0
	next_defense_id = 1
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
	statistics_changed.emit()
	return result

func request_placement(definition: DefenseDefinition, position: Vector3, battlefield: Battlefield, defense_parent: Node3D, registry: ThreatRegistry, projectile_parent: Node3D) -> Dictionary:
	if phase == Phase.GAME_OVER:
		return {"success": false, "reason": "게임이 종료되었습니다"}
	if definition == null or definition.placement_profile == null:
		return {"success": false, "reason": "잘못된 방어 수단입니다"}
	if budget < definition.price:
		return {"success": false, "reason": "예산이 부족합니다"}
	var validation := battlefield.placement_result(position, definition.placement_profile)
	if not validation.valid:
		return {"success": false, "reason": validation.reason}
	var unit := definition.scene.instantiate() as DefenseUnit
	if unit == null:
		return {"success": false, "reason": "방어 수단을 생성할 수 없습니다"}
	defense_parent.add_child(unit)
	unit.global_position = Vector3(position.x, battlefield.terrain_height(position.x, position.z), position.z)
	unit.setup(next_defense_id, definition)
	unit.configure_combat(registry, projectile_parent)
	next_defense_id += 1
	battlefield.register_occupancy(unit.global_position, definition.placement_profile.footprint_radius)
	budget -= definition.price
	defense_count += 1
	budget_changed.emit(budget)
	statistics_changed.emit()
	defense_placed.emit(unit)
	return {"success": true, "reason": "배치 완료", "unit": unit}

func register_threat_resolution(_threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	if neutralized:
		neutralized_count += 1
		budget += reward
		budget_changed.emit(budget)
	statistics_changed.emit()

func update_pressure(level: int) -> void:
	highest_pressure = maxi(highest_pressure, level)
	statistics_changed.emit()

func end_game() -> void:
	if phase == Phase.GAME_OVER:
		return
	phase = Phase.GAME_OVER
	phase_changed.emit(phase)
	statistics_changed.emit()

func set_simulation_speed(value: float) -> void:
	if phase != Phase.GAME_OVER and (is_zero_approx(value) or is_equal_approx(value, 1.0) or is_equal_approx(value, 2.0)):
		simulation_speed = value
		statistics_changed.emit()
