class_name RaidPlanner
extends RefCounted

const PATTERNS: Array[StringName] = [&"concentration", &"diversion", &"layered", &"suppression"]
const MAX_GROUPS := 6
const MAX_AUXILIARY_GROUPS := 2
const RECENT_DEFINITION_WEIGHT := 0.45
var last_pattern: StringName
var recent_definition_ids: Array[StringName] = []

# Only content, observed weights and the operation RNG enter this planner.
# No live defense objects, magazines, C2 graph or player tracks are available.
func generate(request: RaidPlanRequest) -> Array[Dictionary]:
	var scenario := request.scenario
	var weights := request.weights
	var budget := request.budget
	var level := request.level
	var angle := request.angle
	var max_delay := request.max_delay
	var rng := request.rng
	var entries: Array[ThreatSpawnEntry] = []
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if entry.unlock_level <= level and _cost(entry) <= budget and weights.get(entry.threat_definition.id, 0.0) > 0.0:
			entries.append(entry)
	var strikes := _strikes(entries)
	if strikes.is_empty():
		return []
	var candidates: Array[Dictionary] = []
	for pattern: StringName in PATTERNS:
		var pairs: Array[Dictionary] = []
		if pattern != &"concentration":
			for lead: ThreatSpawnEntry in entries:
				for strike: ThreatSpawnEntry in strikes:
					if _cost(lead) + _cost(strike) > budget or not _matches_pair(pattern, lead, strike):
						continue
					var gap := rng.randf_range(0.0, 2.0) if pattern == &"layered" else (rng.randf_range(6.0, 12.0) if pattern == &"diversion" else rng.randf_range(10.0, 18.0))
					if pattern == &"suppression" and lead.threat_definition.jamming_strength > 0.0:
						gap = rng.randf_range(2.0, 5.0)
					var delays := _pair_delays(_eta(lead, request), _eta(strike, request), gap)
					if maxf(delays.x, delays.y) <= max_delay:
						pairs.append({"lead": lead, "strike": strike, "delays": delays, "weight": _entry_weight(lead, weights) * _entry_weight(strike, weights)})
			if pairs.is_empty():
				continue
		var weight := 1.0 if pattern == &"concentration" else 0.85
		if pattern == last_pattern:
			weight *= 0.18
		candidates.append({"pattern": pattern, "pairs": pairs, "weight": weight})
	var selected := _weighted_dictionary(candidates, rng)
	# Eligible pairs already satisfy observation weights, budget and arrival limits.
	var asset_pairs: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if candidate.pattern != &"suppression":
			continue
		for pair: Dictionary in candidate.pairs:
			var mission := (pair.lead as ThreatSpawnEntry).threat_definition.mission_definition()
			var has_planned_target := request.suppression_targets.is_empty() or not _target_options(pair.lead, request.suppression_targets).is_empty()
			if mission != null and mission.target_role != ThreatMissionDefinition.TargetRole.CITY and (pair.lead as ThreatSpawnEntry).threat_definition.jamming_strength <= 0.0 and has_planned_target:
				asset_pairs.append(pair)
	var priority_chance := request.suppression_priority_chance if request.suppression_priority_chance >= 0.0 else (scenario.asset_suppression_chance if level >= 4 else 0.0)
	if not asset_pairs.is_empty() and rng.randf() < priority_chance:
		selected = {"pattern": &"suppression", "pairs": asset_pairs, "weight": 1.0}
	last_pattern = selected.pattern
	if last_pattern == &"suppression" and not request.suppression_targets.is_empty():
		var package := _suppression_package(entries, strikes, request)
		if not package.is_empty():
			_remember_definitions(package)
			return package
	var waves: Array[Dictionary] = []
	var spent := 0.0
	var anchor_delay := 0.0
	var anchor_eta := 0.0
	if last_pattern == &"concentration":
		var primary := _pick_entry(strikes, weights, budget, rng)
		waves.append(_wave(primary, 0.0, angle))
		spent = _cost(primary)
		anchor_eta = _eta(primary, request)
	else:
		var pair := _weighted_dictionary(selected.pairs, rng)
		var lead: ThreatSpawnEntry = pair.lead
		var strike: ThreatSpawnEntry = pair.strike
		var delays: Vector2 = pair.delays
		var lead_angle := angle
		if last_pattern == &"diversion":
			lead_angle += rng.randf_range(PI * 0.5, PI * 0.9) * (-1.0 if rng.randf() < 0.5 else 1.0)
		elif last_pattern == &"layered":
			lead_angle += rng.randf_range(-0.45, 0.45)
		waves.append(_wave(lead, delays.x, lead_angle))
		waves.append(_wave(strike, delays.y, angle))
		spent = _cost(lead) + _cost(strike)
		anchor_delay = delays.y
		anchor_eta = _eta(strike, request)
		if last_pattern == &"suppression" and waves.size() - 1 < MAX_AUXILIARY_GROUPS:
			var complement := _complementary_support(entries, lead, budget - spent, anchor_delay, anchor_eta, request)
			if not complement.is_empty():
				var shift := float(complement.shift)
				var can_shift := waves.all(func(wave: Dictionary) -> bool: return float(wave.remaining) + shift <= max_delay)
				if can_shift:
					if shift > 0.0:
						for wave: Dictionary in waves:
							wave.remaining = float(wave.remaining) + shift
						anchor_delay += shift
					waves.append(complement.wave)
					spent += _cost(complement.entry)
	# Fill around the main effort, with at most one optional scout/decoy.
	var auxiliary_groups := 0 if last_pattern == &"concentration" else waves.size() - 1
	if auxiliary_groups == 0 and asset_pairs.is_empty() and level >= 2 and rng.randf() < 0.5:
		var scouts: Array[ThreatSpawnEntry] = []
		for entry: ThreatSpawnEntry in entries:
			if entry.raid_role == ThreatSpawnEntry.RaidRole.RECON:
				scouts.append(entry)
		var scout := _pick_entry(scouts, weights, budget - spent, rng)
		if scout != null:
			waves.append(_wave(scout, 0.0, angle + 0.3))
			spent += _cost(scout)
			auxiliary_groups += 1
	while waves.size() < MAX_GROUPS:
		var pool: Array[ThreatSpawnEntry] = []
		for entry: ThreatSpawnEntry in entries:
			var desired_delay := anchor_delay + anchor_eta - _eta(entry, request)
			if desired_delay < 0.0 or desired_delay > max_delay:
				continue
			if entry.raid_role == ThreatSpawnEntry.RaidRole.STRIKE or auxiliary_groups == 0 and entry.raid_role in [ThreatSpawnEntry.RaidRole.RECON, ThreatSpawnEntry.RaidRole.DECEPTION]:
				pool.append(entry)
		var extra := _pick_entry(pool, weights, budget - spent, rng)
		if extra == null:
			break
		var delay := minf(anchor_delay + anchor_eta - _eta(extra, request) + rng.randf_range(0.0, 3.0), max_delay)
		waves.append(_wave(extra, delay, angle + rng.randf_range(-0.18, 0.18)))
		spent += _cost(extra)
		auxiliary_groups += int(extra.raid_role != ThreatSpawnEntry.RaidRole.STRIKE)
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.remaining) < float(b.remaining))
	_remember_definitions(waves)
	return waves

