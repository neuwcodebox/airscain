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
var raid_planner := RaidPlanner.new()
var opening_raid_started: bool = false
var opening_raid_complete: bool = false
var opening_threat_ids: Array[int] = []
var pressure_started_at: float = 0.0

func configure(scenario_value: ScenarioDefinition, battlefield_value: Battlefield, objective_value: ProtectedObjective, registry_value: ThreatRegistry, threat_parent_value: Node3D, defense_parent_value: Node3D, enemy_knowledge_value: EnemyKnowledge) -> void:
	scenario = scenario_value
	battlefield = battlefield_value
	objective = objective_value
	registry = registry_value
	threat_parent = threat_parent_value
	defense_parent = defense_parent_value
	enemy_knowledge = enemy_knowledge_value
	if enemy_knowledge != null:
		enemy_knowledge.configure_recon(defense_parent, battlefield, scenario.battlefield_size)
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
	opening_raid_started = false
	opening_raid_complete = false
	opening_threat_ids.clear()
	pressure_started_at = 0.0
	raid_planner.last_pattern = &""
	raid_planner.recent_definition_ids.clear()
	pressure_changed.emit(pressure_level)

func gameplay_tick(delta: float) -> void:
	if not enabled:
		return
	elapsed += delta
	_tick_pending_waves(delta)
	_finish_opening_raid_if_ready()
	var new_level := pressure_level_at(elapsed)
	if new_level != pressure_level:
		pressure_level = new_level
		pressure_changed.emit(pressure_level)
	var should_recover := _should_recover()
	if should_recover != in_recovery:
		in_recovery = should_recover
		if in_recovery:
			completed_attack_windows += 1
			recovery_started.emit(completed_attack_windows)
			if _can_launch_automatic_raid():
				launch_budgeted_raid(true)
		else:
			until_spawn = maxf(until_spawn, scenario.initial_spawn_interval)
	if in_recovery:
		return
	until_spawn -= delta
	if until_spawn > 0.0:
		return
	var interval := automatic_raid_interval_at(elapsed)
	until_spawn = fposmod(until_spawn, interval)
	if is_zero_approx(until_spawn):
		until_spawn = interval
	launch_budgeted_raid()

func _should_recover() -> bool:
	if not opening_raid_complete:
		return false
	if elapsed < pressure_started_at:
		return true
	var cycle_duration := scenario.attack_window_duration + scenario.recovery_duration
	return fmod(elapsed - pressure_started_at, cycle_duration) >= scenario.attack_window_duration

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
			_spawn_group(entry, float(wave.angle), bool(wave.get("opening_raid", false)))
		pending_waves.remove_at(index)

func _spawn_group(entry: ThreatSpawnEntry, group_angle: float, opening_raid: bool = false) -> void:
	var group_target: Variant = null
	if entry.threat_definition.shares_city_impact_target():
		group_target = battlefield.random_city_building_target(rng)
	for group_index: int in entry.group_size:
		if registry.hostile_count() >= scenario.active_threat_cap:
			return
		var threat := _spawn_entry(entry, group_angle + rng.randf_range(-0.035, 0.035), float(group_index) * 3.0, group_target)
		if opening_raid and threat != null:
			opening_threat_ids.append(threat.runtime_id)

func pressure_level_at(time_seconds: float) -> int:
	if not opening_raid_complete or time_seconds < pressure_started_at:
		return 1
	return 2 + int(floor((time_seconds - pressure_started_at) / scenario.pressure_step_duration))

func spawn_interval_at(time_seconds: float) -> float:
	return raid_interval_at(time_seconds)

func raid_interval_at(time_seconds: float) -> float:
	var completed_pressure_steps := float(pressure_level_at(time_seconds) - 1)
	return maxf(scenario.minimum_raid_interval, scenario.initial_raid_interval - completed_pressure_steps * scenario.raid_interval_pressure_reduction)

func automatic_raid_interval_at(time_seconds: float) -> float:
	if opening_raid_started and not opening_raid_complete:
		return scenario.opening_raid_interval
	return raid_interval_at(time_seconds)

func threat_budget_at(time_seconds: float) -> float:
	return 3.0 + float(pressure_level_at(time_seconds)) + performance_budget_adjustment()

func performance_budget_adjustment() -> float:
	if enemy_knowledge == null or enemy_knowledge.recent_outcomes.size() < 4:
		return 0.0
	return clampf((recent_neutralization_rate() - 0.5) * 4.0, -1.0, 1.0)

func speed_multiplier_at(time_seconds: float) -> float:
	return minf(scenario.maximum_speed_multiplier, 1.0 + time_seconds / scenario.speed_growth_duration)

