class_name AttackUav
extends ThreatUnit

enum FlightPhase { APPROACH, TERMINAL }

var objective: ProtectedObjective
var battlefield: Battlefield
var target_point: Vector3
var speed_multiplier: float = 1.0
var phase := FlightPhase.APPROACH
var _definition: AttackUavDefinition

@onready var body: Node3D = $Body

func configure_mission(objective_value: ProtectedObjective, battlefield_value: Battlefield, target_value: Vector3, pressure_multiplier: float) -> void:
	objective = objective_value
	battlefield = battlefield_value
	target_point = target_value
	speed_multiplier = pressure_multiplier

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as AttackUavDefinition
	health = _definition.maximum_health

func gameplay_tick(delta: float) -> void:
	if not active or resolved_state:
		return
	var flat_to_target := Vector2(target_point.x - global_position.x, target_point.z - global_position.z)
	if phase == FlightPhase.APPROACH and flat_to_target.length() <= _definition.terminal_distance:
		phase = FlightPhase.TERMINAL
	var desired_position := target_point
	if phase == FlightPhase.APPROACH:
		desired_position.y = battlefield.terrain_height(global_position.x, global_position.z) + _definition.cruise_altitude
	else:
		desired_position.y = battlefield.terrain_height(target_point.x, target_point.z) + 2.0
	var direction := global_position.direction_to(desired_position)
	if direction.length_squared() > 0.001:
		global_position += direction * _definition.base_speed * speed_multiplier * delta
		body.look_at(global_position + direction, Vector3.UP)
	if global_position.distance_to(target_point + Vector3.UP * 2.0) <= 5.0:
		if resolve_once(false):
			objective.apply_mission_damage(_definition.mission_damage)

func get_urgency() -> float:
	if objective == null:
		return 0.0
	return 1.0 / maxf(1.0, global_position.distance_to(target_point))
