class_name SearchRadar
extends DefenseUnit

@export var rotation_speed_degrees: float = 36.0

var registry: ThreatRegistry
var battlefield: Battlefield
var player_knowledge: Node
var scan_cooldown: float = 0.0
var _definition: SearchRadarDefinition

@onready var antenna: Node3D = $Antenna

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as SearchRadarDefinition
	scan_cooldown = 0.0

func configure_combat(registry_value: ThreatRegistry, _projectile_parent: Node3D) -> void:
	registry = registry_value

func configure_player_knowledge(battlefield_value: Battlefield, player_knowledge_value: Node) -> void:
	battlefield = battlefield_value
	player_knowledge = player_knowledge_value

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
	var effective_range := _definition.detection_range * operational_efficiency()
	if effective_range <= 0.0:
		return 0.0
	var range_ratio := maxf(0.0, distance) / effective_range
	var range_factor := 1.0 / (1.0 + pow(range_ratio, _definition.range_exponent))
	var jamming_multiplier := 1.0
	if registry != null:
		jamming_multiplier = 1.0 - registry.jamming_at(global_position) * 0.75
	return clampf(_definition.sensor_quality * range_factor * jamming_multiplier, 0.0, 1.0)

func altitude_in_envelope(target_position: Vector3) -> bool:
	if battlefield == null:
		return false
	var altitude := target_position.y - battlefield.terrain_height(target_position.x, target_position.z)
	return altitude >= _definition.minimum_detection_altitude and altitude <= _definition.maximum_detection_altitude

func resource_status_text() -> String:
	return "%s\n감시 고도 %d–%dm · 탐지거리 %dm" % [super.resource_status_text(), roundi(_definition.minimum_detection_altitude), roundi(_definition.maximum_detection_altitude), roundi(_definition.detection_range)]

func _scan() -> void:
	if enemy_knowledge != null:
		enemy_knowledge.record_emission(self)
	var sensor_position := global_position + Vector3.UP * 11.0
	for threat: ThreatUnit in registry.get_active():
		var target_position := threat.get_aim_position()
		if not altitude_in_envelope(target_position):
			continue
		var distance := sensor_position.distance_to(target_position)
		if distance > _definition.detection_range * operational_efficiency() or not _has_line_of_sight(sensor_position, target_position):
			continue
		var signature := threat.get_sensor_signature()
		var quality := signal_quality_for(distance) * float(signature.radar_factor)
		var observation := SensorObservation.new()
		observation.setup(runtime_id, float(player_knowledge.get("simulation_time")), target_position, quality, lerpf(5.0, 45.0, 1.0 - quality), _definition.scan_interval, signature.classification_hint, int(signature.affiliation_hint), quality * 0.55)
		player_knowledge.call("submit_observation", observation)
		_submit_false_echoes(threat, target_position, quality, signature)

func _submit_false_echoes(threat: ThreatUnit, target_position: Vector3, quality: float, signature: Dictionary) -> void:
	var echo_count := threat.definition.false_echo_count
	if echo_count <= 0:
		return
	for echo_index: int in echo_count:
		var angle := fposmod(float(threat.runtime_id) * 1.618034 + TAU * float(echo_index) / float(echo_count), TAU)
		var echo_position := target_position + Vector3(cos(angle), 0.0, sin(angle)) * threat.definition.false_echo_radius
		var echo_quality := quality * 0.78
		var echo := SensorObservation.new()
		echo.setup(runtime_id, float(player_knowledge.get("simulation_time")), echo_position, echo_quality, lerpf(18.0, 70.0, 1.0 - echo_quality), _definition.scan_interval, signature.classification_hint, int(signature.affiliation_hint), echo_quality * 0.45)
		player_knowledge.call("submit_observation", echo)

func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	for sample_index: int in range(1, 12):
		var weight := float(sample_index) / 12.0
		var sample_position := from.lerp(to, weight)
		if battlefield.terrain_height(sample_position.x, sample_position.z) + 2.0 > sample_position.y:
			return false
	return true

func capture_content_state() -> Dictionary:
	return {"scan_cooldown": scan_cooldown}

func restore_content_state(state: Dictionary) -> void:
	scan_cooldown = float(state.get("scan_cooldown", 0.0))