func launch_budgeted_raid(for_next_attack_window: bool = false) -> void:
	var attack_elapsed := maxf(0.0, elapsed - pressure_started_at) if opening_raid_complete else elapsed
	var cycle := scenario.attack_window_duration + scenario.recovery_duration
	var remaining_attack := scenario.attack_window_duration if for_next_attack_window else scenario.attack_window_duration - fmod(attack_elapsed, cycle)
	if remaining_attack <= 0.0:
		return
	var weights: Dictionary[StringName, float] = {}
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		var weight := adaptive_entry_weight(entry)
		var role := entry.threat_definition.adaptive_knowledge_role
		if entry.raid_role == ThreatSpawnEntry.RaidRole.SUPPRESSION and not role.is_empty():
			var estimate := enemy_knowledge.best_estimate_for_role(role, _mission_assignments()) if enemy_knowledge != null else {}
			if estimate.is_empty() or float(estimate.confidence) < 0.2:
				weight = 0.0
		weights[entry.threat_definition.id] = weight
	var approach_angle := adaptive_approach_angle()
	if rng.randf() < 0.3:
		approach_angle = rng.randf_range(0.0, TAU)
	else:
		approach_angle += rng.randf_range(-0.35, 0.35)
	var max_delay := minf(32.0, maxf(0.0, remaining_attack - 0.05))
	var travel_distances := estimated_travel_distances(approach_angle)
	var waves := raid_planner.generate(scenario, weights, threat_budget_at(elapsed), pressure_level, approach_angle, max_delay, speed_multiplier_at(elapsed), rng, travel_distances, suppression_priority_chance())
	if not opening_raid_started and not waves.is_empty():
		opening_raid_started = true
		for wave: Dictionary in waves:
			wave["opening_raid"] = true
	pending_waves.append_array(waves)

func suppression_priority_chance() -> float:
	var chance := scenario.asset_suppression_chance if pressure_level >= 4 else 0.0
	if enemy_knowledge == null:
		return chance
	for estimate: Dictionary in enemy_knowledge.estimates.values():
		if String(estimate.get("source", "")) != "reconnaissance" or float(estimate.get("confidence", 0.0)) < 0.2:
			continue
		if enemy_knowledge.simulation_time - float(estimate.get("observed_at", 0.0)) <= scenario.recon_followup_window:
			return maxf(chance, scenario.recon_followup_suppression_chance)
	return chance

func estimated_travel_distances(approach_angle: float) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	if enemy_knowledge == null:
		return result
	var assignments := _mission_assignments()
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		var role := entry.threat_definition.adaptive_knowledge_role
		var mission := entry.threat_definition.mission_definition()
		if role.is_empty() or mission == null or mission.target_role == ThreatMissionDefinition.TargetRole.CITY:
			continue
		var estimate := enemy_knowledge.best_estimate_for_role(role, assignments)
		if estimate.is_empty():
			continue
		var radius := scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier()
		var spawn := Vector2(cos(approach_angle) * radius, sin(approach_angle) * radius)
		var target := SaveDocument.vector3_from_data(estimate.estimated_position)
		result[entry.threat_definition.id] = maxf(0.0, spawn.distance_to(Vector2(target.x, target.z)) - mission.action_distance)
	return result

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

func _spawn_entry(entry: ThreatSpawnEntry, angle: float, edge_offset: float, target_override: Variant = null, target_asset_override: DefenseUnit = null) -> ThreatUnit:
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
	var target := objective.get_target_point(rng)
	var target_asset: DefenseUnit
	var has_required_target := false
	var mission := entry.threat_definition.mission_definition()
	var targets_city := entry.threat_definition.shares_city_impact_target()
	if mission != null and mission.area_recon:
		target = enemy_knowledge.search_target(threat.runtime_id, spawn_position) if enemy_knowledge != null else Vector3.ZERO
	elif mission != null:
		if targets_city:
			target = battlefield.random_city_building_target(rng)
		if mission.acquisition_range > 0.0:
			var estimate := enemy_knowledge.best_estimate_for_role(mission.knowledge_role(), _mission_assignments()) if enemy_knowledge != null else {}
			if not estimate.is_empty():
				has_required_target = true
				target = SaveDocument.vector3_from_data(estimate.estimated_position)
				for child: Node in defense_parent.get_children():
					var candidate := child as DefenseUnit
					if candidate != null and candidate.runtime_id == int(estimate.asset_id):
						target_asset = candidate
		elif entry.threat_definition.requires_role_knowledge:
			var estimate := enemy_knowledge.best_estimate_for_role(entry.threat_definition.adaptive_knowledge_role, _mission_assignments()) if enemy_knowledge != null else {}
			if not estimate.is_empty():
				has_required_target = true
				target = SaveDocument.vector3_from_data(estimate.estimated_position)
			if mission.type != ThreatMissionDefinition.Type.RECONNAISSANCE:
				target_asset = _known_target_for_role(entry.threat_definition.adaptive_knowledge_role)
		else:
			target_asset = choose_target_for(mission)
	if is_instance_valid(target_asset_override) and target_asset_override.active:
		target = target_asset_override.global_position
		target_asset = target_asset_override
		has_required_target = true
	elif target_override is Vector3:
		target = target_override
		target_asset = null
		has_required_target = true
	elif mission != null and entry.threat_definition.requires_role_knowledge and not has_required_target:
		threat.free()
		return null
	elif target_asset != null and (mission == null or mission.acquisition_range <= 0.0):
		target = target_asset.global_position
	elif not targets_city and (mission == null or mission.acquisition_range <= 0.0):
		target.y = battlefield.terrain_height(target.x, target.z)
	threat.configure_mission(objective, battlefield, target, speed_multiplier_at(elapsed), target_asset, spawn_position)
	next_runtime_id += 1
	registry.add(threat)
	bind_releases(threat)
	threat_spawned.emit(threat)
	return threat

