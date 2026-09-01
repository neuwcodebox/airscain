class_name C2Network
extends Node

var endpoints: Array[DefenseUnit] = []
var _topology_signature: int = 0
var _reachable_sensor_cache: Dictionary[int, Array] = {}

func reset() -> void:
	endpoints.clear()
	_invalidate_cache()

func register_asset(unit: DefenseUnit) -> void:
	if unit.c2_roles() != 0 and not endpoints.has(unit):
		endpoints.append(unit)
		_invalidate_cache()

func local_tracks_for(unit: DefenseUnit, tracks: Array[PlayerTrack]) -> Array[PlayerTrack]:
	var result: Array[PlayerTrack] = []
	var local_sensor_ids := unit.local_sensor_ids()
	for track: PlayerTrack in tracks:
		if _has_any_sensor(track, local_sensor_ids):
			result.append(track)
	return result

func shared_tracks_for(unit: DefenseUnit, tracks: Array[PlayerTrack]) -> Array[PlayerTrack]:
	var result: Array[PlayerTrack] = []
	var local_sensor_ids := unit.local_sensor_ids()
	var reachable_sensor_ids := _reachable_sensor_ids(unit)
	for track: PlayerTrack in tracks:
		if _has_any_sensor(track, local_sensor_ids):
			continue
		for sensor_id: int in track.contributing_sensor_ids:
			if reachable_sensor_ids.has(sensor_id):
				result.append(track)
				break
	return result

func available_tracks_for(unit: DefenseUnit, tracks: Array[PlayerTrack]) -> Array[PlayerTrack]:
	var result := local_tracks_for(unit, tracks)
	result.append_array(shared_tracks_for(unit, tracks))
	return result

func has_command_path(unit: DefenseUnit, sensor_id: int) -> bool:
	if not _is_operational_endpoint(unit):
		return false
	return _reachable_sensor_ids(unit).has(sensor_id)

func _reachable_sensor_ids(unit: DefenseUnit) -> Array[int]:
	_refresh_cache_if_topology_changed()
	var unit_id := unit.get_instance_id()
	if _reachable_sensor_cache.has(unit_id):
		var cached: Array = _reachable_sensor_cache[unit_id]
		var cached_result: Array[int] = []
		cached_result.assign(cached)
		return cached_result
	var result: Array[int] = []
	var queue: Array[Dictionary] = [{"unit": unit, "has_command": _has_role(unit, DefenseUnit.C2Role.COMMAND)}]
	var visited: Dictionary[String, bool] = {}
	while not queue.is_empty():
		var entry: Dictionary = queue.pop_front()
		var current := entry.unit as DefenseUnit
		var has_command: bool = entry.has_command
		var state_key := "%d:%d" % [current.get_instance_id(), int(has_command)]
		if visited.has(state_key):
			continue
		visited[state_key] = true
		if has_command and _has_role(current, DefenseUnit.C2Role.SENSOR) and not result.has(current.runtime_id):
			result.append(current.runtime_id)
		for neighbor: DefenseUnit in endpoints:
			if neighbor == current or not _are_linked(current, neighbor):
				continue
			queue.append({"unit": neighbor, "has_command": has_command or _has_role(neighbor, DefenseUnit.C2Role.COMMAND)})
	_reachable_sensor_cache[unit_id] = result
	return result

func active_links() -> Array[Array]:
	var result: Array[Array] = []
	for first_index: int in endpoints.size():
		for second_index: int in range(first_index + 1, endpoints.size()):
			if _are_linked(endpoints[first_index], endpoints[second_index]):
				result.append([endpoints[first_index], endpoints[second_index]])
	return result

func _are_linked(first: DefenseUnit, second: DefenseUnit) -> bool:
	if not _is_operational_endpoint(first) or not _is_operational_endpoint(second):
		return false
	var maximum_distance := minf(first.c2_link_range(), second.c2_link_range())
	return maximum_distance > 0.0 and first.global_position.distance_to(second.global_position) <= maximum_distance

func _is_operational_endpoint(unit: DefenseUnit) -> bool:
	return is_instance_valid(unit) and unit.active and unit.c2_roles() != 0

func _has_role(unit: DefenseUnit, role: DefenseUnit.C2Role) -> bool:
	return (unit.c2_roles() & role) != 0

func _has_any_sensor(track: PlayerTrack, sensor_ids: Array[int]) -> bool:
	for sensor_id: int in sensor_ids:
		if track.contributing_sensor_ids.has(sensor_id):
			return true
	return false

func _refresh_cache_if_topology_changed() -> void:
	var signature_value: int = endpoints.size()
	for endpoint: DefenseUnit in endpoints:
		signature_value = hash([signature_value, endpoint.get_instance_id(), endpoint.active, endpoint.global_position])
	if signature_value != _topology_signature:
		_topology_signature = signature_value
		_reachable_sensor_cache.clear()

func _invalidate_cache() -> void:
	_topology_signature = 0
	_reachable_sensor_cache.clear()
