class_name PowerManager
extends Node

var facilities: Array[SupportFacility] = []
var available_power: float = 0.0

func reset() -> void:
	facilities.clear()
	available_power = 0.0

func register_asset(unit: DefenseUnit) -> void:
	if unit is SupportFacility:
		facilities.append(unit as SupportFacility)

func begin_tick() -> void:
	available_power = generation_capacity()

func request_power(demand: float) -> float:
	if demand <= 0.0:
		return 0.0
	var supplied := minf(demand, available_power)
	available_power -= supplied
	return supplied

func generation_capacity() -> float:
	var result := 0.0
	for facility: SupportFacility in facilities:
		if is_instance_valid(facility):
			result += facility.power_capacity()
	return result
