class_name HomingInterceptor
extends Node3D

const MISS_EFFECT_SCENE := preload("res://effects/interceptor_miss/interceptor_miss.tscn")
const DETONATION_SCENE := preload("res://effects/explosion/explosion.tscn")
const COUNTERMEASURE_SCENE := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
const INTERCEPT_GUIDANCE := preload("res://defense/intercept_guidance.gd")

var target_track: PlayerTrack
var registry: ThreatRegistry
var owner_defense_id: int
var speed: float = 200.0
var turn_rate: float = deg_to_rad(240.0)
var maximum_lifetime: float = 5.0
var damage: float = 100.0
var proximity_radius: float = 15.0
var age: float = 0.0
var velocity: Vector3 = Vector3.FORWARD
var infrared_sensitivity: float = 0.65
var radar_sensitivity: float = 0.65
var countermeasure_attempted: bool = false
var countermeasure_decoy_active: bool = false
var countermeasure_decoy_position: Vector3
var target_resolved: bool = false
var target_resolution_reason: String = "표적 소실"
var closest_guidance_distance: float = INF
var rng := RandomNumberGenerator.new()

func configure(track_value: PlayerTrack, registry_value: ThreatRegistry, definition: MissileMunitionDefinition, initial_direction: Vector3, owner_id: int = 0, launch_sequence: int = 0) -> void:
	target_track = track_value
	registry = registry_value
	owner_defense_id = owner_id
	speed = definition.interceptor_speed
	turn_rate = deg_to_rad(definition.interceptor_turn_rate_degrees)
	maximum_lifetime = definition.interceptor_lifetime
	damage = definition.interceptor_damage
	proximity_radius = definition.proximity_radius
	infrared_sensitivity = definition.infrared_sensitivity
	radar_sensitivity = definition.radar_sensitivity
	velocity = initial_direction.normalized() * speed
	rng.seed = owner_defense_id ^ track_value.track_id ^ launch_sequence * 0x45D9F3B ^ 0x5E3C9A
	_connect_registry_signal()

func gameplay_tick(delta: float) -> void:
	if target_resolved:
		_expire(Color(0.86, 0.72, 0.42), target_resolution_reason)
		return
	if target_track == null or target_track.state == PlayerTrack.State.LOST:
		_expire(Color(0.62, 0.72, 0.8), "유도 상실")
		return
	age += delta
	if age >= maximum_lifetime:
		_expire(Color(0.72, 0.78, 0.82), "요격 실패")
		return
	var previous := global_position
	var guidance_point := countermeasure_decoy_position if countermeasure_decoy_active else INTERCEPT_GUIDANCE.lead_point(global_position, speed, target_track.estimated_position, target_track.estimated_velocity, 1.8)
	var desired := global_position.direction_to(guidance_point)
	var current := velocity.normalized()
	var angle := current.angle_to(desired)
	var direction := desired if angle <= turn_rate * delta else current.slerp(desired, (turn_rate * delta) / angle)
	velocity = direction.normalized() * speed
	global_position += velocity * delta
	look_at(global_position + velocity, Vector3.UP)
	var smoke := get_node_or_null("SmokeTrail") as GPUParticles3D
	if smoke != null:
		smoke.call("sample_world_segment", previous, global_position)
	if not countermeasure_attempted:
		var countermeasure_target := _countermeasure_target()
		if countermeasure_target != null and global_position.distance_to(countermeasure_target.get_aim_position()) <= 120.0:
			countermeasure_attempted = true
			if countermeasure_target.try_defeat_seeker(infrared_sensitivity, radar_sensitivity, rng.randf()):
				var countermeasure_type := countermeasure_target.effective_countermeasure_type(infrared_sensitivity, radar_sensitivity)
				countermeasure_decoy_position = _decoy_position(countermeasure_target)
				countermeasure_decoy_active = true
				closest_guidance_distance = INF
				_spawn_countermeasure(countermeasure_decoy_position, countermeasure_type)
				return
	for threat: ThreatUnit in registry.get_active():
		var physical_position := threat.get_aim_position()
		var nearest := Geometry3D.get_closest_point_to_segment(physical_position, previous, global_position)
		if nearest.distance_to(physical_position) <= proximity_radius:
			global_position = nearest
			_spawn_detonation(Color(0.45, 0.78, 1.0), 6.0)
			threat.receive_damage(damage)
			_release_smoke_trail()
			queue_free()
			return
	var guidance_distance := global_position.distance_to(target_track.estimated_position)
	if guidance_distance < closest_guidance_distance:
		closest_guidance_distance = guidance_distance
	elif closest_guidance_distance <= maxf(45.0, proximity_radius * 3.0) and guidance_distance >= closest_guidance_distance + maxf(8.0, speed * delta * 0.25):
		_expire(Color(0.72, 0.78, 0.82), "유도 이탈")

func _expire(color: Color, reason: String) -> void:
	var parent := get_parent()
	if parent != null:
		_spawn_detonation(color, 7.0)
		var effect := MISS_EFFECT_SCENE.instantiate() as Node3D
		parent.add_child(effect)
		effect.global_position = global_position
		effect.call("setup", color, reason)
	_release_smoke_trail()
	queue_free()

