class_name EnemyKnowledge
extends Node

const MAX_REPORTS := 96
const MAX_OUTCOMES := 24

var simulation_time: float = 0.0
var estimates: Dictionary[int, Dictionary] = {}
var reports: Array[Dictionary] = []
var recent_outcomes: Array[Dictionary] = []
var defense_parent: Node3D

var battlefield: Battlefield
var search := ReconSearch.new()
var sightings: Dictionary[int, Dictionary] = {}

func configure_recon(assets: Node3D, world: Battlefield, size: float) -> void:
	defense_parent = assets
	battlefield = world
	search.configure(size)
	_configure_land_search()

func _configure_land_search() -> void:
	if battlefield == null:
		return
	var land: Array[int] = []
	for cell: int in search.width() * search.width():
		var point := search.center(cell)
		if battlefield.terrain_height(point.x, point.z) > battlefield.generator.sea_level:
			land.append(cell)
	search.configure(search.extent * 2.0, land)

func search_target(owner: int, position: Vector3) -> Vector3:
	var clues: Array[Dictionary] = []
	clues.assign(estimates.values())
	var target := search.choose(owner, position, simulation_time, clues)
	if battlefield != null:
		target.y = battlefield.flight_surface_height(target.x, target.z)
	return target

func visible_from(observer: Vector3, point: Vector3, radius: float) -> bool:
	if Vector2(point.x - observer.x, point.z - observer.z).length() > radius:
		return false
	return battlefield == null or (not battlefield.building_blocks_segment(observer, point) and battlefield.terrain_segment_impact(observer, point).is_empty())

func record_recon_area(position: Vector3, radius: float, duration: float = 0.5) -> void:
	if not is_instance_valid(defense_parent):
		return
	for cell: int in search.width() * search.width():
		var point := search.center(cell)
		if Vector2(point.x - position.x, point.z - position.z).length() > radius:
			continue
		if battlefield != null:
			point.y = battlefield.flight_surface_height(point.x, point.z) + 2.0
		if visible_from(position, point, radius):
			search.seen[cell] = simulation_time
	var observed: Dictionary[int, bool] = {}
	for child: Node in defense_parent.get_children():
		var asset := child as DefenseUnit
		if asset == null or not asset.active or not visible_from(position, asset.global_position + Vector3.UP * 3.0, radius):
			continue
		var id := asset.runtime_id
		observed[id] = true
		var sight: Dictionary = sightings.get(id, {"seconds": 0.0, "time": -10.0})
		# Observing the same instant with several cameras is not extra dwell time.
		if float(sight.time) == simulation_time:
			continue
		if simulation_time - float(sight.time) > 2.0:
			sight.seconds = 0.0
		sight.seconds = minf(4.0, float(sight.seconds) + minf(duration, maxf(0.0, simulation_time - float(sight.time))))
		sight.time = simulation_time
		sightings[id] = sight
		var progress := float(sight.seconds) / 4.0
		_record_asset(asset, "reconnaissance", lerpf(0.25, 0.92, progress), lerpf(100.0, 24.0, progress), float(sight.seconds) >= 1.5)
	# Only reject a stale report when its uncertainty area is inside the view.
	for id: int in estimates.keys():
		if observed.has(id):
			continue
		var estimate := estimates[id]
		var point := SaveDocument.vector3_from_data(estimate.estimated_position) + Vector3.UP * 3.0
		if float(estimate.uncertainty) < radius and visible_from(position, point, radius - float(estimate.uncertainty)):
			estimates.erase(id)
			sightings.erase(id)

func reset() -> void:
	simulation_time = 0.0
	estimates.clear()
	reports.clear()
	recent_outcomes.clear()
	search.reset()
	sightings.clear()

func gameplay_tick(delta: float) -> void:
	simulation_time += delta
	for id: int in sightings.keys():
		if simulation_time - float(sightings[id].time) > 10.0:
			sightings.erase(id)
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

func discard_estimate_at(asset_id: int, searched_position: Vector3, search_range: float) -> void:
	var estimate: Dictionary = estimates.get(asset_id, {})
	if not estimate.is_empty() and SaveDocument.vector3_from_data(estimate.estimated_position).distance_to(searched_position) <= search_range:
		estimates.erase(asset_id)

