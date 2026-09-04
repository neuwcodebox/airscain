class_name EnemyKnowledge
extends Node

const MAX_REPORTS := 96
const MAX_OUTCOMES := 24

var simulation_time: float = 0.0
var estimates: Dictionary[int, Dictionary] = {}
var reports: Array[Dictionary] = []
var recent_outcomes: Array[Dictionary] = []

func reset() -> void:
	simulation_time = 0.0
	estimates.clear()
	reports.clear()
	recent_outcomes.clear()

func gameplay_tick(delta: float) -> void:
	simulation_time += delta
	for asset_id: int in estimates.keys():
		var estimate := estimates[asset_id]
		estimate.confidence = float(estimate.confidence) * exp(-delta / 150.0)
		estimate.uncertainty = minf(500.0, float(estimate.uncertainty) + delta * 0.8)
		estimates[asset_id] = estimate
		if float(estimate.confidence) < 0.05:
			estimates.erase(asset_id)

func record_emission(asset: DefenseUnit) -> void:
	_record_asset(asset, "radar_emission", 0.42, 120.0)

func record_engagement(asset: DefenseUnit, weapon_role: StringName) -> void:
	_record_asset(asset, "engagement:%s" % weapon_role, 0.62, 70.0)

func record_recon(target: DefenseUnit) -> void:
	if target != null:
		_record_asset(target, "reconnaissance", 0.92, 24.0)

func record_outcome(neutralized: bool, position: Vector3, threat_id: StringName) -> void:
	recent_outcomes.append({"neutralized": neutralized, "position": SaveDocument.vector3_to_data(position), "threat_id": String(threat_id), "observed_at": simulation_time})
	if recent_outcomes.size() > MAX_OUTCOMES:
		recent_outcomes.pop_front()

func best_estimate_for_role(role: StringName) -> Dictionary:
	var best: Dictionary = {}
	for estimate: Dictionary in estimates.values():
		if StringName(estimate.role) == role and (best.is_empty() or float(estimate.confidence) > float(best.confidence)):
			best = estimate
	return best

func capture_state() -> Dictionary:
	var estimate_states: Array[Dictionary] = []
	for estimate: Dictionary in estimates.values():
		estimate_states.append(estimate.duplicate(true))
	return {"simulation_time": simulation_time, "estimates": estimate_states, "reports": reports.duplicate(true), "recent_outcomes": recent_outcomes.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	reset()
	simulation_time = float(state.get("simulation_time", 0.0))
	for estimate: Dictionary in state.get("estimates", []):
		var normalized := estimate.duplicate(true)
		normalized.asset_id = int(estimate.asset_id)
		estimates[int(normalized.asset_id)] = normalized
	for report: Dictionary in state.get("reports", []):
		var normalized := report.duplicate(true)
		normalized.asset_id = int(report.asset_id)
		reports.append(normalized)
	for outcome: Dictionary in state.get("recent_outcomes", []):
		recent_outcomes.append(outcome.duplicate(true))

func _record_asset(asset: DefenseUnit, source: String, confidence: float, uncertainty: float) -> void:
	if asset == null or not is_instance_valid(asset):
		return
	var role := _role_for(asset)
	var offset_angle := fmod(float(asset.runtime_id) * 2.399963 + simulation_time * 0.01, TAU)
	var estimated_position := asset.global_position + Vector3(cos(offset_angle), 0.0, sin(offset_angle)) * uncertainty * (1.0 - confidence)
	var existing: Dictionary = estimates.get(asset.runtime_id, {})
	if not existing.is_empty() and float(existing.confidence) > confidence:
		confidence = float(existing.confidence)
		uncertainty = minf(uncertainty, float(existing.uncertainty))
	var estimate := {"asset_id": asset.runtime_id, "role": String(role), "estimated_position": SaveDocument.vector3_to_data(estimated_position), "confidence": confidence, "uncertainty": uncertainty, "observed_at": simulation_time, "source": source}
	estimates[asset.runtime_id] = estimate
	reports.append({"source": source, "asset_id": asset.runtime_id, "role": String(role), "position": SaveDocument.vector3_to_data(estimated_position), "confidence": confidence, "observed_at": simulation_time})
	if reports.size() > MAX_REPORTS:
		reports.pop_front()

func _role_for(asset: DefenseUnit) -> StringName:
	return asset.definition.enemy_knowledge_role()
