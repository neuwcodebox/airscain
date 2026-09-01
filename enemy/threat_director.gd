class_name ThreatDirector
extends Node

signal pressure_changed(level: int)
signal threat_spawned(threat: ThreatUnit)

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
	until_spawn -= delta
	if until_spawn > 0.0:
		return
	until_spawn += spawn_interval_at(elapsed)
	if pressure_level >= 3 and not scenario.raid_archetypes.is_empty() and rng.randf() < 0.35:
		var archetype := _choose_archetype()
		if archetype != null:
			schedule_archetype(archetype, rng.randf_range(0.0, TAU))
			return
	var package_count := spawn_count_at(elapsed)
	for _package_index: int in package_count:
		var entry := _choose_entry()
		if entry == null:
			continue
		_spawn_group(entry, rng.randf_range(0.0, TAU))

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
	if entry.threat_definition is AttackUavDefinition and (entry.threat_definition as AttackUavDefinition).mission.target_role == ThreatMissionDefinition.TargetRole.CITY:
		group_target = objective.get_target_point(rng)
		group_target.y = battlefield.terrain_height(group_target.x, group_target.z)
	for group_index: int in entry.group_size:
		if registry.hostile_count() >= scenario.active_threat_cap:
			return
		_spawn_entry(entry, group_angle + rng.randf_range(-0.035, 0.035), float(group_index) * 3.0, group_target)

func pressure_level_at(time_seconds: float) -> int:
	return 1 + int(floor(time_seconds / 45.0))

func spawn_interval_at(time_seconds: float) -> float:
	return maxf(1.15, scenario.initial_spawn_interval - float(pressure_level_at(time_seconds) - 1) * 0.32)

func spawn_count_at(time_seconds: float) -> int:
	return 1 + int(floor(time_seconds / 120.0))

func speed_multiplier_at(time_seconds: float) -> float:
	return minf(2.0, 1.0 + time_seconds / 600.0)

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
	var edge := scenario.battlefield_size * 0.5 - 8.0 - edge_offset
	var spawn_position := Vector3(cos(angle) * edge, 0.0, sin(angle) * edge)
	var spawn_altitude := 70.0
	if entry.threat_definition is AttackUavDefinition:
		spawn_altitude = (entry.threat_definition as AttackUavDefinition).movement.cruise_altitude
	spawn_position.y = battlefield.terrain_height(spawn_position.x, spawn_position.z) + spawn_altitude
	threat.global_position = spawn_position
	threat.setup(next_runtime_id, entry.threat_definition)
	threat.configure_enemy_knowledge(enemy_knowledge)
	next_runtime_id += 1
	var target := objective.get_target_point(rng)
	var target_asset: DefenseUnit
	if entry.threat_definition is AttackUavDefinition:
		target_asset = choose_target_for((entry.threat_definition as AttackUavDefinition).mission)
	if target_override is Vector3:
		target = target_override
		target_asset = null
	elif target_asset != null:
		target = target_asset.global_position
	else:
		target.y = battlefield.terrain_height(target.x, target.z)
	threat.configure_mission(objective, battlefield, target, speed_multiplier_at(elapsed), target_asset, spawn_position)
	registry.add(threat)
	threat_spawned.emit(threat)
	return threat

func choose_target_for(mission: ThreatMissionDefinition) -> DefenseUnit:
	if mission == null or mission.target_role == ThreatMissionDefinition.TargetRole.CITY or defense_parent == null:
		return null
	var candidates: Array[DefenseUnit] = []
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit == null or unit.integrity <= 0.0:
			continue
		if mission.target_role == ThreatMissionDefinition.TargetRole.SENSOR and (unit.c2_roles() & DefenseUnit.C2Role.SENSOR) != 0:
			candidates.append(unit)
		elif mission.target_role == ThreatMissionDefinition.TargetRole.COMMAND and (unit.c2_roles() & DefenseUnit.C2Role.COMMAND) != 0:
			candidates.append(unit)
		elif mission.target_role == ThreatMissionDefinition.TargetRole.SUPPORT and unit is SupportFacility:
			candidates.append(unit)
	return candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else null

func _choose_entry() -> ThreatSpawnEntry:
	var available: Array[ThreatSpawnEntry] = []
	var total_weight := 0.0
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if entry.unlock_level <= pressure_level:
			available.append(entry)
			total_weight += maxf(0.0, entry.selection_weight)
	if available.is_empty() or total_weight <= 0.0:
		return null
	var roll := rng.randf() * total_weight
	for entry: ThreatSpawnEntry in available:
		roll -= maxf(0.0, entry.selection_weight)
		if roll <= 0.0:
			return entry
	return available.back()

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
	pressure_changed.emit(pressure_level)