func _suppression_package(entries: Array[ThreatSpawnEntry], strikes: Array[ThreatSpawnEntry], request: RaidPlanRequest) -> Array[Dictionary]:
	var city := _pick_entry(strikes, request.weights, request.budget, request.rng)
	if city == null:
		return []
	var spent := _cost(city)
	var desired_direct := 2 if request.level < 10 else (3 if request.level < 20 else 4)
	var distinct_limit := 1 if request.level < 10 else (2 if request.level < 20 else 3)
	var planned_counts: Dictionary[int, int] = {}
	var components: Array[Dictionary] = []
	for direct_index: int in desired_direct:
		var choices := _direct_suppression_choices(entries, request.weights, request.budget - spent, request.suppression_targets, planned_counts, distinct_limit)
		if choices.is_empty():
			break
		var choice := _weighted_dictionary(choices, request.rng)
		var entry: ThreatSpawnEntry = choice.entry
		var estimate: Dictionary = choice.estimate
		components.append({"entry": entry, "estimate": estimate, "kind": &"direct", "arrival_offset": request.rng.randf_range(0.0, 2.0)})
		spent += _cost(entry)
		var target_id := int(estimate.asset_id)
		planned_counts[target_id] = planned_counts.get(target_id, 0) + 1
	if components.is_empty():
		return []
	if components.size() + 1 < MAX_GROUPS:
		var support_choices := _suppression_support_choices(entries, request.weights, request.budget - spent, request.suppression_targets)
		if not support_choices.is_empty():
			var support := _weighted_dictionary(support_choices, request.rng)
			var support_entry: ThreatSpawnEntry = support.entry
			var is_deception := support_entry.raid_role == ThreatSpawnEntry.RaidRole.DECEPTION
			components.append({
				"entry": support_entry,
				"estimate": support.estimate,
				"kind": &"deception" if is_deception else &"jamming",
				"arrival_offset": -request.rng.randf_range(4.0, 8.0) if is_deception else -request.rng.randf_range(2.0, 5.0),
			})
			spent += _cost(support_entry)
	components.append({"entry": city, "estimate": {}, "kind": &"city", "arrival_offset": request.rng.randf_range(6.0, 10.0)})
	var base_arrival := 0.0
	for component: Dictionary in components:
		var eta := _component_eta(component.entry, component.estimate, request)
		component.eta = eta
		base_arrival = maxf(base_arrival, eta - float(component.arrival_offset))
	var waves: Array[Dictionary] = []
	for component: Dictionary in components:
		var delay := base_arrival + float(component.arrival_offset) - float(component.eta)
		if delay < 0.0 or delay > request.max_delay:
			return []
		var wave_angle := request.angle + request.rng.randf_range(-0.18, 0.18)
		if component.kind == &"deception":
			wave_angle = request.angle + request.rng.randf_range(PI * 0.5, PI * 0.9) * (-1.0 if request.rng.randf() < 0.5 else 1.0)
		waves.append(_wave(component.entry, delay, wave_angle, component.estimate))
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.remaining) < float(b.remaining))
	return waves

