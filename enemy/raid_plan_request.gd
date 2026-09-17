class_name RaidPlanRequest
extends RefCounted

var scenario: ScenarioDefinition
var weights: Dictionary[StringName, float] = {}
var budget: float = 0.0
var level: int = 1
var angle: float = 0.0
var max_delay: float = 0.0
var speed: float = 1.0
var rng: RandomNumberGenerator
var travel_distances: Dictionary[StringName, float] = {}
var suppression_priority_chance: float = -1.0
var suppression_targets: Dictionary = {}
