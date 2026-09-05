class_name ArmedDefenseUnit
extends DefenseUnit

var battlefield: Battlefield
var player_knowledge: Node
var c2_network: Node
var engagement_coordinator: EngagementCoordinator
var doctrine := EngagementDoctrine.new()
var magazine := WeaponMagazine.new()

func configure_player_knowledge(battlefield_value: Battlefield, player_knowledge_value: Node) -> void:
	battlefield = battlefield_value
	player_knowledge = player_knowledge_value

func configure_c2(network: Node) -> void:
	c2_network = network

func configure_engagements(coordinator: EngagementCoordinator) -> void:
	engagement_coordinator = coordinator

func configure_support(manager: SupportManager) -> void:
	super.configure_support(manager)

func c2_roles() -> int:
	return C2Role.DEFENSE

func supports_engagement_controls() -> bool:
	return true

func engagement_hold_fire() -> bool:
	return doctrine.hold_fire

func engagement_engages_unknown() -> bool:
	return doctrine.engage_unknown

func set_hold_fire(enabled: bool) -> void:
	doctrine.hold_fire = enabled

func set_engage_unknown(enabled: bool) -> void:
	doctrine.engage_unknown = enabled

func set_priority_track(track_id: int) -> void:
	doctrine.priority_track_id = track_id

func available_tracks() -> Array[PlayerTrack]:
	if player_knowledge == null or c2_network == null:
		return []
	var known_tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	return c2_network.call("available_tracks_for", self, known_tracks)

func is_track_available_for_engagement(track: PlayerTrack, maximum_concurrent: int = 1) -> bool:
	return engagement_coordinator == null or definition.engagement_reservation_kind() == EngagementCoordinator.FIRE_SUPPORT or engagement_coordinator.reservation_count(track.track_id, EngagementCoordinator.INTERCEPTOR) < maximum_concurrent

func cooperative_target_score(track: PlayerTrack, protected_position: Vector3, target_match: float) -> float:
	var offset := track.estimated_position - protected_position
	var distance := maxf(1.0, offset.length())
	var closing_speed := maxf(0.0, -offset.dot(track.estimated_velocity) / distance)
	var score := track.track_quality * target_match * (1.0 + minf(closing_speed / 80.0, 2.0)) / distance
	if engagement_coordinator != null:
		var owners := engagement_coordinator.engagement_owner_ids(track.track_id)
		owners.erase(runtime_id)
		# Assignment is a preference, not an exclusive lock. A lone or urgent
		# threat can receive supporting fire from every eligible local weapon.
		score /= 1.0 + float(owners.size()) * 0.65
		if engagement_coordinator.fire_support_target(runtime_id) == track.track_id:
			score *= 1.25
	return score

func maintain_fire_support(track: PlayerTrack, can_supply: bool) -> bool:
	if engagement_coordinator == null:
		return false
	if track == null or not can_supply:
		engagement_coordinator.release_fire_support(runtime_id)
		return false
	return engagement_coordinator.reserve_fire_support(track.track_id, runtime_id)

func resource_status_text() -> String:
	if magazine.is_reloading():
		return _with_support_status("%s\n탄약 %d + %d · 재장전 %.1f초" % [operational_status_text(), magazine.rounds, magazine.reserve, magazine.reload_remaining])
	if magazine.is_depleted():
		return _with_support_status("%s\n탄약 고갈" % operational_status_text())
	return _with_support_status("%s\n탄약 %d + %d" % [operational_status_text(), magazine.rounds, magazine.reserve])

func selection_status_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if uses_ammunition():
		var ammunition := "%d + %d" % [magazine.rounds, magazine.reserve]
		if magazine.is_depleted():
			ammunition = "고갈"
		rows.append({"label": "탄약", "value": ammunition, "warning": magazine.is_depleted()})
		if magazine.is_reloading():
			rows.append({"label": "재장전", "value": "%.1f초" % magazine.reload_remaining})
	rows.append_array(_selection_task_rows())
	return rows

func uses_ammunition() -> bool:
	return false

func resupply_work() -> float:
	return 1.0

func resupply_cost() -> int:
	return 0

func can_request_resupply() -> bool:
	return uses_ammunition() and support_manager != null and ammunition_needs_resupply() and support_manager.task_status(self).is_empty() and support_manager.can_service(self)

func request_resupply() -> bool:
	return support_manager != null and support_manager.request_resupply(self)

func ammunition_needs_resupply() -> bool:
	return magazine.reserve < magazine.reserve_capacity

func ammunition_reserve_ratio() -> float:
	return float(magazine.reserve) / maxf(1.0, float(magazine.reserve_capacity))

func combat_resource_low() -> bool:
	return uses_ammunition() and ammunition_reserve_ratio() <= 0.2

func combat_resource_depleted() -> bool:
	return uses_ammunition() and magazine.is_depleted()

func critical_status_text() -> String:
	var operational_status := super.critical_status_text()
	if not operational_status.is_empty():
		return operational_status
	if combat_resource_depleted():
		return "탄약 고갈"
	return ""

func complete_resupply() -> void:
	magazine.refill_reserve()

func _with_support_status(ammunition_status: String) -> String:
	var statuses: Array[String] = []
	if support_manager != null and not support_manager.task_status(self).is_empty():
		statuses.append(support_manager.task_status(self))
	if relocation_manager != null and not relocation_manager.task_status(self).is_empty():
		statuses.append(relocation_manager.task_status(self))
	return ammunition_status if statuses.is_empty() else "%s · %s" % [ammunition_status, " · ".join(statuses)]

func capture_doctrine_state() -> Dictionary:
	return {
		"hold_fire": doctrine.hold_fire,
		"engage_unknown": doctrine.engage_unknown,
		"engage_neutral": doctrine.engage_neutral,
		"minimum_track_quality": doctrine.minimum_track_quality,
		"minimum_classification_confidence": doctrine.minimum_classification_confidence,
		"minimum_affiliation_confidence": doctrine.minimum_affiliation_confidence,
		"priority_track_id": doctrine.priority_track_id,
	}

func restore_doctrine_state(state: Dictionary) -> void:
	doctrine.hold_fire = bool(state.get("hold_fire", false))
	doctrine.engage_unknown = bool(state.get("engage_unknown", false))
	doctrine.engage_neutral = bool(state.get("engage_neutral", false))
	doctrine.minimum_track_quality = float(state.get("minimum_track_quality", 0.3))
	doctrine.minimum_classification_confidence = float(state.get("minimum_classification_confidence", 0.25))
	doctrine.minimum_affiliation_confidence = float(state.get("minimum_affiliation_confidence", 0.3))
	doctrine.priority_track_id = int(state.get("priority_track_id", -1))
