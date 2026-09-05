class_name EngagementCoordinator
extends Node

const INTERCEPTOR := &"interceptor"
const FIRE_SUPPORT := &"fire_support"

var _reservations: Array[Dictionary] = []
var _queries_dirty: bool = true
var _counts: Dictionary[int, Dictionary] = {}
var _owners: Dictionary[int, Array] = {}
var _support: Dictionary[int, Dictionary] = {}

func total_reservations() -> int:
	return _reservations.size()

func _remove_reservation(index: int) -> void:
	_reservations.remove_at(index)
	_queries_dirty = true

func _append_reservation(reservation: Dictionary) -> void:
	_reservations.append(reservation)
	_queries_dirty = true

func reset() -> void:
	_reservations.clear()
	_queries_dirty = true

func gameplay_tick(delta: float) -> void:
	for index: int in range(_reservations.size() - 1, -1, -1):
		_reservations[index].remaining = float(_reservations[index].remaining) - delta
		if float(_reservations[index].remaining) <= 0.0:
			_remove_reservation(index)

func try_reserve(track_id: int, owner_defense_id: int, duration: float, maximum_concurrent: int = 1) -> bool:
	if track_id <= 0 or owner_defense_id <= 0 or duration <= 0.0 or maximum_concurrent < 1 or reservation_count(track_id, INTERCEPTOR) >= maximum_concurrent:
		return false
	_append_reservation({
		"track_id": track_id,
		"owner_defense_id": owner_defense_id,
		"remaining": duration,
		"kind": String(INTERCEPTOR),
	})
	return true

func reserve_fire_support(track_id: int, owner_defense_id: int, duration: float = 0.5) -> bool:
	if track_id <= 0 or owner_defense_id <= 0 or duration <= 0:
		return false
	_refresh_queries()
	if _support.has(owner_defense_id):
		var reservation: Dictionary = _support[owner_defense_id]
		_queries_dirty = int(reservation.track_id) != track_id
		reservation.track_id = track_id
		reservation.remaining = duration
		return true
	_append_reservation({"track_id": track_id, "owner_defense_id": owner_defense_id, "remaining": duration, "kind": String(FIRE_SUPPORT)})
	return true

func release_fire_support(owner_defense_id: int) -> void:
	for index: int in range(_reservations.size() - 1, -1, -1):
		if StringName(_reservations[index].get("kind", INTERCEPTOR)) == FIRE_SUPPORT and int(_reservations[index].owner_defense_id) == owner_defense_id:
			_remove_reservation(index)

func fire_support_target(owner_defense_id: int) -> int:
	_refresh_queries()
	return int(_support[owner_defense_id].track_id) if _support.has(owner_defense_id) else 0

func release(track_id: int, owner_defense_id: int) -> void:
	for index: int in range(_reservations.size() - 1, -1, -1):
		var reservation := _reservations[index]
		if int(reservation.track_id) == track_id and int(reservation.owner_defense_id) == owner_defense_id:
			_remove_reservation(index)

func release_one(track_id: int, owner_defense_id: int) -> void:
	for index: int in _reservations.size():
		var reservation := _reservations[index]
		if int(reservation.track_id) == track_id and int(reservation.owner_defense_id) == owner_defense_id:
			_remove_reservation(index)
			return

func has_reservation(track_id: int) -> bool:
	return reservation_count(track_id) > 0

func reservation_count(track_id: int, kind: StringName = &"") -> int:
	_refresh_queries()
	return int(_counts[track_id].get(kind, 0)) if _counts.has(track_id) else 0

func engagement_owner_ids(track_id: int) -> Array[int]:
	_refresh_queries()
	var result: Array[int] = []
	if _owners.has(track_id):
		result.assign(_owners[track_id])
	return result

func _refresh_queries() -> void:
	if not _queries_dirty:
		return
	_counts.clear()
	_owners.clear()
	_support.clear()
	for reservation: Dictionary in _reservations:
		var track_id := int(reservation.track_id)
		var owner_id := int(reservation.owner_defense_id)
		var kind := StringName(reservation.get("kind", INTERCEPTOR))
		if not _counts.has(track_id):
			_counts[track_id] = {}
			_owners[track_id] = []
		_counts[track_id][&""] = int(_counts[track_id].get(&"", 0)) + 1
		_counts[track_id][kind] = int(_counts[track_id].get(kind, 0)) + 1
		if not _owners[track_id].has(owner_id):
			_owners[track_id].append(owner_id)
		if kind == FIRE_SUPPORT and not _support.has(owner_id):
			_support[owner_id] = reservation
	_queries_dirty = false

func capture_state() -> Dictionary:
	return {"reservations": _reservations.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	reset()
	for reservation: Dictionary in state.get("reservations", []):
		_append_reservation({
			"track_id": int(reservation.track_id),
			"owner_defense_id": int(reservation.owner_defense_id),
			"remaining": float(reservation.remaining),
			"kind": String(reservation.get("kind", INTERCEPTOR)),
		})
