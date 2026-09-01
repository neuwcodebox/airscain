class_name CloseInGun
extends DefenseUnit

const TRACER_SCENE := preload("res://effects/tracer_burst/tracer_burst.tscn")

var registry: ThreatRegistry
var projectile_parent: Node3D
var battlefield: Battlefield
var player_knowledge: Node
var c2_network: Node
var doctrine := EngagementDoctrine.new()
var cooldown: float = 0.0
var rng := RandomNumberGenerator.new()
var _definition: CloseInGunDefinition

@onready var turret: Node3D = $Turret
@onready var muzzle: Marker3D = $Turret/Muzzle
@onready var muzzle_flash: MeshInstance3D = $MuzzleFlash

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as CloseInGunDefinition
	rng.seed = id_value ^ 0x4C11DB7

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
		_fire_burst(track)
		cooldown = _definition.burst_interval

func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
	var selected: PlayerTrack
	var selected_score := -INF
	for track: PlayerTrack in tracks:
		if not doctrine.allows(track):
			continue
		var distance := global_position.distance_to(track.estimated_position)
		if distance > _definition.attack_range:
			continue
		if track.track_id == doctrine.priority_track_id:
			return track
		var urgency := 1.0 / maxf(1.0, track.estimated_position.distance_to(protected_position))
		var score := urgency * track.track_quality * weapon_match(track)
		if score > selected_score:
			selected = track
			selected_score = score
	return selected

func weapon_match(track: PlayerTrack) -> float:
	return _definition.preferred_target_match if track.classification == _definition.preferred_class else _definition.other_target_match

func _fire_burst(track: PlayerTrack) -> void:
	var tracer := TRACER_SCENE.instantiate() as TracerBurst
	projectile_parent.add_child(tracer)
	tracer.setup(muzzle.global_position, track.estimated_position)
	muzzle_flash.global_position = muzzle.global_position
	muzzle_flash.visible = true
	get_tree().create_timer(0.06).timeout.connect(func() -> void:
		if is_instance_valid(muzzle_flash):
			muzzle_flash.visible = false
	)
	var distance := global_position.distance_to(track.estimated_position)
	var range_ratio := distance / _definition.attack_range
	var range_factor := 1.0 / (1.0 + pow(range_ratio, 4.0))
	var hit_probability := clampf(_definition.base_accuracy * track.track_quality * range_factor * weapon_match(track), 0.0, 1.0)
	if rng.randf() > hit_probability:
		return
	var target := _physical_target_near(track.estimated_position)
	if target != null:
		target.receive_damage(_definition.burst_damage)

func _physical_target_near(estimated_position: Vector3) -> ThreatUnit:
	var selected: ThreatUnit
	var nearest_distance := _definition.hit_tolerance
	for threat: ThreatUnit in registry.get_active():
		var distance := threat.get_aim_position().distance_to(estimated_position)
		if distance < nearest_distance:
			selected = threat
			nearest_distance = distance
	return selected

func capture_content_state() -> Dictionary:
	return {
		"cooldown": cooldown,
		"rng_state": str(rng.state),
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
	rng.state = int(state.get("rng_state", rng.state))
	var doctrine_state: Dictionary = state.get("doctrine", {})
	doctrine.hold_fire = bool(doctrine_state.get("hold_fire", false))
	doctrine.engage_unknown = bool(doctrine_state.get("engage_unknown", false))
	doctrine.engage_neutral = bool(doctrine_state.get("engage_neutral", false))
	doctrine.minimum_track_quality = float(doctrine_state.get("minimum_track_quality", 0.3))
	doctrine.minimum_classification_confidence = float(doctrine_state.get("minimum_classification_confidence", 0.25))
	doctrine.minimum_affiliation_confidence = float(doctrine_state.get("minimum_affiliation_confidence", 0.3))
	doctrine.priority_track_id = int(doctrine_state.get("priority_track_id", -1))
