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

func _prune(timestamp: float) -> void:
	for sensor_id: int in _leases_by_sensor.keys():
		if _leases_by_sensor[sensor_id].expires_at <= timestamp:
			_leases_by_sensor.erase(sensor_id)
