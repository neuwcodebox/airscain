class_name ThreatDirector
extends Node

signal pressure_changed(level: int)
signal threat_spawned(threat: ThreatUnit)

var scenario: ScenarioDefinition
var battlefield: Battlefield
var objective: ProtectedObjective
var registry: ThreatRegistry
var threat_parent: Node3D
var rng := RandomNumberGenerator.new()
var elapsed: float = 0.0
var until_spawn: float = 0.0
var pressure_level: int = 1
var next_runtime_id: int = 1
var enabled: bool = false

func configure(scenario_value: ScenarioDefinition, battlefield_value: Battlefield, objective_value: ProtectedObjective, registry_value: ThreatRegistry, threat_parent_value: Node3D) -> void:
	scenario = scenario_value
	battlefield = battlefield_value
	objective = objective_value
	registry = registry_value
	threat_parent = threat_parent_value
	rng.seed = scenario.world_seed ^ 0x6E624EB7
	reset()

func reset() -> void:
	elapsed = 0.0
	until_spawn = scenario.initial_spawn_interval if scenario != null else 4.0
	pressure_level = 1
	next_runtime_id = 1
	enabled = false
	pressure_changed.emit(pressure_level)

func gameplay_tick(delta: float) -> void:
	if not enabled:
		return
	elapsed += delta
	var new_level := pressure_level_at(elapsed)
	if new_level != pressure_level:
		pressure_level = new_level
		pressure_changed.emit(pressure_level)
	until_spawn -= delta
	if until_spawn > 0.0:
		return
	until_spawn += spawn_interval_at(elapsed)
	var count := spawn_count_at(elapsed)
	for index: int in count:
		if registry.hostile_count() >= scenario.active_threat_cap:
			break
		spawn_one()

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
	var threat := entry.threat_definition.scene.instantiate() as ThreatUnit
	if threat == null:
		return null
	threat_parent.add_child(threat)
	var angle := rng.randf_range(0.0, TAU)
	var edge := scenario.battlefield_size * 0.5 - 8.0
	var spawn_position := Vector3(cos(angle) * edge, 0.0, sin(angle) * edge)
	spawn_position.y = battlefield.terrain_height(spawn_position.x, spawn_position.z) + 70.0
	threat.global_position = spawn_position
	threat.setup(next_runtime_id, entry.threat_definition)
	next_runtime_id += 1
	var target := objective.get_target_point(rng)
	target.y = battlefield.terrain_height(target.x, target.z)
	threat.configure_mission(objective, battlefield, target, speed_multiplier_at(elapsed))
	registry.add(threat)
	threat_spawned.emit(threat)
	return threat

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

func capture_state() -> Dictionary:
	return {
		"elapsed": elapsed,
		"until_spawn": until_spawn,
		"pressure_level": pressure_level,
		"next_runtime_id": next_runtime_id,
		"enabled": enabled,
		"rng_state": rng.state,
	}

func restore_state(state: Dictionary) -> void:
	elapsed = float(state.elapsed)
	until_spawn = float(state.until_spawn)
	pressure_level = int(state.pressure_level)
	next_runtime_id = int(state.next_runtime_id)
	enabled = bool(state.enabled)
	rng.state = int(state.rng_state)
	pressure_changed.emit(pressure_level)