func best_estimate_for_role(role: StringName, assignments: Dictionary[int, int] = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for estimate: Dictionary in estimates.values():
		var assigned: int = assignments.get(int(estimate.asset_id), 0)
		if StringName(estimate.role) != role or assigned >= 2:
			continue
		var score := float(estimate.confidence) / (1.0 + 4.0 * assigned)
		if score > best_score:
			best_score = score
			best = estimate
	return best

func capture_state() -> Dictionary:
	var estimate_states: Array[Dictionary] = []
	for estimate: Dictionary in estimates.values():
		estimate_states.append(estimate.duplicate(true))
	return {"simulation_time": simulation_time, "estimates": estimate_states, "reports": reports.duplicate(true), "recent_outcomes": recent_outcomes.duplicate(true), "recon_search": search.capture_state(), "recon_sightings": _capture_sightings()}

func restore_state(state: Dictionary) -> void:
	reset()
	simulation_time = float(state.get("simulation_time", 0.0))
	_configure_land_search()
	search.restore_state(state.get("recon_search", {}))
	for sight: Dictionary in state.get("recon_sightings", []):
		sightings[int(sight.id)] = {"seconds": float(sight.seconds), "time": float(sight.time)}
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

func _record_asset(asset: DefenseUnit, source: String, confidence: float, uncertainty: float, classified: bool = true) -> void:
	if asset == null or not is_instance_valid(asset):
		return
	var role := _role_for(asset) if classified else &""
	var offset_angle := fmod(float(asset.runtime_id) * 2.399963 + simulation_time * 0.01, TAU)
	var existing: Dictionary = estimates.get(asset.runtime_id, {})
	if not existing.is_empty() and float(existing.confidence) > confidence and SaveDocument.vector3_from_data(existing.estimated_position).distance_to(asset.global_position) <= float(existing.uncertainty):
		confidence = float(existing.confidence)
		uncertainty = minf(uncertainty, float(existing.uncertainty))
	if role == &"" and not existing.is_empty():
		role = StringName(existing.role)
	var estimated_position := asset.global_position + Vector3(cos(offset_angle), 0.0, sin(offset_angle)) * uncertainty * (1.0 - confidence)
	var estimate := {"asset_id": asset.runtime_id, "role": String(role), "estimated_position": SaveDocument.vector3_to_data(estimated_position), "confidence": confidence, "uncertainty": uncertainty, "observed_at": simulation_time, "source": source}
	estimates[asset.runtime_id] = estimate
	reports.append({"source": source, "asset_id": asset.runtime_id, "role": String(role), "position": SaveDocument.vector3_to_data(estimated_position), "confidence": confidence, "observed_at": simulation_time})
	if reports.size() > MAX_REPORTS:
		reports.pop_front()

func _role_for(asset: DefenseUnit) -> StringName:
	return asset.definition.enemy_knowledge_role()

func _capture_sightings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in sightings:
		result.append({"id": id, "seconds": sightings[id].seconds, "time": sightings[id].time})
	return result

static func recon_validation_error(state: Dictionary, size: float, defense_ids: Dictionary[int, bool]) -> String:
	if not state.get("recon_search", {}) is Dictionary or not state.get("recon_sightings", []) is Array:
		return "정찰 기억 상태가 올바르지 않습니다"
	var planner := ReconSearch.new()
	planner.configure(size)
	var error := planner.validation_error(state.get("recon_search", {}), float(state.simulation_time))
	if not error.is_empty():
		return error
	var ids: Dictionary[int, bool] = {}
	for value: Variant in state.get("recon_sightings", []):
		if not value is Dictionary:
			return "정찰 관측 누적 상태가 올바르지 않습니다"
		var id := int(value.get("id", 0))
		var seconds := float(value.get("seconds", -1.0))
		var time := float(value.get("time", -1.0))
		if not defense_ids.has(id) or ids.has(id) or not is_finite(seconds) or seconds < 0.0 or seconds > 4.0 or not is_finite(time) or time < 0.0 or time > float(state.simulation_time):
			return "정찰 관측 누적 값이 올바르지 않습니다"
		ids[id] = true
	return ""