func bind_releases(threat: ThreatUnit) -> void:
	var release_callback := _register_released_threat.bind(threat)
	if not threat.threat_released.is_connected(release_callback):
		threat.threat_released.connect(release_callback)
	if not threat.resolved.is_connected(_on_threat_resolved):
		threat.resolved.connect(_on_threat_resolved)

func _on_threat_resolved(threat: ThreatUnit, _neutralized: bool, _reward: int) -> void:
	opening_threat_ids.erase(threat.runtime_id)
	_finish_opening_raid_if_ready()

func _finish_opening_raid_if_ready() -> void:
	if not opening_raid_started or opening_raid_complete or not opening_threat_ids.is_empty():
		return
	for wave: Dictionary in pending_waves:
		if bool(wave.get("opening_raid", false)):
			return
	opening_raid_complete = true
	pressure_started_at = elapsed + scenario.recovery_duration

func _can_launch_automatic_raid() -> bool:
	return scenario != null and battlefield != null and objective != null and registry != null and threat_parent != null and defense_parent != null

func _register_released_threat(threat: ThreatUnit, source: ThreatUnit) -> void:
	threat.setup(next_runtime_id, threat.definition)
	next_runtime_id += 1
	if opening_threat_ids.has(source.runtime_id):
		opening_threat_ids.append(threat.runtime_id)
	bind_releases(threat)
	registry.add(threat)
	threat_spawned.emit(threat)

func choose_target_for(mission: ThreatMissionDefinition) -> DefenseUnit:
	if mission == null or defense_parent == null or mission.area_recon or mission.target_role == ThreatMissionDefinition.TargetRole.CITY:
		return null
	var role := mission.knowledge_role()
	var candidates: Array[DefenseUnit] = []
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit != null and unit.integrity > 0.0 and unit.definition.enemy_knowledge_role() == role:
			candidates.append(unit)
	return candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else null

func _known_target_for_role(role: StringName) -> DefenseUnit:
	var estimate := enemy_knowledge.best_estimate_for_role(role, _mission_assignments())
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
		var estimate := enemy_knowledge.best_estimate_for_role(definition.adaptive_knowledge_role, _mission_assignments())
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
		"last_raid_pattern": String(raid_planner.last_pattern),
		"recent_raid_definitions": raid_planner.capture_recent_definitions(),
		"opening_raid_started": opening_raid_started,
		"opening_raid_complete": opening_raid_complete,
		"opening_threat_ids": opening_threat_ids.duplicate(),
		"pressure_started_at": pressure_started_at,
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
		pending_waves.append(wave.duplicate(true))
	in_recovery = bool(state.in_recovery)
	completed_attack_windows = int(state.completed_attack_windows)
	opening_raid_started = bool(state.opening_raid_started)
	opening_raid_complete = bool(state.opening_raid_complete)
	opening_threat_ids.assign(state.opening_threat_ids)
	pressure_started_at = float(state.pressure_started_at)
	raid_planner.last_pattern = StringName(state.get("last_raid_pattern", ""))
	raid_planner.restore_recent_definitions(state.get("recent_raid_definitions", []))
	pressure_changed.emit(pressure_level)

static func opening_state_validation_error(state: Dictionary) -> String:
	if not state.get("opening_raid_started") is bool or not state.get("opening_raid_complete") is bool or not state.get("opening_threat_ids") is Array:
		return "첫 공습 상태가 올바르지 않습니다"
	var start: Variant = state.get("pressure_started_at")
	if not (start is float or start is int) or not is_finite(float(start)):
		return "위협 단계 시작 시간이 올바르지 않습니다"
	var ids: Dictionary[int, bool] = {}
	for id: Variant in state.opening_threat_ids:
		if not (id is int or id is float) or not is_finite(float(id)) or float(id) != float(int(id)) or int(id) <= 0 or ids.has(int(id)):
			return "첫 공습 위협 ID가 올바르지 않습니다"
		ids[int(id)] = true
	var has_pending := false
	for wave: Variant in state.pending_waves:
		if not wave is Dictionary or not wave.get("opening_raid", false) is bool:
			return "첫 공습 예약 상태가 올바르지 않습니다"
		has_pending = has_pending or bool(wave.get("opening_raid", false))
	if (not state.opening_raid_started or state.opening_raid_complete) and (not ids.is_empty() or has_pending):
		return "첫 공습 진행과 남은 위협이 일치하지 않습니다"
	if state.opening_raid_complete and not state.opening_raid_started:
		return "시작하지 않은 첫 공습이 완료되었습니다"
	return ""

func _mission_assignments() -> Dictionary[int, int]:
	var result: Dictionary[int, int] = {}
	if registry != null:
		for threat: ThreatUnit in registry.get_active():
			var target_id := threat.assigned_target_id()
			if target_id > 0:
				result[target_id] = result.get(target_id, 0) + 1
	return result
