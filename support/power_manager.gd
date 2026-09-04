class_name PowerManager
extends Node

var facilities: Array[DefenseUnit] = []
var consumers: Array[DefenseUnit] = []
var available_power: float = 0.0

func reset() -> void:
	facilities.clear()
	consumers.clear()
	available_power = 0.0

func register_asset(unit: DefenseUnit) -> void:
	if unit.power_capacity() > 0.0:
		facilities.append(unit)
	if unit.power_demand() > 0.0 and not consumers.has(unit):
		consumers.append(unit)

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
	for facility: DefenseUnit in facilities:
		if is_instance_valid(facility):
			result += facility.power_capacity()
	return result

func total_demand() -> float:
	var result := 0.0
	for consumer: DefenseUnit in consumers:
		if is_instance_valid(consumer) and consumer.active:
			result += consumer.power_demand()
	return result

func consumer_status(demand: float) -> String:
	var capacity := generation_capacity()
	var status := "전력 수요 %d / 총 공급 %d" % [roundi(demand), roundi(capacity)]
	if total_demand() > capacity:
		status += "  공급 부족"
	return status
