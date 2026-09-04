class_name ThreatDirector
extends Node

signal pressure_changed(level: int)
signal threat_spawned(threat: ThreatUnit)
signal recovery_started(completed_window: int)

var scenario: ScenarioDefinition
var battlefield: Battlefield
var objective: ProtectedObjective
var registry: ThreatRegistry
var threat_parent: Node3D
var defense_parent: Node3D
var enemy_knowledge: EnemyKnowledge
var rng := RandomNumberGenerator.new()
var elapsed: float = 0.0
var until_spawn: float = 0.0
var pressure_level: int = 1
var next_runtime_id: int = 1
var enabled: bool = false
var pending_waves: Array[Dictionary] = []
var in_recovery: bool = false
var completed_attack_windows: int = 0

func configure(scenario_value: ScenarioDefinition, battlefield_value: Battlefield, objective_value: ProtectedObjective, registry_value: ThreatRegistry, threat_parent_value: Node3D, defense_parent_value: Node3D, enemy_knowledge_value: EnemyKnowledge) -> void:
	scenario = scenario_value
	battlefield = battlefield_value
	objective = objective_value
	registry = registry_value
	threat_parent = threat_parent_value
	defense_parent = defense_parent_value
	enemy_knowledge = enemy_knowledge_value
	rng.seed = scenario.world_seed ^ 0x6E624EB7
	reset()

func reset() -> void:
	elapsed = 0.0
	until_spawn = scenario.initial_spawn_interval if scenario != null else 4.0
	pressure_level = 1
	next_runtime_id = 1
	enabled = false
	pending_waves.clear()
	in_recovery = false
	completed_attack_windows = 0
	pressure_changed.emit(pressure_level)

func gameplay_tick(delta: float) -> void:
	if not enabled:
		return
	elapsed += delta
	_tick_pending_waves(delta)
	var new_level := pressure_level_at(elapsed)
	if new_level != pressure_level:
		pressure_level = new_level
		pressure_changed.emit(pressure_level)
	var cycle_duration := scenario.attack_window_duration + scenario.recovery_duration
	var should_recover := fmod(elapsed, cycle_duration) >= scenario.attack_window_duration
	if should_recover != in_recovery:
		in_recovery = should_recover
		if in_recovery:
			completed_attack_windows += 1
			recovery_started.emit(completed_attack_windows)
		else:
			until_spawn = maxf(until_spawn, scenario.initial_spawn_interval)
	if in_recovery:
		return
	until_spawn -= delta
	if until_spawn > 0.0:
		return
	until_spawn += raid_interval_at(elapsed)
	launch_budgeted_raid()

func schedule_archetype(archetype: RaidArchetypeDefinition, approach_angle: float) -> void:
	for index: int in archetype.phase_entries.size():
		pending_waves.append({"definition_id": String(archetype.phase_entries[index].threat_definition.id), "remaining": archetype.phase_delays[index], "angle": approach_angle})

func _tick_pending_waves(delta: float) -> void:
	for index: int in range(pending_waves.size() - 1, -1, -1):
		var wave := pending_waves[index]
		wave.remaining = float(wave.remaining) - delta
		pending_waves[index] = wave
		if float(wave.remaining) > 0.0:
			continue
		var entry := _entry_for_definition(StringName(String(wave.definition_id)))
		if entry != null:
			_spawn_group(entry, float(wave.angle))
		pending_waves.remove_at(index)

func _spawn_group(entry: ThreatSpawnEntry, group_angle: float) -> void:
	var group_target: Variant = null
	if entry.threat_definition.shares_city_impact_target():
		group_target = battlefield.random_city_building_target(rng)
	for group_index: int in entry.group_size:
		if registry.hostile_count() >= scenario.active_threat_cap:
			return
		_spawn_entry(entry, group_angle + rng.randf_range(-0.035, 0.035), float(group_index) * 3.0, group_target)

func pressure_level_at(time_seconds: float) -> int:
	return 1 + int(floor(time_seconds / scenario.pressure_step_duration))

func spawn_interval_at(time_seconds: float) -> float:
	return raid_interval_at(time_seconds)

func raid_interval_at(time_seconds: float) -> float:
	var completed_pressure_steps := float(pressure_level_at(time_seconds) - 1)
	return maxf(scenario.minimum_raid_interval, scenario.initial_raid_interval - completed_pressure_steps * scenario.raid_interval_pressure_reduction)

