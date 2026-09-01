class_name ScenarioDefinition
extends Resource

@export var world_seed: int = 73129
@export var battlefield_size: float = 1200.0
@export var terrain_resolution: int = 49
@export var city_size: float = 330.0
@export var starting_budget: int = 400
@export var objective_definition: ObjectiveDefinition
@export var available_defenses: Array[DefenseDefinition] = []
@export var threat_entries: Array[ThreatSpawnEntry] = []
@export var initial_spawn_interval: float = 4.0
@export var active_threat_cap: int = 200

