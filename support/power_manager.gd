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
	var total := total_demand()
	var status := "전체 전력 %d / %d · 이 자산 수요 %d" % [roundi(total), roundi(capacity), roundi(demand)]
	if total > capacity:
		status += "  공급 부족"
	return status

func consumer_status_rows(demand: float) -> Array[Dictionary]:
	var capacity := generation_capacity()
	var total := total_demand()
	var shortage := total > capacity
	return [
		{"label": "전체 수요 / 공급", "value": "%d / %d" % [roundi(total), roundi(capacity)]},
		{"label": "이 자산 전력 수요", "value": "%d" % roundi(demand)},
		{"label": "전력망 상태", "value": "부족" if shortage else "정상", "warning": shortage},
	]
