class_name ThreatUnit
extends Node3D

signal resolved(threat: ThreatUnit, neutralized: bool, reward: int)

var runtime_id: int
var definition: ThreatDefinition
var active: bool = true
var resolved_state: bool = false
var health: float = 1.0

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	runtime_id = id_value
	definition = definition_value

func configure_mission(_objective: ProtectedObjective, _battlefield: Battlefield, _target_point: Vector3, _pressure_multiplier: float) -> void:
	pass

func configure_patrol(_battlefield: Battlefield, _initial_velocity: Vector3) -> void:
	pass

func gameplay_tick(_delta: float) -> void:
	pass

func is_targetable() -> bool:
	return active and not resolved_state and health > 0.0

func get_aim_position() -> Vector3:
	return global_position

func get_urgency() -> float:
	return 0.0

func get_sensor_signature() -> Dictionary:
	return {
		"classification_hint": definition.signature_class,
		"radar_factor": definition.radar_signature,
		"affiliation_hint": int(definition.affiliation),
	}

func receive_damage(amount: float) -> bool:
	if not is_targetable() or amount <= 0.0:
		return false
	health -= amount
	if health <= 0.0:
		resolve_once(true)
	return true

func resolve_once(neutralized: bool) -> bool:
	if resolved_state:
		return false
	resolved_state = true
	active = false
	resolved.emit(self, neutralized, definition.neutralization_reward if neutralized else 0)
	return true
