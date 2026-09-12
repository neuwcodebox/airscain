class_name RaidPlanner
extends RefCounted

const PATTERNS: Array[StringName] = [&"concentration", &"diversion", &"layered", &"suppression"]
const MAX_GROUPS := 6
const MAX_AUXILIARY_GROUPS := 2
var last_pattern: StringName

# Only content, observed weights and the operation RNG enter this planner.
# No live defense objects, magazines, C2 graph or player tracks are available.
func generate(scenario: ScenarioDefinition, weights: Dictionary[StringName, float], budget: float, level: int, angle: float, max_delay: float, speed: float, rng: RandomNumberGenerator, travel_distances: Dictionary[StringName, float] = {}, suppression_priority_chance: float = -1.0) -> Array[Dictionary]:
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
					var delays := _pair_delays(_eta(lead, scenario, speed, travel_distances), _eta(strike, scenario, speed, travel_distances), gap)
					if maxf(delays.x, delays.y) <= max_delay:
						pairs.append({"lead": lead, "strike": strike, "delays": delays, "weight": weights[lead.threat_definition.id] * weights[strike.threat_definition.id]})
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
			if mission != null and mission.target_role != ThreatMissionDefinition.TargetRole.CITY:
				asset_pairs.append(pair)
	var priority_chance := suppression_priority_chance if suppression_priority_chance >= 0.0 else (scenario.asset_suppression_chance if level >= 4 else 0.0)
	if not asset_pairs.is_empty() and rng.randf() < priority_chance:
		selected = {"pattern": &"suppression", "pairs": asset_pairs, "weight": 1.0}
	last_pattern = selected.pattern
	var waves: Array[Dictionary] = []
	var spent := 0.0
	var anchor_delay := 0.0
	var anchor_eta := 0.0
	if last_pattern == &"concentration":
		var primary := _pick_entry(strikes, weights, budget, rng)
		waves.append(_wave(primary, 0.0, angle))
		spent = _cost(primary)
		anchor_eta = _eta(primary, scenario, speed, travel_distances)
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
		anchor_eta = _eta(strike, scenario, speed, travel_distances)
		if last_pattern == &"suppression" and waves.size() - 1 < MAX_AUXILIARY_GROUPS:
			var complement := _complementary_support(entries, lead, weights, budget - spent, anchor_delay, anchor_eta, scenario, speed, max_delay, angle, rng, travel_distances)
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
			var desired_delay := anchor_delay + anchor_eta - _eta(entry, scenario, speed, travel_distances)
			if desired_delay < 0.0 or desired_delay > max_delay:
				continue
			if entry.raid_role == ThreatSpawnEntry.RaidRole.STRIKE or auxiliary_groups == 0 and entry.raid_role in [ThreatSpawnEntry.RaidRole.RECON, ThreatSpawnEntry.RaidRole.DECEPTION]:
				pool.append(entry)
		var extra := _pick_entry(pool, weights, budget - spent, rng)
		if extra == null:
			break
		var delay := minf(anchor_delay + anchor_eta - _eta(extra, scenario, speed, travel_distances) + rng.randf_range(0.0, 3.0), max_delay)
		waves.append(_wave(extra, delay, angle + rng.randf_range(-0.18, 0.18)))
		spent += _cost(extra)
		auxiliary_groups += int(extra.raid_role != ThreatSpawnEntry.RaidRole.STRIKE)
	waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.remaining) < float(b.remaining))
	return waves

func _matches_pair(pattern: StringName, lead: ThreatSpawnEntry, strike: ThreatSpawnEntry) -> bool:
	match pattern:
		&"diversion":
			return lead.raid_role == ThreatSpawnEntry.RaidRole.DECEPTION
		&"layered":
			return lead.raid_role == ThreatSpawnEntry.RaidRole.STRIKE and lead.attack_layer != strike.attack_layer
		&"suppression":
			return lead.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION
	return false

func _complementary_support(entries: Array[ThreatSpawnEntry], lead: ThreatSpawnEntry, weights: Dictionary[StringName, float], budget: float, anchor_delay: float, anchor_eta: float, scenario: ScenarioDefinition, speed: float, max_delay: float, angle: float, rng: RandomNumberGenerator, travel_distances: Dictionary[StringName, float]) -> Dictionary:
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
		var gap := rng.randf_range(6.0, 12.0) if is_deception else (rng.randf_range(2.0, 5.0) if is_jammer else rng.randf_range(10.0, 18.0))
		var delay := anchor_delay + anchor_eta - gap - _eta(entry, scenario, speed, travel_distances)
		var shift := maxf(0.0, -delay)
		delay += shift
		if delay > max_delay or anchor_delay + shift > max_delay:
			continue
		var entry_angle := angle
		if is_deception:
			entry_angle += rng.randf_range(PI * 0.5, PI * 0.9) * (-1.0 if rng.randf() < 0.5 else 1.0)
		candidates.append({"entry": entry, "wave": _wave(entry, delay, entry_angle), "shift": shift, "weight": weights[entry.threat_definition.id]})
	if candidates.is_empty():
		return {}
	return _weighted_dictionary(candidates, rng)

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
			candidates.append({"entry": entry, "weight": weights[entry.threat_definition.id]})
	return null if candidates.is_empty() else _weighted_dictionary(candidates, rng).entry as ThreatSpawnEntry

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

func _eta(entry: ThreatSpawnEntry, scenario: ScenarioDefinition, speed: float, travel_distances: Dictionary[StringName, float] = {}) -> float:
	var distance := float(travel_distances.get(entry.threat_definition.id, scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier() - (scenario.city_size * 0.5 + 260.0)))
	return entry.threat_definition.estimated_approach_seconds(distance, speed)

func _wave(entry: ThreatSpawnEntry, delay: float, angle: float) -> Dictionary:
	return {"definition_id": String(entry.threat_definition.id), "remaining": delay, "angle": fposmod(angle, TAU)}

func _cost(entry: ThreatSpawnEntry) -> float:
	return entry.threat_cost * float(entry.group_size)