func _direct_suppression_choices(entries: Array[ThreatSpawnEntry], weights: Dictionary[StringName, float], budget: float, suppression_targets: Dictionary, planned_counts: Dictionary[int, int], distinct_limit: int) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var new_target_choices: Array[Dictionary] = []
	for entry: ThreatSpawnEntry in entries:
		if not _is_direct_suppression(entry) or _cost(entry) > budget:
			continue
		for estimate: Dictionary in _target_options(entry, suppression_targets):
			var target_id := int(estimate.asset_id)
			var planned: int = planned_counts.get(target_id, 0)
			if int(estimate.get("assigned", 0)) + planned >= 2:
				continue
			var choice: Dictionary = {"entry": entry, "estimate": estimate, "weight": _entry_weight(entry, weights) * float(estimate.get("confidence", 0.0)) / (1.0 + 4.0 * planned)}
			choices.append(choice)
			if planned == 0:
				new_target_choices.append(choice)
	if planned_counts.size() < distinct_limit and not new_target_choices.is_empty():
		return new_target_choices
	return choices

func _suppression_support_choices(entries: Array[ThreatSpawnEntry], weights: Dictionary[StringName, float], budget: float, suppression_targets: Dictionary) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for entry: ThreatSpawnEntry in entries:
		if _cost(entry) > budget:
			continue
		if entry.raid_role == ThreatSpawnEntry.RaidRole.DECEPTION:
			choices.append({"entry": entry, "estimate": {}, "weight": _entry_weight(entry, weights)})
		elif entry.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION and entry.threat_definition.jamming_strength > 0.0:
			for estimate: Dictionary in _target_options(entry, suppression_targets):
				choices.append({"entry": entry, "estimate": estimate, "weight": _entry_weight(entry, weights) * float(estimate.get("confidence", 0.0))})
	return choices

func _is_direct_suppression(entry: ThreatSpawnEntry) -> bool:
	if entry.raid_role != ThreatSpawnEntry.RaidRole.SUPPRESSION or entry.threat_definition.jamming_strength > 0.0:
		return false
	var mission := entry.threat_definition.mission_definition()
	return mission != null and mission.target_role != ThreatMissionDefinition.TargetRole.CITY

func _target_options(entry: ThreatSpawnEntry, suppression_targets: Dictionary) -> Array:
	return suppression_targets.get(entry.threat_definition.id, []) as Array

func _component_eta(entry: ThreatSpawnEntry, estimate: Dictionary, request: RaidPlanRequest) -> float:
	if estimate.is_empty():
		return _eta(entry, request)
	var radius := request.scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier()
	var spawn := Vector2(cos(request.angle) * radius, sin(request.angle) * radius)
	var position := SaveDocument.vector3_from_data(estimate.estimated_position)
	var mission := entry.threat_definition.mission_definition()
	var distance := spawn.distance_to(Vector2(position.x, position.z)) - (mission.action_distance if mission != null else 0.0)
	return entry.threat_definition.estimated_approach_seconds(maxf(0.0, distance), request.speed)

func _matches_pair(pattern: StringName, lead: ThreatSpawnEntry, strike: ThreatSpawnEntry) -> bool:
	match pattern:
		&"diversion":
			return lead.raid_role == ThreatSpawnEntry.RaidRole.DECEPTION
		&"layered":
			return lead.raid_role == ThreatSpawnEntry.RaidRole.STRIKE and lead.attack_layer != strike.attack_layer
		&"suppression":
			return lead.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION
	return false

