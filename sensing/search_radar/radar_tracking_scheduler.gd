class_name RadarTrackingScheduler
extends RefCounted

const MINIMUM_ACTION_SECONDS := 3.0
const SIGNAL_QUALITY_WEIGHT := 0.25
const CONTINUITY_BONUS := 0.2
const ACTIVE_ENGAGEMENT_BONUS := 1000.0
const CYCLING_SLOT_DIVISOR := 5

var sensor_id: int
var capacity: int

func setup(sensor_id_value: int, capacity_value: int) -> void:
	sensor_id = sensor_id_value
	capacity = capacity_value

func priority_for(
	threat: ThreatUnit,
	quality: float,
	was_tracked: bool,
	actively_engaged: bool,
) -> float:
	var expected_damage := 0.0
	var mission := threat.definition.mission_definition()
	if mission != null and threat.definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
		expected_damage = mission.damage
	var seconds := threat.presentation_action_seconds()
	var imminent_risk := expected_damage / maxf(MINIMUM_ACTION_SECONDS, seconds) if is_finite(seconds) else 0.0
	var continuity := CONTINUITY_BONUS if was_tracked else 0.0
	var engagement_support := ACTIVE_ENGAGEMENT_BONUS if actively_engaged else 0.0
	return imminent_risk + quality * SIGNAL_QUALITY_WEIGHT + continuity + engagement_support

func select(
	candidates: Array[RadarTrackCandidate],
	scan_index: int,
	support_counts: Dictionary[String, int] = {},
) -> Array[RadarTrackCandidate]:
	var candidates_by_support_count: Dictionary[int, Array] = {}
	for candidate: RadarTrackCandidate in candidates:
		var support_count := int(support_counts.get(candidate.key, 0))
		if not candidates_by_support_count.has(support_count):
			candidates_by_support_count[support_count] = []
		candidates_by_support_count[support_count].append(candidate)
	var support_levels: Array[int] = []
	support_levels.assign(candidates_by_support_count.keys())
	support_levels.sort()
	var selected: Array[RadarTrackCandidate] = []
	for support_count: int in support_levels:
		var ranked: Array[RadarTrackCandidate] = []
		ranked.assign(candidates_by_support_count[support_count])
		ranked.sort_custom(_ranks_before)
		var available_slots := capacity - selected.size()
		if ranked.size() <= available_slots:
			selected.append_array(ranked)
		else:
			selected.append_array(_select_from_stratum(ranked, available_slots, scan_index))
		if selected.size() >= capacity:
			break
	return selected

func _select_from_stratum(ranked: Array[RadarTrackCandidate], slots: int, scan_index: int) -> Array[RadarTrackCandidate]:
	var cycling_slots := slots / CYCLING_SLOT_DIVISOR
	var stable_slots := slots - cycling_slots
	var selected: Array[RadarTrackCandidate] = []
	selected.append_array(ranked.slice(0, stable_slots))
	if cycling_slots <= 0:
		return selected
	var remainder := ranked.slice(stable_slots)
	var start := posmod(scan_index * cycling_slots + sensor_id, remainder.size())
	for offset: int in mini(cycling_slots, remainder.size()):
		selected.append(remainder[(start + offset) % remainder.size()])
	return selected

func _ranks_before(first: RadarTrackCandidate, second: RadarTrackCandidate) -> bool:
	if not is_equal_approx(first.priority, second.priority):
		return first.priority > second.priority
	var first_order := _stable_contact_order(first.key)
	var second_order := _stable_contact_order(second.key)
	return first.key < second.key if first_order == second_order else first_order > second_order

func _stable_contact_order(key: String) -> int:
	return posmod(key.hash() ^ sensor_id * 1103515245, 1000)
