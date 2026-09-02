class_name ThreatUnit
extends Node3D

signal resolved(threat: ThreatUnit, neutralized: bool, reward: int)

var runtime_id: int
var definition: ThreatDefinition
var active: bool = true
var resolved_state: bool = false
var health: float = 1.0
var enemy_knowledge: EnemyKnowledge
var countermeasure_charges_remaining: int = 0

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	runtime_id = id_value
	definition = definition_value
	countermeasure_charges_remaining = definition.countermeasure_charges

func configure_mission(_objective: ProtectedObjective, _battlefield: Battlefield, _target_point: Vector3, _pressure_multiplier: float, _target_asset: DefenseUnit = null, _exit_point: Vector3 = Vector3.ZERO) -> void:
	pass

func configure_patrol(_battlefield: Battlefield, _initial_velocity: Vector3) -> void:
	pass

func configure_enemy_knowledge(knowledge: EnemyKnowledge) -> void:
	enemy_knowledge = knowledge

func gameplay_tick(_delta: float) -> void:
	pass

func is_targetable() -> bool:
	return active and not resolved_state and health > 0.0

func get_aim_position() -> Vector3:
	return global_position

func get_urgency() -> float:
	return 0.0

func presentation_velocity() -> Vector3:
	return Vector3.ZERO

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

func receive_electronic_damage(amount: float) -> bool:
	return receive_damage(amount * definition.electronic_vulnerability)

func try_defeat_seeker(infrared_sensitivity: float, radar_sensitivity: float, roll: float) -> bool:
	if countermeasure_charges_remaining <= 0:
		return false
	var probability := maxf(definition.flare_effectiveness * infrared_sensitivity, definition.chaff_effectiveness * radar_sensitivity)
	if roll >= probability:
		return false
	countermeasure_charges_remaining -= 1
	return true

func effective_countermeasure_type(infrared_sensitivity: float, radar_sensitivity: float) -> StringName:
	var flare_score := definition.flare_effectiveness * infrared_sensitivity
	var chaff_score := definition.chaff_effectiveness * radar_sensitivity
	return &"flare" if flare_score >= chaff_score else &"chaff"

func resolve_once(neutralized: bool) -> bool:
	if resolved_state:
		return false
	resolved_state = true
	active = false
	resolved.emit(self, neutralized, definition.neutralization_reward if neutralized else 0)
	return true

func capture_state() -> Dictionary:
	return {
		"definition_id": String(definition.id),
		"runtime_id": runtime_id,
		"position": SaveDocument.vector3_to_data(global_position),
		"health": health,
		"active": active,
		"resolved_state": resolved_state,
		"countermeasure_charges": countermeasure_charges_remaining,
		"content_state": capture_content_state(),
	}

func capture_content_state() -> Dictionary:
	return {}

func restore_state(state: Dictionary, objective_value: ProtectedObjective, battlefield_value: Battlefield, defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	health = float(state.health)
	active = bool(state.active)
	resolved_state = bool(state.resolved_state)
	countermeasure_charges_remaining = int(state.get("countermeasure_charges", definition.countermeasure_charges))
	restore_content_state(state.get("content_state", {}), objective_value, battlefield_value, defense_by_id)

func restore_content_state(_state: Dictionary, _objective: ProtectedObjective, _battlefield: Battlefield, _defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	pass
