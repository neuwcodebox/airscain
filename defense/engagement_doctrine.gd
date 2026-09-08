class_name EngagementDoctrine
extends RefCounted

var hold_fire: bool = false
var engage_unknown: bool = false
var engage_neutral: bool = false
var minimum_track_quality: float = 0.3
var minimum_classification_confidence: float = 0.25
var minimum_affiliation_confidence: float = 0.3
const TARGET_KINDS: Array[StringName] = [&"small_uav", &"uav", &"aircraft", &"cruise_missile", &"rocket", &"ballistic_missile"]
const TARGET_LABELS: Array[String] = ["소형 무인기", "무인기", "항공기", "순항·유도미사일", "로켓", "탄도미사일"]
var excluded_target_kinds: Array[StringName] = []

static func target_kind(classification: StringName) -> StringName:
	match classification:
		&"strike_aircraft": return &"aircraft"
		&"large_uav", &"strike_uav", &"recon_uav": return &"uav"
		&"missile": return &"cruise_missile"
	return classification

func allows_target_kind(kind: StringName) -> bool:
	return not excluded_target_kinds.has(target_kind(kind))

func set_target_kind_allowed(kind: StringName, enabled: bool) -> void:
	kind = target_kind(kind)
	if not TARGET_KINDS.has(kind):
		return
	excluded_target_kinds.erase(kind)
	if not enabled:
		excluded_target_kinds.append(kind)

func allows(track: PlayerTrack) -> bool:
	if hold_fire or track.state != PlayerTrack.State.CONFIRMED:
		return false
	if track.track_quality < minimum_track_quality:
		return false
	if not allows_target_kind(track.classification):
		return false
	if track.classification_confidence < minimum_classification_confidence:
		return engage_unknown
	if track.affiliation_confidence < minimum_affiliation_confidence:
		return engage_unknown
	match track.affiliation:
		PlayerTrack.Affiliation.HOSTILE:
			return true
		PlayerTrack.Affiliation.NEUTRAL:
			return engage_neutral
		PlayerTrack.Affiliation.UNKNOWN:
			return engage_unknown
		_:
			return false
