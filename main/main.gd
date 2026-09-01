class_name AirscainMain
extends Node3D

const BASE_SCENARIO := preload("res://main/first_scenario.tres")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")

static var requested_seed: int = -1

var scenario: ScenarioDefinition
var registry := ThreatRegistry.new()
var objective: ProtectedObjective
var defenses: Array[DefenseUnit] = []

@onready var battlefield: Battlefield = $Battlefield
@onready var session: GameSession = $GameSession
@onready var director: ThreatDirector = $ThreatDirector
@onready var camera_rig: CameraRig = $CameraRig
@onready var world_objects: Node3D = $WorldObjects
@onready var objectives: Node3D = $WorldObjects/Objectives
@onready var defense_parent: Node3D = $WorldObjects/Defenses
@onready var threat_parent: Node3D = $WorldObjects/Threats
@onready var projectile_parent: Node3D = $WorldObjects/Projectiles
@onready var effects_parent: Node3D = $WorldObjects/Effects
@onready var placement: PlacementController = $PlacementController
@onready var hud: Hud = $UI/HUD

func _ready() -> void:
	scenario = BASE_SCENARIO.duplicate(true) as ScenarioDefinition
	if requested_seed >= 0:
		scenario.world_seed = requested_seed
	requested_seed = scenario.world_seed
	battlefield.build(scenario)
	_spawn_objective()
	session.reset(scenario.starting_budget)
	director.configure(scenario, battlefield, objective, registry, threat_parent)
	placement.configure(session, battlefield, camera_rig.camera, defense_parent, projectile_parent, registry)
	hud.configure(session, objective, scenario.available_defenses)
	_connect_flow()
	hud.set_feedback("포대를 배치한 뒤 방어를 시작하세요 · Seed %d" % scenario.world_seed)

func _process(delta: float) -> void:
	var simulation_delta := session.gameplay_delta(delta)
	if simulation_delta <= 0.0:
		return
	director.gameplay_tick(simulation_delta)
	for defense: DefenseUnit in defenses:
		if is_instance_valid(defense):
			defense.gameplay_tick(simulation_delta)
	for threat: ThreatUnit in registry.get_active():
		threat.gameplay_tick(simulation_delta)

func _spawn_objective() -> void:
	objective = scenario.objective_definition.scene.instantiate() as ProtectedObjective
	objectives.add_child(objective)
	objective.global_position = Vector3(0.0, battlefield.terrain_height(0.0, 0.0), 0.0)
	objective.exclusion_radius = scenario.city_size * 0.5
	objective.setup(1, scenario.objective_definition)
	battlefield.set_objective(objective)

func _connect_flow() -> void:
	objective.depleted.connect(_on_objective_depleted)
	director.threat_spawned.connect(_on_threat_spawned)
	director.pressure_changed.connect(_on_pressure_changed)
	session.defense_placed.connect(_on_defense_placed)
	hud.defense_selected.connect(placement.select)
	hud.start_requested.connect(_on_start_requested)
	hud.speed_requested.connect(session.set_simulation_speed)
	hud.restart_requested.connect(_on_restart_requested)
	placement.feedback_changed.connect(hud.set_feedback)

func _on_start_requested() -> void:
	if session.start_defense():
		director.enabled = true
		hud.set_feedback("방어 진행 중 · 포대를 추가 배치할 수 있습니다")

func _on_defense_placed(unit: DefenseUnit) -> void:
	defenses.append(unit)

func _on_threat_spawned(threat: ThreatUnit) -> void:
	threat.resolved.connect(_on_threat_resolved)

func _on_threat_resolved(threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	registry.remove(threat)
	session.register_threat_resolution(threat, neutralized, reward)
	_spawn_explosion(threat.global_position, Color("ff8c35") if neutralized else Color("ff3b24"), 10.0 if neutralized else 15.0)
	threat.queue_free()

func _on_objective_depleted(_objective: ProtectedObjective) -> void:
	director.enabled = false
	session.end_game()
	placement.cancel()

func _on_pressure_changed(level: int) -> void:
	session.update_pressure(level)
	hud.set_pressure(level)

func _spawn_explosion(position: Vector3, color: Color, radius: float) -> void:
	var effect := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	effects_parent.add_child(effect)
	effect.global_position = position
	effect.setup(color, radius)

func _on_restart_requested(same_seed: bool) -> void:
	if same_seed:
		requested_seed = scenario.world_seed
	else:
		requested_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	get_tree().reload_current_scene()