func threat_budget_at(time_seconds: float) -> float:
	return 3.0 + float(pressure_level_at(time_seconds)) + performance_budget_adjustment()

func performance_budget_adjustment() -> float:
	if enemy_knowledge == null or enemy_knowledge.recent_outcomes.size() < 4:
		return 0.0
	return clampf((recent_neutralization_rate() - 0.5) * 4.0, -1.0, 1.0)

func speed_multiplier_at(time_seconds: float) -> float:
	return minf(scenario.maximum_speed_multiplier, 1.0 + time_seconds / scenario.speed_growth_duration)

func launch_budgeted_raid() -> void:
	var budget := threat_budget_at(elapsed)
	var approach_angle := adaptive_approach_angle()
	var archetype := _choose_archetype()
	if archetype != null and archetype.total_cost() <= budget and rng.randf() < 0.45:
		schedule_archetype(archetype, approach_angle)
		budget -= archetype.total_cost()
	var scheduled_count := 0
	while budget > 0.0 and scheduled_count < 6:
		var entry := _choose_entry_for_budget(budget)
		if entry == null:
			break
		var cost := entry.threat_cost * float(entry.group_size)
		pending_waves.append({"definition_id": String(entry.threat_definition.id), "remaining": rng.randf_range(0.0, 2.0), "angle": approach_angle + rng.randf_range(-0.18, 0.18)})
		budget -= cost
		scheduled_count += 1

func adaptive_approach_angle() -> float:
	var known_angles: Array[float] = []
	if enemy_knowledge == null:
		return rng.randf_range(0.0, TAU)
	for estimate: Dictionary in enemy_knowledge.estimates.values():
		if float(estimate.confidence) < 0.2:
			continue
		var position := SaveDocument.vector3_from_data(estimate.estimated_position)
		known_angles.append(fposmod(atan2(position.z - objective.global_position.z, position.x - objective.global_position.x), TAU))
	if known_angles.is_empty():
		return rng.randf_range(0.0, TAU)
	known_angles.sort()
	var best_start := known_angles[0]
	var best_gap := -1.0
	for index: int in known_angles.size():
		var start := known_angles[index]
		var finish := known_angles[(index + 1) % known_angles.size()] + (TAU if index == known_angles.size() - 1 else 0.0)
		if finish - start > best_gap:
			best_gap = finish - start
			best_start = start
	return fposmod(best_start + best_gap * 0.5, TAU)

func spawn_one() -> ThreatUnit:
	var entry := _choose_entry()
	if entry == null:
		return null
	return _spawn_entry(entry, rng.randf_range(0.0, TAU), 0.0)

func _spawn_entry(entry: ThreatSpawnEntry, angle: float, edge_offset: float, target_override: Variant = null) -> ThreatUnit:
	var threat := entry.threat_definition.scene.instantiate() as ThreatUnit
	if threat == null:
		return null
	threat_parent.add_child(threat)
	var edge := scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier() - edge_offset
	var spawn_position := Vector3(cos(angle) * edge, 0.0, sin(angle) * edge)
	spawn_position.y = battlefield.flight_surface_height(spawn_position.x, spawn_position.z) + entry.threat_definition.spawn_altitude()
	threat.global_position = spawn_position
	threat.setup(next_runtime_id, entry.threat_definition)
	threat.configure_enemy_knowledge(enemy_knowledge)
	next_runtime_id += 1
	var target := objective.get_target_point(rng)
	var target_asset: DefenseUnit
	var mission := entry.threat_definition.mission_definition()
	var targets_city := entry.threat_definition.shares_city_impact_target()
	if mission != null:
		if targets_city:
			target = battlefield.random_city_building_target(rng)
		if entry.threat_definition.requires_role_knowledge:
			target_asset = _known_target_for_role(entry.threat_definition.adaptive_knowledge_role)
		else:
			target_asset = choose_target_for(mission)
	if target_override is Vector3:
		target = target_override
		target_asset = null
	elif target_asset != null:
		target = target_asset.global_position
	elif not targets_city:
		target.y = battlefield.terrain_height(target.x, target.z)
	threat.configure_mission(objective, battlefield, target, speed_multiplier_at(elapsed), target_asset, spawn_position)
	registry.add(threat)
	threat_spawned.emit(threat)
	return threat

