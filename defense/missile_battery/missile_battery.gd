class_name MissileBattery
extends DefenseUnit

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")

var registry: ThreatRegistry
var projectile_parent: Node3D
var battlefield: Battlefield
var player_knowledge: Node
var c2_network: Node
var doctrine := EngagementDoctrine.new()
var cooldown: float = 0.0
var _definition: MissileBatteryDefinition
var interceptors: Array[HomingInterceptor] = []

@onready var turret: Node3D = $Turret
@onready var launch_point: Marker3D = $Turret/LaunchPoint

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as MissileBatteryDefinition

func configure_combat(registry_value: ThreatRegistry, projectile_parent_value: Node3D) -> void:
	registry = registry_value
	projectile_parent = projectile_parent_value

func configure_player_knowledge(battlefield_value: Battlefield, player_knowledge_value: Node) -> void:
	battlefield = battlefield_value
	player_knowledge = player_knowledge_value

func configure_c2(network: Node) -> void:
	c2_network = network

func c2_roles() -> int:
	return C2Role.DEFENSE

func c2_link_range() -> float:
	return _definition.c2_range

func set_hold_fire(enabled: bool) -> void:
	doctrine.hold_fire = enabled

func set_engage_unknown(enabled: bool) -> void:
	doctrine.engage_unknown = enabled

func set_priority_track(track_id: int) -> void:
	doctrine.priority_track_id = track_id

func gameplay_tick(delta: float) -> void:
	if not active or registry == null or player_knowledge == null or c2_network == null:
		return
	for index: int in range(interceptors.size() - 1, -1, -1):
		var interceptor := interceptors[index]
		if not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
			interceptors.remove_at(index)
		else:
			interceptor.gameplay_tick(delta)
	cooldown = maxf(0.0, cooldown - delta)
	var known_tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	var available_tracks: Array[PlayerTrack] = c2_network.call("available_tracks_for", self, known_tracks)
	var track := select_track(available_tracks, battlefield.objective.global_position)
	if track == null:
		return
	var flat_target := Vector3(track.estimated_position.x, turret.global_position.y, track.estimated_position.z)
	if turret.global_position.distance_squared_to(flat_target) > 0.01:
		turret.look_at(flat_target, Vector3.UP)
	if cooldown <= 0.0:
		_launch(track)
		cooldown = _definition.fire_interval

func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
	var selected: PlayerTrack
	var selected_urgency := -INF
	var selected_distance := INF
	for track: PlayerTrack in tracks:
		if not doctrine.allows(track):
			continue
		var distance := global_position.distance_to(track.estimated_position)
		if distance > _definition.attack_range:
			continue
		if track.track_id == doctrine.priority_track_id:
			return track
		var urgency := track.track_quality / maxf(1.0, track.estimated_position.distance_to(protected_position))
		if urgency > selected_urgency or (is_equal_approx(urgency, selected_urgency) and distance < selected_distance):
			selected = track
			selected_urgency = urgency
			selected_distance = distance
	return selected

func _launch(track: PlayerTrack) -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	projectile_parent.add_child(interceptor)
	interceptor.global_position = launch_point.global_position
	var initial_direction := launch_point.global_position.direction_to(track.estimated_position)
	interceptor.configure(track, registry, _definition, initial_direction, runtime_id)
	interceptors.append(interceptor)
	$MuzzleFlash.global_position = launch_point.global_position
	$MuzzleFlash.visible = true
	get_tree().create_timer(0.08).timeout.connect(func() -> void: $MuzzleFlash.visible = false)

func capture_content_state() -> Dictionary:
	return {
		"cooldown": cooldown,
		"doctrine": {
			"hold_fire": doctrine.hold_fire,
			"engage_unknown": doctrine.engage_unknown,
			"engage_neutral": doctrine.engage_neutral,
			"minimum_track_quality": doctrine.minimum_track_quality,
			"minimum_classification_confidence": doctrine.minimum_classification_confidence,
			"minimum_affiliation_confidence": doctrine.minimum_affiliation_confidence,
			"priority_track_id": doctrine.priority_track_id,
		},
	}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	var doctrine_state: Dictionary = state.get("doctrine", {})
	doctrine.hold_fire = bool(doctrine_state.get("hold_fire", false))
	doctrine.engage_unknown = bool(doctrine_state.get("engage_unknown", false))
	doctrine.engage_neutral = bool(doctrine_state.get("engage_neutral", false))
	doctrine.minimum_track_quality = float(doctrine_state.get("minimum_track_quality", 0.3))
	doctrine.minimum_classification_confidence = float(doctrine_state.get("minimum_classification_confidence", 0.25))
	doctrine.minimum_affiliation_confidence = float(doctrine_state.get("minimum_affiliation_confidence", 0.3))
	doctrine.priority_track_id = int(doctrine_state.get("priority_track_id", -1))
