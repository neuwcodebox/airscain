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
	return _definition.c2_range

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
	var range_ratio := maxf(0.0, distance) / _definition.detection_range
	var range_factor := 1.0 / (1.0 + pow(range_ratio, _definition.range_exponent))
	return clampf(_definition.sensor_quality * range_factor, 0.0, 1.0)

func _scan() -> void:
	var sensor_position := global_position + Vector3.UP * 11.0
	for threat: ThreatUnit in registry.get_active():
		var target_position := threat.get_aim_position()
		var distance := sensor_position.distance_to(target_position)
		if distance > _definition.detection_range or not _has_line_of_sight(sensor_position, target_position):
			continue
		var signature := threat.get_sensor_signature()
		var quality := signal_quality_for(distance) * float(signature.radar_factor)
		var observation := SensorObservation.new()
		observation.setup(runtime_id, float(player_knowledge.get("simulation_time")), target_position, quality, lerpf(5.0, 45.0, 1.0 - quality), _definition.scan_interval, signature.classification_hint, int(signature.affiliation_hint), quality * 0.55)
		player_knowledge.call("submit_observation", observation)

func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	for sample_index: int in range(1, 12):
		var weight := float(sample_index) / 12.0
		var sample_position := from.lerp(to, weight)
		if battlefield.terrain_height(sample_position.x, sample_position.z) + 2.0 > sample_position.y:
			return false
	return true
