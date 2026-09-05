class_name C2Network
extends Node

const MINIMUM_LINK_DISTANCE := 0.01

var endpoints: Array[DefenseUnit] = []
var threat_registry: ThreatRegistry
var _topology_dirty: bool = true
var _endpoint_ids: Array[int] = []
var _endpoint_positions: Array[Vector3] = []
var _endpoint_active: Array[bool] = []
var _cached_jamming_epoch: int = -1
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
	var result: Array[PlayerTrack] = []
	var shared: Array[PlayerTrack] = []
	var local_sensor_ids := unit.local_sensor_ids()
	var reachable_sensor_ids := _reachable_sensor_ids(unit)
	for track: PlayerTrack in tracks:
		if _has_any_sensor(track, local_sensor_ids):
			result.append(track)
		else:
			for sensor_id: int in track.contributing_sensor_ids:
				if reachable_sensor_ids.has(sensor_id):
					shared.append(track)
					break
	# Local tracks retain their original priority over shared tracks.
	result.append_array(shared)
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

func placement_preview(definition: DefenseDefinition, position: Vector3) -> Dictionary:
	var direct_links: Array[DefenseUnit] = []
	var candidate_range := definition.placement_c2_range()
	var candidate_roles := definition.placement_c2_roles()
	if candidate_range <= 0.0 or candidate_roles == 0:
		return {"links": direct_links, "ready": true}
	for endpoint: DefenseUnit in endpoints:
		if _candidate_is_linked(position, candidate_range, endpoint):
			direct_links.append(endpoint)
	var component_roles := candidate_roles
	var visited: Dictionary[int, bool] = {}
	var queue: Array[DefenseUnit] = direct_links.duplicate()
	for endpoint: DefenseUnit in queue:
		visited[endpoint.get_instance_id()] = true
	while not queue.is_empty():
		var current := queue.pop_front() as DefenseUnit
		component_roles |= current.c2_roles()
		for neighbor: DefenseUnit in endpoints:
			var neighbor_id := neighbor.get_instance_id()
			if visited.has(neighbor_id) or not _are_linked(current, neighbor):
				continue
			visited[neighbor_id] = true
			queue.append(neighbor)
	var required_roles := 0
	if (candidate_roles & DefenseUnit.C2Role.SENSOR) != 0:
		required_roles |= DefenseUnit.C2Role.COMMAND
	if (candidate_roles & DefenseUnit.C2Role.COMMAND) != 0:
		required_roles |= DefenseUnit.C2Role.SENSOR
	if (candidate_roles & DefenseUnit.C2Role.DEFENSE) != 0:
		required_roles |= DefenseUnit.C2Role.SENSOR | DefenseUnit.C2Role.COMMAND
	var ready := not direct_links.is_empty() and (component_roles & required_roles) == required_roles
	return {"links": direct_links, "ready": ready}

func _candidate_is_linked(position: Vector3, candidate_range: float, endpoint: DefenseUnit) -> bool:
	if not _is_operational_endpoint(endpoint):
		return false
	var maximum_distance := minf(candidate_range, endpoint.c2_link_range())
	if threat_registry != null:
		var midpoint := position.lerp(endpoint.global_position, 0.5)
		var interference := maxf(threat_registry.jamming_at(position), maxf(threat_registry.jamming_at(midpoint), threat_registry.jamming_at(endpoint.global_position)))
		maximum_distance *= 1.0 - interference * 0.9
	var distance := position.distance_to(endpoint.global_position)
	return maximum_distance > 0.0 and distance > MINIMUM_LINK_DISTANCE and distance <= maximum_distance

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
	var changed := _topology_dirty or (threat_registry != null and _cached_jamming_epoch != _jamming_epoch)
	if _endpoint_ids.size() != endpoints.size():
		_endpoint_ids.resize(endpoints.size())
		_endpoint_positions.resize(endpoints.size())
		_endpoint_active.resize(endpoints.size())
		changed = true
	for index: int in endpoints.size():
		var endpoint := endpoints[index]
		var id := endpoint.get_instance_id()
		var position := endpoint.global_position
		if _endpoint_ids[index] != id or _endpoint_positions[index] != position or _endpoint_active[index] != endpoint.active:
			_endpoint_ids[index] = id
			_endpoint_positions[index] = position
			_endpoint_active[index] = endpoint.active
			changed = true
	if changed:
		_topology_dirty = false
		_cached_jamming_epoch = _jamming_epoch
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
	_topology_dirty = true
	_reachable_sensor_cache.clear()
