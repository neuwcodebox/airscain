class_name EngagementDoctrine
extends RefCounted

var hold_fire: bool = false
var engage_unknown: bool = false
var engage_neutral: bool = false
var minimum_track_quality: float = 0.3
var minimum_classification_confidence: float = 0.25
var minimum_affiliation_confidence: float = 0.3
var priority_track_id: int = -1

func allows(track: PlayerTrack) -> bool:
	if hold_fire or track.state != PlayerTrack.State.CONFIRMED:
		return false
	if track.track_quality < minimum_track_quality:
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
