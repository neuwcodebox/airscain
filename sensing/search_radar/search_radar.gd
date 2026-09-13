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
var _tracking_scheduler := RadarTrackingScheduler.new()
var _tracking_coordinator: RadarTrackingCoordinator

@onready var antenna: Node3D = $Antenna

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as SearchRadarDefinition
	scan_cooldown = 0.0
	tracked_contacts.clear()
	scan_index = 0
	saturated = false
	_tracking_scheduler.setup(runtime_id, _definition.tracking_capacity)

func configure_combat(registry_value: ThreatRegistry, _projectile_parent: Node3D) -> void:
	registry = registry_value

func configure_player_knowledge(battlefield_value: Battlefield, player_knowledge_value: PlayerKnowledge) -> void:
	battlefield = battlefield_value
	player_knowledge = player_knowledge_value

func configure_engagements(coordinator: EngagementCoordinator) -> void:
	engagement_coordinator = coordinator

func configure_sensor_tracking(coordinator: RadarTrackingCoordinator) -> void:
	_tracking_coordinator = coordinator

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
	var candidates: Array[RadarTrackCandidate] = []
	for threat: ThreatUnit in registry.get_active():
		var target_position := threat.get_aim_position()
		if not altitude_in_envelope(target_position):
			continue
		var distance := sensor_position.distance_to(target_position)
		if distance > effective_range or not _has_line_of_sight(sensor_position, target_position):
			continue
		var signature := threat.get_sensor_signature()
		var quality := _signal_quality(distance, effective_range, jamming_multiplier) * float(signature.radar_factor)
		candidates.append(_candidate("threat:%d" % threat.runtime_id, threat, target_position, quality, signature, false))
		_append_false_echoes(candidates, threat, target_position, quality, signature)
	_apply_tracking_capacity(candidates, timestamp)

func _candidate(
	key: String,
	threat: ThreatUnit,
	measured_position: Vector3,
	quality: float,
	signature: Dictionary,
	false_echo: bool,
) -> RadarTrackCandidate:
	var track_id := int(tracked_contacts.get(key, 0))
	var actively_engaged := track_id > 0 and engagement_coordinator != null and engagement_coordinator.has_reservation(track_id)
	var candidate := RadarTrackCandidate.new()
	var priority := _tracking_scheduler.priority_for(threat, quality, tracked_contacts.has(key), actively_engaged)
	candidate.setup(key, measured_position, quality, StringName(signature.classification_hint), int(signature.affiliation_hint), false_echo, priority)
	return candidate

func _append_false_echoes(candidates: Array[RadarTrackCandidate], threat: ThreatUnit, target_position: Vector3, quality: float, signature: Dictionary) -> void:
	var echo_count := threat.definition.false_echo_count
	if echo_count <= 0:
		return
	for echo_index: int in echo_count:
		var angle := fposmod(float(threat.runtime_id) * 1.618034 + float(runtime_id) * 0.754877 + TAU * float(echo_index) / float(echo_count), TAU)
		var echo_position := target_position + Vector3(cos(angle), 0.0, sin(angle)) * threat.definition.false_echo_radius
		var echo_quality := quality * 0.78
		candidates.append(_candidate("echo:%d:%d" % [threat.runtime_id, echo_index], threat, echo_position, echo_quality, signature, true))

func _apply_tracking_capacity(candidates: Array[RadarTrackCandidate], timestamp: float) -> void:
	var candidate_keys: Dictionary[String, bool] = {}
	for candidate: RadarTrackCandidate in candidates:
		candidate_keys[candidate.key] = true
	saturated = candidates.size() > _definition.tracking_capacity
	var support_counts: Dictionary[String, int] = {}
	if _tracking_coordinator != null:
		support_counts = _tracking_coordinator.support_counts_excluding(runtime_id, timestamp)
	var selected := _tracking_scheduler.select(candidates, scan_index, support_counts)
	var next_contacts := _submit_observations(selected, timestamp)
	var selected_keys: Array[String] = []
	for candidate: RadarTrackCandidate in selected:
		selected_keys.append(candidate.key)
	if _tracking_coordinator != null:
		_tracking_coordinator.renew_lease(runtime_id, selected_keys, timestamp, _definition.scan_interval)
	for key: String in tracked_contacts:
		if candidate_keys.has(key) and not next_contacts.has(key):
			player_knowledge.note_capacity_gap(tracked_contacts[key], runtime_id, timestamp)
	tracked_contacts = next_contacts
	scan_index += 1

func _submit_observations(selected: Array[RadarTrackCandidate], timestamp: float) -> Dictionary[String, int]:
	var observed_contacts: Dictionary[String, int] = {}
	var observations: Array[SensorObservation] = []
	for candidate: RadarTrackCandidate in selected:
		var observation := SensorObservation.new()
		var uncertainty := lerpf(18.0, 70.0, 1.0 - candidate.quality) if candidate.false_echo else lerpf(5.0, 45.0, 1.0 - candidate.quality)
		var identity_scale := 0.45 if candidate.false_echo else 0.55
		observation.setup(runtime_id, timestamp, candidate.measured_position, candidate.quality, uncertainty, _definition.scan_interval, candidate.classification_hint, candidate.affiliation_hint, candidate.quality * identity_scale)
		observations.append(observation)
	var submitted_tracks := player_knowledge.submit_scan(observations)
	for candidate_index: int in selected.size():
		observed_contacts[selected[candidate_index].key] = submitted_tracks[candidate_index].track_id
	return observed_contacts

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
