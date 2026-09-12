class_name ThreatUnit
extends Node3D

signal resolved(threat: ThreatUnit, neutralized: bool, reward: int)
signal threat_released(threat: ThreatUnit)

const PRESENTATION_SCALE := 0.9

var runtime_id: int
var definition: ThreatDefinition
var active: bool = true
var resolved_state: bool = false
var health: float = 1.0
var enemy_knowledge: EnemyKnowledge
signal countermeasure_released(kind: StringName)
var countermeasure_charges_remaining: int = 0
var countermeasure_cooldown: float = 0.0
var countermeasure_evasion: float = 0.0
var countermeasure_kind: StringName
var countermeasure_origin := Vector3.ZERO

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	scale = Vector3.ONE * PRESENTATION_SCALE
	runtime_id = id_value
	definition = definition_value
	countermeasure_charges_remaining = definition.countermeasure_charges

func configure_mission(_objective: ProtectedObjective, _battlefield: Battlefield, _target_point: Vector3, _pressure_multiplier: float, _target_asset: DefenseUnit = null, _exit_point: Vector3 = Vector3.ZERO) -> void:
	pass

func configure_patrol(_battlefield: Battlefield, _initial_velocity: Vector3) -> void:
	pass

func configure_enemy_knowledge(knowledge: EnemyKnowledge) -> void:
	enemy_knowledge = knowledge

func gameplay_tick(delta: float) -> void:
	countermeasure_cooldown = maxf(0.0, countermeasure_cooldown - delta)
	countermeasure_evasion = maxf(0.0, countermeasure_evasion - delta)

func is_targetable() -> bool:
	return active and not resolved_state and health > 0.0

func get_aim_position() -> Vector3:
	return global_position

func get_urgency() -> float:
	return 0.0

func presentation_action_seconds() -> float:
	return INF

func presentation_action_completed() -> bool:
	return false

func presentation_velocity() -> Vector3:
	return Vector3.ZERO

func exits_without_impact() -> bool:
	return false

func impact_uses_objective_audio() -> bool:
	return false

func get_sensor_signature() -> Dictionary:
	return {
		"classification_hint": definition.signature_class,
		"radar_factor": definition.radar_signature,
		"affiliation_hint": int(definition.affiliation),
	}

func receive_damage(amount: float, source: DefenseUnit = null) -> bool:
	if not is_targetable() or amount <= 0.0:
		return false
	health -= amount
	if health <= 0.0:
		if source != null:
			source.record_neutralization(self)
		resolve_once(true)
	return true

func receive_electronic_damage(amount: float, source: DefenseUnit = null) -> bool:
	return receive_damage(amount * definition.electronic_vulnerability, source)

func respond_to_seeker(infrared_sensitivity: float, radar_sensitivity: float, roll: float) -> Dictionary:
	var released := false
	if countermeasure_cooldown <= 0.0:
		if countermeasure_charges_remaining <= 0 or maxf(definition.flare_effectiveness * infrared_sensitivity, definition.chaff_effectiveness * radar_sensitivity) <= 0.0:
			return {}
		countermeasure_kind = effective_countermeasure_type(infrared_sensitivity, radar_sensitivity)
		countermeasure_origin = global_position if is_inside_tree() else position
		countermeasure_charges_remaining -= 1
		countermeasure_cooldown = 0.9
		countermeasure_evasion = 1.6
		released = true
		countermeasure_released.emit(countermeasure_kind)
	var probability := definition.flare_effectiveness * infrared_sensitivity if countermeasure_kind == &"flare" else definition.chaff_effectiveness * radar_sensitivity
	return {"released": released, "defeated": roll < probability, "kind": countermeasure_kind, "position": countermeasure_origin}

func try_defeat_seeker(infrared_sensitivity: float, radar_sensitivity: float, roll: float) -> bool:
	return bool(respond_to_seeker(infrared_sensitivity, radar_sensitivity, roll).get("defeated", false))

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
		"countermeasure": {"cooldown": countermeasure_cooldown, "evasion": countermeasure_evasion, "kind": String(countermeasure_kind), "origin": SaveDocument.vector3_to_data(countermeasure_origin)},
		"content_state": capture_content_state(),
	}

func capture_content_state() -> Dictionary:
	return {}

func restore_state(state: Dictionary, objective_value: ProtectedObjective, battlefield_value: Battlefield, defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	health = float(state.health)
	active = bool(state.active)
	resolved_state = bool(state.resolved_state)
	countermeasure_charges_remaining = int(state.get("countermeasure_charges", definition.countermeasure_charges))
	var countermeasure: Dictionary = state.get("countermeasure", {})
	countermeasure_cooldown = float(countermeasure.get("cooldown", 0.0))
	countermeasure_evasion = float(countermeasure.get("evasion", 0.0))
	countermeasure_kind = StringName(countermeasure.get("kind", ""))
	countermeasure_origin = SaveDocument.vector3_from_data(countermeasure.get("origin", [0, 0, 0]))
	restore_content_state(state.get("content_state", {}), objective_value, battlefield_value, defense_by_id)

func restore_content_state(_state: Dictionary, _objective: ProtectedObjective, _battlefield: Battlefield, _defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	pass

func assigned_target_id() -> int:
	return 0
