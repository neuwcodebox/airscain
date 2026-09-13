class_name RadarTrackingCoordinator
extends RefCounted

var _leases: Dictionary[int, Dictionary] = {}

func begin_selection(sensor_id: int, timestamp: float) -> Dictionary[String, int]:
	_prune(timestamp)
	_leases.erase(sensor_id)
	var support_counts: Dictionary[String, int] = {}
	for lease: Dictionary in _leases.values():
		var keys: Dictionary = lease["keys"]
		for key: String in keys:
			support_counts[key] = support_counts.get(key, 0) + 1
	return support_counts

func commit_selection(sensor_id: int, keys: Array[String], expires_at: float) -> void:
	var assigned: Dictionary[String, bool] = {}
	for key: String in keys:
		assigned[key] = true
	_leases[sensor_id] = {"keys": assigned, "expires_at": expires_at}

func reset() -> void:
	_leases.clear()

func _prune(timestamp: float) -> void:
	for sensor_id: int in _leases.keys():
		if float(_leases[sensor_id].expires_at) <= timestamp:
			_leases.erase(sensor_id)