func _spawn_detonation(color: Color, radius: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var detonation := DETONATION_SCENE.instantiate() as ExplosionEffect
	parent.add_child(detonation)
	detonation.global_position = global_position
	detonation.setup(color, radius)

func _spawn_countermeasure(position: Vector3, countermeasure_type: StringName) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var burst := COUNTERMEASURE_SCENE.instantiate() as Node3D
	parent.add_child(burst)
	burst.global_position = position
	burst.call("setup", countermeasure_type)

func _release_smoke_trail() -> void:
	var smoke := get_node_or_null("SmokeTrail") as GPUParticles3D
	var parent := get_parent()
	if smoke != null:
		smoke.call("release_to", parent)

func _countermeasure_target() -> ThreatUnit:
	var selected: ThreatUnit
	var nearest_distance := 90.0
	for threat: ThreatUnit in registry.get_active():
		var distance := threat.get_aim_position().distance_to(target_track.estimated_position)
		if distance < nearest_distance:
			selected = threat
			nearest_distance = distance
	return selected

func _decoy_position(threat: ThreatUnit) -> Vector3:
	var target_position := threat.get_aim_position()
	var travel_direction := target_track.estimated_velocity.normalized()
	if travel_direction.length_squared() < 0.001:
		travel_direction = velocity.normalized()
	var distance_to_target := global_position.distance_to(target_position)
	var trail_distance := minf(35.0, distance_to_target * 0.45)
	var lateral := travel_direction.cross(Vector3.UP).normalized() * 12.0
	return target_position - travel_direction * trail_distance + lateral

func _connect_registry_signal() -> void:
	if registry != null and not registry.threat_removed.is_connected(_on_threat_removed):
		registry.threat_removed.connect(_on_threat_removed)

func _on_threat_removed(threat: ThreatUnit) -> void:
	if target_track == null or threat == null:
		return
	if target_track.classification != &"unknown" and target_track.classification != threat.definition.signature_class:
		return
	var correlation_gate := maxf(100.0, target_track.position_uncertainty * 2.0 + 30.0)
	if threat.get_aim_position().distance_to(target_track.estimated_position) > correlation_gate:
		return
	target_resolved = true
	target_resolution_reason = "표적 격추" if threat.health <= 0.0 else "표적 소실"

func capture_state() -> Dictionary:
	return {
		"type": "homing_interceptor",
		"owner_defense_id": owner_defense_id,
		"target_track_id": target_track.track_id if target_track != null else -1,
		"position": SaveDocument.vector3_to_data(global_position),
		"velocity": SaveDocument.vector3_to_data(velocity),
		"speed": speed,
		"turn_rate": turn_rate,
		"maximum_lifetime": maximum_lifetime,
		"damage": damage,
		"proximity_radius": proximity_radius,
		"age": age,
		"infrared_sensitivity": infrared_sensitivity,
		"radar_sensitivity": radar_sensitivity,
		"countermeasure_attempted": countermeasure_attempted,
		"countermeasure_decoy_active": countermeasure_decoy_active,
		"countermeasure_decoy_position": SaveDocument.vector3_to_data(countermeasure_decoy_position),
		"target_resolved": target_resolved,
		"target_resolution_reason": target_resolution_reason,
		"closest_guidance_distance": closest_guidance_distance if closest_guidance_distance < INF else -1.0,
		"rng_state": str(rng.state),
	}

func restore_state(state: Dictionary, track: PlayerTrack, registry_value: ThreatRegistry) -> void:
	target_track = track
	registry = registry_value
	owner_defense_id = int(state.owner_defense_id)
	global_position = SaveDocument.vector3_from_data(state.position)
	velocity = SaveDocument.vector3_from_data(state.velocity)
	speed = float(state.speed)
	turn_rate = float(state.turn_rate)
	maximum_lifetime = float(state.maximum_lifetime)
	damage = float(state.damage)
	proximity_radius = float(state.proximity_radius)
	age = float(state.age)
	infrared_sensitivity = float(state.get("infrared_sensitivity", 0.65))
	radar_sensitivity = float(state.get("radar_sensitivity", 0.65))
	countermeasure_attempted = bool(state.get("countermeasure_attempted", false))
	countermeasure_decoy_active = bool(state.get("countermeasure_decoy_active", false))
	countermeasure_decoy_position = SaveDocument.vector3_from_data(state.get("countermeasure_decoy_position", [0.0, 0.0, 0.0]))
	target_resolved = bool(state.get("target_resolved", false))
	target_resolution_reason = String(state.get("target_resolution_reason", "표적 소실"))
	var saved_guidance_distance := float(state.get("closest_guidance_distance", -1.0))
	closest_guidance_distance = INF if saved_guidance_distance < 0.0 else saved_guidance_distance
	rng.state = int(state.get("rng_state", rng.state))
	_connect_registry_signal()
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)
