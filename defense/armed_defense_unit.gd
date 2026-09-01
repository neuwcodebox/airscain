class_name ArmedDefenseUnit
extends DefenseUnit

var battlefield: Battlefield
var player_knowledge: Node
var c2_network: Node
var engagement_coordinator: EngagementCoordinator
var doctrine := EngagementDoctrine.new()

func configure_player_knowledge(battlefield_value: Battlefield, player_knowledge_value: Node) -> void:
	battlefield = battlefield_value
	player_knowledge = player_knowledge_value

func configure_c2(network: Node) -> void:
	c2_network = network

func configure_engagements(coordinator: EngagementCoordinator) -> void:
	engagement_coordinator = coordinator

func c2_roles() -> int:
	return C2Role.DEFENSE

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
	return engagement_coordinator == null or engagement_coordinator.reservation_count(track.track_id) < maximum_concurrent

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
