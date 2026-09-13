class_name SearchRadar
extends DefenseUnit

@export var rotation_speed_degrees: float = 36.0

var registry: ThreatRegistry
var battlefield: Battlefield
var player_knowledge: PlayerKnowledge
var scan_cooldown: float = 0.0
var engagement_coordinator: EngagementCoordinator
var tracked_contacts: Dictionary[String, int] = {}
var scan_index: int = 0
var saturated: bool = false
var _definition: SearchRadarDefinition

@onready var antenna: Node3D = $Antenna

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as SearchRadarDefinition
	scan_cooldown = 0.0
	tracked_contacts.clear()
	scan_index = 0
	saturated = false

func configure_combat(registry_value: ThreatRegistry, _projectile_parent: Node3D) -> void:
	registry = registry_value

func configure_player_knowledge(battlefield_value: Battlefield, player_knowledge_value: PlayerKnowledge) -> void:
	battlefield = battlefield_value
	player_knowledge = player_knowledge_value

func configure_engagements(coordinator: EngagementCoordinator) -> void:
	engagement_coordinator = coordinator

func c2_roles() -> int:
	return C2Role.SENSOR

func c2_link_range() -> float:
	return _definition.c2_range * operational_efficiency()

func local_sensor_ids() -> Array[int]:
	return [runtime_id]

func gameplay_tick(delta: float) -> void:
	if not active:
		return
	antenna.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
	if registry == null or battlefield == null or player_knowledge == null:
		return
	scan_cooldown -= delta
	if scan_cooldown > 0.0:
		return
	scan_cooldown += _definition.scan_interval
	_scan()

func signal_quality_for(distance: float) -> float:
	return _signal_quality(distance, _definition.detection_range * operational_efficiency(), _jamming_multiplier())

func _jamming_multiplier() -> float:
	return 1.0 - registry.jamming_at(global_position) * 0.75 if registry != null else 1.0

func _signal_quality(distance: float, effective_range: float, jamming_multiplier: float) -> float:
	if effective_range <= 0.0:
		return 0.0
	var range_ratio := maxf(0.0, distance) / effective_range
	var range_factor := 1.0 / (1.0 + pow(range_ratio, _definition.range_exponent))
	return clampf(_definition.sensor_quality * range_factor * jamming_multiplier, 0.0, 1.0)

func altitude_in_envelope(target_position: Vector3) -> bool:
	if battlefield == null:
		return false
	var altitude := target_position.y - battlefield.terrain_height(target_position.x, target_position.z)
	return altitude >= _definition.minimum_detection_altitude and altitude <= _definition.maximum_detection_altitude

func resource_status_text() -> String:
	return "%s\n감시 고도 %d–%dm · 탐지거리 %dm\n동시 추적 %d/%d" % [super.resource_status_text(), roundi(_definition.minimum_detection_altitude), roundi(_definition.maximum_detection_altitude), roundi(_definition.detection_range), current_tracking_count(), _definition.tracking_capacity]

func selection_status_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [{"label": "동시 추적", "value": "%d / %d" % [current_tracking_count(), _definition.tracking_capacity], "warning": active and saturated}]
	rows.append_array(_selection_task_rows())
	return rows

func current_tracking_count() -> int:
	return tracked_contacts.size() if active else 0

func _scan() -> void:
	if enemy_knowledge != null:
		enemy_knowledge.record_emission(self)
	var sensor_position := global_position + Vector3.UP * 11.0
	# These values are common to every contact in this instantaneous scan.
	var effective_range := _definition.detection_range * operational_efficiency()
	var jamming_multiplier := _jamming_multiplier()
	var timestamp := player_knowledge.simulation_time
	var candidates: Array[Dictionary] = []
	for threat: ThreatUnit in registry.get_active():
		var target_position := threat.get_aim_position()
		if not altitude_in_envelope(target_position):
			continue
		var distance := sensor_position.distance_to(target_position)
		if distance > effective_range or not _has_line_of_sight(sensor_position, target_position):
			continue
		var signature := threat.get_sensor_signature()
		var quality := _signal_quality(distance, effective_range, jamming_multiplier) * float(signature.radar_factor)
		candidates.append(_candidate("threat:%d" % threat.runtime_id, threat, target_position, quality, signature))
		_append_false_echoes(candidates, threat, target_position, quality, signature)
	_apply_tracking_capacity(candidates, timestamp)

func _candidate(key: String, threat: ThreatUnit, measured_position: Vector3, quality: float, signature: Dictionary) -> Dictionary:
	return {
		"key": key,
		"threat": threat,
		"position": measured_position,
		"quality": quality,
		"signature": signature,
		"priority": _tracking_priority(key, threat, quality),
	}

