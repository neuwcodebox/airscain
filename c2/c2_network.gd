class_name C2Network
extends Node

var endpoints: Array[DefenseUnit] = []
var threat_registry: ThreatRegistry
var _topology_signature: int = 0
var _reachable_sensor_cache: Dictionary[int, Array] = {}
var _jamming_refresh_remaining: float = 0.0
var _jamming_epoch: int = 0

func configure(registry: ThreatRegistry) -> void:
	threat_registry = registry
	_invalidate_cache()

func gameplay_tick(delta: float) -> void:
	if threat_registry == null:
		return
	_jamming_refresh_remaining -= delta
	if _jamming_refresh_remaining <= 0.0:
		_jamming_refresh_remaining += 2.0
		_jamming_epoch += 1

func reset() -> void:
	endpoints.clear()
	_jamming_refresh_remaining = 0.0
	_jamming_epoch = 0
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
	return []

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
	if threat_registry != null:
		var midpoint := first.global_position.lerp(second.global_position, 0.5)
		var interference := maxf(threat_registry.jamming_at(first.global_position), maxf(threat_registry.jamming_at(midpoint), threat_registry.jamming_at(second.global_position)))
		maximum_distance *= 1.0 - interference * 0.9
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
	if threat_registry != null:
		signature_value = hash([signature_value, _jamming_epoch])
	if signature_value != _topology_signature:
		_topology_signature = signature_value
		_rebuild_reachable_cache()

func _rebuild_reachable_cache() -> void:
	_reachable_sensor_cache.clear()
	var visited: Dictionary[int, bool] = {}
	for start: DefenseUnit in endpoints:
		var start_id := start.get_instance_id()
		if visited.has(start_id) or not _is_operational_endpoint(start):
			continue
		var component: Array[DefenseUnit] = []
		var queue: Array[DefenseUnit] = [start]
		visited[start_id] = true
		while not queue.is_empty():
			var current := queue.pop_front() as DefenseUnit
			component.append(current)
			for neighbor: DefenseUnit in endpoints:
				var neighbor_id := neighbor.get_instance_id()
				if visited.has(neighbor_id) or not _are_linked(current, neighbor):
					continue
				visited[neighbor_id] = true
				queue.append(neighbor)
		var has_command := false
		var sensor_ids: Array[int] = []
		for member: DefenseUnit in component:
			has_command = has_command or _has_role(member, DefenseUnit.C2Role.COMMAND)
			if _has_role(member, DefenseUnit.C2Role.SENSOR):
				sensor_ids.append(member.runtime_id)
		var shared_sensors: Array[int] = []
		if has_command:
			shared_sensors.assign(sensor_ids)
		for member: DefenseUnit in component:
			_reachable_sensor_cache[member.get_instance_id()] = shared_sensors.duplicate()

func _invalidate_cache() -> void:
	_topology_signature = 0
	_reachable_sensor_cache.clear()
