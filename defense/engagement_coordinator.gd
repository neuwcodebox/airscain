class_name EngagementCoordinator
extends Node

const INTERCEPTOR := &"interceptor"
const FIRE_SUPPORT := &"fire_support"

var reservations: Array[Dictionary] = []

func reset() -> void:
	reservations.clear()

func gameplay_tick(delta: float) -> void:
	for index: int in range(reservations.size() - 1, -1, -1):
		reservations[index].remaining = float(reservations[index].remaining) - delta
		if float(reservations[index].remaining) <= 0.0:
			reservations.remove_at(index)

func try_reserve(track_id: int, owner_defense_id: int, duration: float, maximum_concurrent: int = 1) -> bool:
	if track_id <= 0 or owner_defense_id <= 0 or duration <= 0.0 or maximum_concurrent < 1 or reservation_count(track_id, INTERCEPTOR) >= maximum_concurrent:
		return false
	reservations.append({
		"track_id": track_id,
		"owner_defense_id": owner_defense_id,
		"remaining": duration,
		"kind": String(INTERCEPTOR),
	})
	return true

func reserve_fire_support(track_id: int, owner_defense_id: int, duration: float = 0.5) -> bool:
	if track_id <= 0 or owner_defense_id <= 0 or duration <= 0:
		return false
	for reservation: Dictionary in reservations:
		if StringName(reservation.get("kind", INTERCEPTOR)) == FIRE_SUPPORT and int(reservation.owner_defense_id) == owner_defense_id:
			reservation.track_id = track_id
			reservation.remaining = duration
			return true
	reservations.append({"track_id": track_id, "owner_defense_id": owner_defense_id, "remaining": duration, "kind": String(FIRE_SUPPORT)})
	return true

func release_fire_support(owner_defense_id: int) -> void:
	for index: int in range(reservations.size() - 1, -1, -1):
		if StringName(reservations[index].get("kind", INTERCEPTOR)) == FIRE_SUPPORT and int(reservations[index].owner_defense_id) == owner_defense_id:
			reservations.remove_at(index)

func fire_support_target(owner_defense_id: int) -> int:
	for reservation: Dictionary in reservations:
		if StringName(reservation.get("kind", INTERCEPTOR)) == FIRE_SUPPORT and int(reservation.owner_defense_id) == owner_defense_id:
			return int(reservation.track_id)
	return 0

func release(track_id: int, owner_defense_id: int) -> void:
	for index: int in range(reservations.size() - 1, -1, -1):
		var reservation := reservations[index]
		if int(reservation.track_id) == track_id and int(reservation.owner_defense_id) == owner_defense_id:
			reservations.remove_at(index)

func release_one(track_id: int, owner_defense_id: int) -> void:
	for index: int in reservations.size():
		var reservation := reservations[index]
		if int(reservation.track_id) == track_id and int(reservation.owner_defense_id) == owner_defense_id:
			reservations.remove_at(index)
			return

func has_reservation(track_id: int) -> bool:
	return reservation_count(track_id) > 0

func reservation_count(track_id: int, kind: StringName = &"") -> int:
	var count := 0
	for reservation: Dictionary in reservations:
		if int(reservation.track_id) == track_id and (kind.is_empty() or StringName(reservation.get("kind", INTERCEPTOR)) == kind):
			count += 1
	return count

func engagement_owner_ids(track_id: int) -> Array[int]:
	var result: Array[int] = []
	for reservation: Dictionary in reservations:
		if int(reservation.track_id) != track_id:
			continue
		var owner_id := int(reservation.owner_defense_id)
		if not result.has(owner_id):
			result.append(owner_id)
	return result

func capture_state() -> Dictionary:
	return {"reservations": reservations.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	reservations.clear()
	for reservation: Dictionary in state.get("reservations", []):
		reservations.append({
			"track_id": int(reservation.track_id),
			"owner_defense_id": int(reservation.owner_defense_id),
			"remaining": float(reservation.remaining),
			"kind": String(reservation.get("kind", INTERCEPTOR)),
		})