func _append_false_echoes(candidates: Array[Dictionary], threat: ThreatUnit, target_position: Vector3, quality: float, signature: Dictionary) -> void:
	var echo_count := threat.definition.false_echo_count
	if echo_count <= 0:
		return
	for echo_index: int in echo_count:
		var angle := fposmod(float(threat.runtime_id) * 1.618034 + float(runtime_id) * 0.754877 + TAU * float(echo_index) / float(echo_count), TAU)
		var echo_position := target_position + Vector3(cos(angle), 0.0, sin(angle)) * threat.definition.false_echo_radius
		var echo_quality := quality * 0.78
		candidates.append(_candidate("echo:%d:%d" % [threat.runtime_id, echo_index], threat, echo_position, echo_quality, signature))

func _tracking_priority(key: String, threat: ThreatUnit, quality: float) -> float:
	var expected_damage := 0.0
	var mission := threat.definition.mission_definition()
	if mission != null and threat.definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
		expected_damage = mission.damage
	var seconds := threat.presentation_action_seconds()
	var imminent_risk := expected_damage / maxf(3.0, seconds) if is_finite(seconds) else 0.0
	var continuity := 0.2 if tracked_contacts.has(key) else 0.0
	var engagement_support := 0.0
	var track_id := int(tracked_contacts.get(key, 0))
	if track_id > 0 and engagement_coordinator != null and engagement_coordinator.has_reservation(track_id):
		engagement_support = 1000.0
	# Nearby radars naturally disagree on signal strength. This small stable bias
	# also prevents colocated sensors from choosing identical marginal contacts.
	var diversity := float(posmod(key.hash() ^ runtime_id * 1103515245, 1000)) / 1000.0
	return engagement_support + imminent_risk + quality * 0.25 + continuity + diversity * 0.08

func _apply_tracking_capacity(candidates: Array[Dictionary], timestamp: float) -> void:
	var candidate_keys: Dictionary[String, bool] = {}
	for candidate: Dictionary in candidates:
		candidate_keys[String(candidate.key)] = true
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_priority := float(first.priority)
		var second_priority := float(second.priority)
		return String(first.key) < String(second.key) if is_equal_approx(first_priority, second_priority) else first_priority > second_priority
	)
	var selected: Array[Dictionary] = []
	saturated = candidates.size() > _definition.tracking_capacity
	if not saturated:
		selected = candidates
	else:
		var cycling_slots := _definition.tracking_capacity / 5
		var stable_slots := _definition.tracking_capacity - cycling_slots
		selected.append_array(candidates.slice(0, stable_slots))
		var remainder := candidates.slice(stable_slots)
		if cycling_slots > 0:
			var start := posmod(scan_index * cycling_slots + runtime_id, remainder.size())
			for offset: int in mini(cycling_slots, remainder.size()):
				selected.append(remainder[(start + offset) % remainder.size()])
	var next_contacts: Dictionary[String, int] = {}
	for candidate: Dictionary in selected:
		var observation := SensorObservation.new()
		var quality := float(candidate.quality)
		var signature := candidate.signature as Dictionary
		var uncertainty := lerpf(18.0, 70.0, 1.0 - quality) if String(candidate.key).begins_with("echo:") else lerpf(5.0, 45.0, 1.0 - quality)
		var identity_scale := 0.45 if String(candidate.key).begins_with("echo:") else 0.55
		observation.setup(runtime_id, timestamp, candidate.position, quality, uncertainty, _definition.scan_interval, signature.classification_hint, int(signature.affiliation_hint), quality * identity_scale)
		var track := player_knowledge.submit_observation(observation)
		next_contacts[String(candidate.key)] = track.track_id
	for key: String in tracked_contacts:
		if candidate_keys.has(key) and not next_contacts.has(key):
			player_knowledge.note_capacity_gap(tracked_contacts[key], runtime_id, timestamp)
	tracked_contacts = next_contacts
	scan_index += 1

func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return TerrainLineOfSight.is_clear(battlefield, from, to)

func capture_content_state() -> Dictionary:
	var assignments: Array[Dictionary] = []
	for key: String in tracked_contacts:
		assignments.append({"key": key, "track_id": tracked_contacts[key]})
	assignments.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return String(first.key) < String(second.key))
	return {"scan_cooldown": scan_cooldown, "scan_index": scan_index, "tracked_contacts": assignments}

func restore_content_state(state: Dictionary) -> void:
	scan_cooldown = float(state.get("scan_cooldown", 0.0))
	scan_index = int(state.get("scan_index", 0))
	tracked_contacts.clear()
	for assignment: Dictionary in state.get("tracked_contacts", []):
		tracked_contacts[String(assignment.key)] = int(assignment.track_id)
	saturated = false