func _complementary_support(entries: Array[ThreatSpawnEntry], lead: ThreatSpawnEntry, budget: float, anchor_delay: float, anchor_eta: float, request: RaidPlanRequest) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var lead_is_jammer := lead.threat_definition.jamming_strength > 0.0
	for entry: ThreatSpawnEntry in entries:
		if entry == lead or _cost(entry) > budget:
			continue
		var is_deception := entry.raid_role == ThreatSpawnEntry.RaidRole.DECEPTION
		var is_jammer := entry.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION and entry.threat_definition.jamming_strength > 0.0
		var mission := entry.threat_definition.mission_definition()
		var is_direct_suppression := entry.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION and mission != null and mission.target_role != ThreatMissionDefinition.TargetRole.CITY
		if lead_is_jammer and not is_direct_suppression or not lead_is_jammer and not (is_jammer or is_deception):
			continue
		var gap := request.rng.randf_range(6.0, 12.0) if is_deception else (request.rng.randf_range(2.0, 5.0) if is_jammer else request.rng.randf_range(10.0, 18.0))
		var delay := anchor_delay + anchor_eta - gap - _eta(entry, request)
		var shift := maxf(0.0, -delay)
		delay += shift
		if delay > request.max_delay or anchor_delay + shift > request.max_delay:
			continue
		var entry_angle := request.angle
		if is_deception:
			entry_angle += request.rng.randf_range(PI * 0.5, PI * 0.9) * (-1.0 if request.rng.randf() < 0.5 else 1.0)
		candidates.append({"entry": entry, "wave": _wave(entry, delay, entry_angle), "shift": shift, "weight": _entry_weight(entry, request.weights)})
	if candidates.is_empty():
		return {}
	return _weighted_dictionary(candidates, request.rng)

func _strikes(entries: Array[ThreatSpawnEntry]) -> Array[ThreatSpawnEntry]:
	var result: Array[ThreatSpawnEntry] = []
	for entry: ThreatSpawnEntry in entries:
		if entry.raid_role == ThreatSpawnEntry.RaidRole.STRIKE:
			result.append(entry)
	return result

func _pick_entry(entries: Array[ThreatSpawnEntry], weights: Dictionary[StringName, float], budget: float, rng: RandomNumberGenerator) -> ThreatSpawnEntry:
	var candidates: Array[Dictionary] = []
	for entry: ThreatSpawnEntry in entries:
		if _cost(entry) <= budget:
			candidates.append({"entry": entry, "weight": _entry_weight(entry, weights)})
	return null if candidates.is_empty() else _weighted_dictionary(candidates, rng).entry as ThreatSpawnEntry

func _entry_weight(entry: ThreatSpawnEntry, weights: Dictionary[StringName, float]) -> float:
	var weight := float(weights.get(entry.threat_definition.id, 0.0))
	return weight * RECENT_DEFINITION_WEIGHT if recent_definition_ids.has(entry.threat_definition.id) else weight

func _remember_definitions(waves: Array[Dictionary]) -> void:
	recent_definition_ids.clear()
	for wave: Dictionary in waves:
		var definition_id := StringName(String(wave.definition_id))
		if not recent_definition_ids.has(definition_id):
			recent_definition_ids.append(definition_id)

func capture_recent_definitions() -> Array[String]:
	var result: Array[String] = []
	for definition_id: StringName in recent_definition_ids:
		result.append(String(definition_id))
	return result

func restore_recent_definitions(values: Array) -> void:
	recent_definition_ids.clear()
	for value: Variant in values:
		recent_definition_ids.append(StringName(String(value)))

func _weighted_dictionary(candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for candidate: Dictionary in candidates:
		total += float(candidate.weight)
	var roll := rng.randf() * total
	for candidate: Dictionary in candidates:
		roll -= float(candidate.weight)
		if roll < 0.0:
			return candidate
	return candidates.back()

func _pair_delays(lead_eta: float, strike_eta: float, arrival_gap: float) -> Vector2:
	var lead_arrival := maxf(lead_eta, strike_eta - arrival_gap)
	return Vector2(lead_arrival - lead_eta, lead_arrival + arrival_gap - strike_eta)

func _eta(entry: ThreatSpawnEntry, request: RaidPlanRequest) -> float:
	var scenario := request.scenario
	var distance := float(request.travel_distances.get(entry.threat_definition.id, scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier() - (scenario.city_size * 0.5 + 260.0)))
	return entry.threat_definition.estimated_approach_seconds(distance, request.speed)

func _wave(entry: ThreatSpawnEntry, delay: float, angle: float, estimate: Dictionary = {}) -> Dictionary:
	var wave := {"definition_id": String(entry.threat_definition.id), "remaining": delay, "angle": fposmod(angle, TAU)}
	if not estimate.is_empty():
		wave["target_asset_id"] = int(estimate.asset_id)
		wave["target_role"] = String(estimate.role)
		wave["target_position"] = estimate.estimated_position.duplicate()
		wave["target_confidence"] = float(estimate.confidence)
		wave["target_observed_at"] = float(estimate.observed_at)
	return wave

func _cost(entry: ThreatSpawnEntry) -> float:
	return entry.threat_cost * float(entry.group_size)
