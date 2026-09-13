class_name RadarTrackingCoordinator
extends RefCounted

const LEASE_SCAN_INTERVALS := 1.5

class TrackingLease:
	extends RefCounted
	var contact_keys: Dictionary[String, bool] = {}
	var expires_at: float

	func _init(keys: Array[String], expiration: float) -> void:
		for key: String in keys:
			contact_keys[key] = true
		expires_at = expiration

var _leases_by_sensor: Dictionary[int, TrackingLease] = {}
var _scan_phase_by_sensor: Dictionary[int, float] = {}
var _next_scan_phase_index: int = 0

func reserve_initial_scan_delay(sensor_id: int, scan_interval: float) -> float:
	if scan_interval <= 0.0:
		return 0.0
	if not _scan_phase_by_sensor.has(sensor_id):
		_scan_phase_by_sensor[sensor_id] = _radical_inverse_base_two(_next_scan_phase_index)
		_next_scan_phase_index += 1
	return _scan_phase_by_sensor[sensor_id] * scan_interval

func support_counts_excluding(sensor_id: int, timestamp: float) -> Dictionary[String, int]:
	_prune(timestamp)
	var support_counts: Dictionary[String, int] = {}
	for assigned_sensor_id: int in _leases_by_sensor:
		if assigned_sensor_id == sensor_id:
			continue
		for key: String in _leases_by_sensor[assigned_sensor_id].contact_keys:
			support_counts[key] = support_counts.get(key, 0) + 1
	return support_counts

func renew_lease(sensor_id: int, keys: Array[String], timestamp: float, scan_interval: float) -> void:
	var expires_at := timestamp + scan_interval * LEASE_SCAN_INTERVALS
	_leases_by_sensor[sensor_id] = TrackingLease.new(keys, expires_at)

func reset() -> void:
	_leases_by_sensor.clear()
	_scan_phase_by_sensor.clear()
	_next_scan_phase_index = 0

func _radical_inverse_base_two(index: int) -> float:
	var result := 0.0
	var place_value := 0.5
	while index > 0:
		result += float(index & 1) * place_value
		index >>= 1
		place_value *= 0.5
	return result

func _prune(timestamp: float) -> void:
	for sensor_id: int in _leases_by_sensor.keys():
		if _leases_by_sensor[sensor_id].expires_at <= timestamp:
			_leases_by_sensor.erase(sensor_id)
