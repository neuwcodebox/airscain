class_name AttackUav
extends ThreatUnit

var objective: ProtectedObjective
var battlefield: Battlefield
var target_point: Vector3
var speed_multiplier: float = 1.0
var mover := ThreatMover.new()
var _definition: AttackUavDefinition

@onready var body: Node3D = $Body

func configure_mission(objective_value: ProtectedObjective, battlefield_value: Battlefield, target_value: Vector3, pressure_multiplier: float) -> void:
	objective = objective_value
	battlefield = battlefield_value
	target_point = target_value
	speed_multiplier = pressure_multiplier
	mover.setup(_definition.movement, battlefield, global_position.direction_to(target_point))

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as AttackUavDefinition
	health = _definition.maximum_health

func gameplay_tick(delta: float) -> void:
	if not active or resolved_state:
		return
	mover.advance(self, body, target_point, speed_multiplier, delta)
	if global_position.distance_to(target_point + Vector3.UP * 2.0) <= _definition.mission.action_distance:
		if resolve_once(false):
			objective.apply_mission_damage(roundi(_definition.mission.damage))

func get_urgency() -> float:
	if objective == null:
		return 0.0
	return 1.0 / maxf(1.0, global_position.distance_to(target_point))

func capture_content_state() -> Dictionary:
	return {
		"target_point": SaveDocument.vector3_to_data(target_point),
		"speed_multiplier": speed_multiplier,
		"movement": mover.capture_state(),
	}

func restore_content_state(state: Dictionary, objective_value: ProtectedObjective, battlefield_value: Battlefield) -> void:
	objective = objective_value
	battlefield = battlefield_value
	target_point = SaveDocument.vector3_from_data(state.get("target_point", []))
	speed_multiplier = float(state.get("speed_multiplier", 1.0))
	mover.restore_state(state.get("movement", {}), _definition.movement, battlefield)