func choose_target_for(mission: ThreatMissionDefinition) -> DefenseUnit:
	if mission == null or mission.target_role == ThreatMissionDefinition.TargetRole.CITY or defense_parent == null:
		return null
	var role := &"sensor"
	if mission.target_role == ThreatMissionDefinition.TargetRole.COMMAND:
		role = &"command"
	elif mission.target_role == ThreatMissionDefinition.TargetRole.SUPPORT:
		role = &"support"
	var candidates: Array[DefenseUnit] = []
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit != null and unit.integrity > 0.0 and unit.definition.enemy_knowledge_role() == role:
			candidates.append(unit)
	return candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else null

func _known_target_for_role(role: StringName) -> DefenseUnit:
	var estimate := enemy_knowledge.best_estimate_for_role(role)
	if estimate.is_empty():
		return null
	var target_id := int(estimate.asset_id)
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit != null and unit.runtime_id == target_id and unit.integrity > 0.0:
			return unit
	return null

func _choose_entry() -> ThreatSpawnEntry:
	return _choose_entry_for_budget(INF)

func _choose_entry_for_budget(budget: float) -> ThreatSpawnEntry:
	var available: Array[ThreatSpawnEntry] = []
	var total_weight := 0.0
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if entry.unlock_level <= pressure_level and entry.threat_cost * float(entry.group_size) <= budget:
			available.append(entry)
			total_weight += adaptive_entry_weight(entry)
	if available.is_empty() or total_weight <= 0.0:
		return null
	var roll := rng.randf() * total_weight
	for entry: ThreatSpawnEntry in available:
		roll -= adaptive_entry_weight(entry)
		if roll <= 0.0:
			return entry
	return available.back()

func adaptive_entry_weight(entry: ThreatSpawnEntry) -> float:
	var weight := maxf(0.0, entry.selection_weight)
	if enemy_knowledge == null:
		return weight
	var definition := entry.threat_definition
	if not definition.adaptive_knowledge_role.is_empty():
		var estimate := enemy_knowledge.best_estimate_for_role(definition.adaptive_knowledge_role)
		if estimate.is_empty() and definition.requires_role_knowledge:
			return 0.0
		if not estimate.is_empty():
			weight *= definition.adaptive_knowledge_weight
	if recent_neutralization_rate() > 0.65:
		weight *= definition.high_neutralization_weight
	return weight

func recent_neutralization_rate() -> float:
	if enemy_knowledge == null or enemy_knowledge.recent_outcomes.is_empty():
		return 0.0
	var neutralized := 0
	for outcome: Dictionary in enemy_knowledge.recent_outcomes:
		if bool(outcome.neutralized):
			neutralized += 1
	return float(neutralized) / float(enemy_knowledge.recent_outcomes.size())

func _choose_archetype() -> RaidArchetypeDefinition:
	var available: Array[RaidArchetypeDefinition] = []
	var total_weight := 0.0
	for archetype: RaidArchetypeDefinition in scenario.raid_archetypes:
		if archetype.unlock_level <= pressure_level:
			available.append(archetype)
			total_weight += archetype.selection_weight
	if available.is_empty():
		return null
	var roll := rng.randf() * total_weight
	for archetype: RaidArchetypeDefinition in available:
		roll -= archetype.selection_weight
		if roll <= 0.0:
			return archetype
	return available.back()

func _entry_for_definition(definition_id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if entry.threat_definition.id == definition_id:
			return entry
	return null

func capture_state() -> Dictionary:
	return {
		"elapsed": elapsed,
		"until_spawn": until_spawn,
		"pressure_level": pressure_level,
		"next_runtime_id": next_runtime_id,
		"enabled": enabled,
		"rng_state": str(rng.state),
		"pending_waves": pending_waves.duplicate(true),
		"in_recovery": in_recovery,
		"completed_attack_windows": completed_attack_windows,
	}

func restore_state(state: Dictionary) -> void:
	elapsed = float(state.elapsed)
	until_spawn = float(state.until_spawn)
	pressure_level = int(state.pressure_level)
	next_runtime_id = int(state.next_runtime_id)
	enabled = bool(state.enabled)
	rng.state = int(state.rng_state)
	pending_waves.clear()
	for wave: Dictionary in state.get("pending_waves", []):
		pending_waves.append({"definition_id": String(wave.definition_id), "remaining": float(wave.remaining), "angle": float(wave.angle)})
	in_recovery = bool(state.in_recovery)
	completed_attack_windows = int(state.completed_attack_windows)
	pressure_changed.emit(pressure_level)
