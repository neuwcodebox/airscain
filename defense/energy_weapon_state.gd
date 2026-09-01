class_name EnergyWeaponState
extends RefCounted

var capacity: float
var energy: float
var recharge_rate: float
var heat_capacity: float
var heat: float = 0.0
var heat_per_shot: float
var cooling_rate: float
var overheated: bool = false

func setup(capacity_value: float, recharge_rate_value: float, heat_capacity_value: float, heat_per_shot_value: float, cooling_rate_value: float) -> void:
	capacity = capacity_value
	energy = capacity_value
	recharge_rate = recharge_rate_value
	heat_capacity = heat_capacity_value
	heat_per_shot = heat_per_shot_value
	cooling_rate = cooling_rate_value
	heat = 0.0
	overheated = false

func gameplay_tick(delta: float, power_fraction: float) -> void:
	energy = minf(capacity, energy + recharge_rate * clampf(power_fraction, 0.0, 1.0) * delta)
	heat = maxf(0.0, heat - cooling_rate * delta)
	if overheated and heat <= heat_capacity * 0.3:
		overheated = false

func can_fire(energy_cost: float) -> bool:
	return not overheated and energy >= energy_cost

func consume(energy_cost: float) -> bool:
	if not can_fire(energy_cost):
		return false
	energy -= energy_cost
	heat = minf(heat_capacity, heat + heat_per_shot)
	if heat >= heat_capacity:
		overheated = true
	return true

func capture_state() -> Dictionary:
	return {"capacity": capacity, "energy": energy, "recharge_rate": recharge_rate, "heat_capacity": heat_capacity, "heat": heat, "heat_per_shot": heat_per_shot, "cooling_rate": cooling_rate, "overheated": overheated}

func restore_state(state: Dictionary) -> void:
	capacity = float(state.get("capacity", capacity))
	energy = float(state.get("energy", energy))
	recharge_rate = float(state.get("recharge_rate", recharge_rate))
	heat_capacity = float(state.get("heat_capacity", heat_capacity))
	heat = float(state.get("heat", heat))
	heat_per_shot = float(state.get("heat_per_shot", heat_per_shot))
	cooling_rate = float(state.get("cooling_rate", cooling_rate))
	overheated = bool(state.get("overheated", overheated))

static func validation_error(state: Variant) -> String:
	if not state is Dictionary:
		return "에너지 상태가 없습니다"
	var value := state as Dictionary
	var saved_capacity := float(value.get("capacity", 0.0))
	var saved_energy := float(value.get("energy", -1.0))
	var saved_heat_capacity := float(value.get("heat_capacity", 0.0))
	var saved_heat := float(value.get("heat", -1.0))
	if saved_capacity <= 0.0 or saved_energy < 0.0 or saved_energy > saved_capacity or float(value.get("recharge_rate", 0.0)) <= 0.0 or saved_heat_capacity <= 0.0 or saved_heat < 0.0 or saved_heat > saved_heat_capacity or float(value.get("heat_per_shot", 0.0)) <= 0.0 or float(value.get("cooling_rate", 0.0)) <= 0.0:
		return "충전량 또는 열 상태가 올바르지 않습니다"
	return ""
