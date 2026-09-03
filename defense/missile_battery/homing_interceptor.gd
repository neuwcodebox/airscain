class_name HomingInterceptor
extends Node3D

signal target_changed(previous_track_id: int, new_track_id: int, remaining_lifetime: float)

const MISS_EFFECT_SCENE := preload("res://effects/interceptor_miss/interceptor_miss.tscn")
const DETONATION_SCENE := preload("res://effects/explosion/explosion.tscn")
const COUNTERMEASURE_SCENE := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
const INTERCEPT_GUIDANCE := preload("res://defense/intercept_guidance.gd")
const BOOST_GUIDANCE_RAMP_DURATION := 0.55
const REACQUISITION_GRACE_DURATION := 2.5

var target_track: PlayerTrack
var registry: ThreatRegistry
var battlefield: Battlefield
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
var reacquisition_remaining: float = -1.0
var reacquisition_reason: String = "표적 소실"
var target_destroyed_coast: bool = false
var closest_guidance_distance: float = INF
var boost_guidance_ramp_active: bool = false
var alternative_tracks: Array[PlayerTrack] = []
var preferred_classes: Array[StringName] = []
var minimum_preferred_speed: float = 0.0
var other_target_match: float = 1.0
var small_target_match: float = 0.22
var rng := RandomNumberGenerator.new()

func configure(track_value: PlayerTrack, registry_value: ThreatRegistry, definition: MissileMunitionDefinition, initial_direction: Vector3, owner_id: int = 0, launch_sequence: int = 0, track_candidates: Array[PlayerTrack] = [], battlefield_value: Battlefield = null) -> void:
	target_track = track_value
	registry = registry_value
	battlefield = battlefield_value
	owner_defense_id = owner_id
	speed = definition.interceptor_speed
	turn_rate = deg_to_rad(definition.interceptor_turn_rate_degrees)
	maximum_lifetime = definition.interceptor_lifetime
	damage = definition.interceptor_damage
	proximity_radius = definition.proximity_radius
	infrared_sensitivity = definition.infrared_sensitivity
	radar_sensitivity = definition.radar_sensitivity
	preferred_classes = definition.preferred_classes.duplicate()
	minimum_preferred_speed = definition.minimum_preferred_speed
	other_target_match = definition.other_target_match
	small_target_match = definition.small_target_match
	alternative_tracks = track_candidates.duplicate()
	velocity = initial_direction.normalized() * speed
	boost_guidance_ramp_active = initial_direction.angle_to(global_position.direction_to(track_value.estimated_position)) > deg_to_rad(5.0)
	rng.seed = owner_defense_id ^ track_value.track_id ^ launch_sequence * 0x45D9F3B ^ 0x5E3C9A
	_connect_registry_signal()

func gameplay_tick(delta: float) -> void:
	age += delta
	if age >= maximum_lifetime:
		if target_destroyed_coast:
			_retire_without_detonation()
		else:
			_expire(Color(0.72, 0.78, 0.82), "요격 실패")
		return
	if target_destroyed_coast:
		if not _try_retarget():
			_coast_without_target(delta)
			return
	if reacquisition_remaining >= 0.0 or target_track == null or target_track.state == PlayerTrack.State.LOST:
		if _try_retarget():
			pass
		else:
			_begin_reacquisition("유도 상실" if target_track == null or target_track.state == PlayerTrack.State.LOST else reacquisition_reason)
			reacquisition_remaining -= delta
			if reacquisition_remaining <= 0.0:
				_expire(Color(0.62, 0.72, 0.8), reacquisition_reason)
				return
			_coast_without_target(delta)
			return
	var previous := global_position
	var guidance_point := countermeasure_decoy_position if countermeasure_decoy_active else INTERCEPT_GUIDANCE.lead_point(global_position, speed, target_track.estimated_position, target_track.estimated_velocity, 1.8)
	var desired := global_position.direction_to(guidance_point)
	var current := velocity.normalized()
	var angle := current.angle_to(desired)
	var guidance_ratio := smoothstep(0.0, 1.0, age / BOOST_GUIDANCE_RAMP_DURATION) if boost_guidance_ramp_active else 1.0
	var effective_turn_rate := turn_rate * lerpf(0.28, 1.0, guidance_ratio)
	var direction := desired if angle <= effective_turn_rate * delta else current.slerp(desired, (effective_turn_rate * delta) / angle)
	velocity = direction.normalized() * speed
	global_position += velocity * delta
	if _resolve_terrain_impact(previous):
		return
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
	if _resolve_proximity_intercept(previous):
		return
	var guidance_distance := global_position.distance_to(target_track.estimated_position)
	if guidance_distance < closest_guidance_distance:
		closest_guidance_distance = guidance_distance
	elif closest_guidance_distance <= maxf(45.0, proximity_radius * 3.0) and guidance_distance >= closest_guidance_distance + maxf(8.0, speed * delta * 0.25):
		_expire(Color(0.72, 0.78, 0.82), "유도 이탈")

func _coast_without_target(delta: float) -> void:
	var previous := global_position
	global_position += velocity * delta
	if _resolve_terrain_impact(previous):
		return
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)
	var smoke := get_node_or_null("SmokeTrail") as GPUParticles3D
	if smoke != null:
		smoke.call("sample_world_segment", previous, global_position)
	_resolve_proximity_intercept(previous)

func _resolve_terrain_impact(previous: Vector3) -> bool:
	if battlefield == null:
		return false
	var impact := battlefield.terrain_segment_impact(previous, global_position)
	if impact.is_empty():
		return false
	global_position = impact.position
	var smoke := get_node_or_null("SmokeTrail") as GPUParticles3D
	if smoke != null:
		smoke.call("sample_world_segment", previous, global_position)
	_expire(Color(0.62, 0.68, 0.7), "지형 충돌")
	return true

func _resolve_proximity_intercept(previous: Vector3) -> bool:
	if registry == null:
		return false
	for threat: ThreatUnit in registry.get_active():
		var physical_position := threat.get_aim_position()
		var nearest := Geometry3D.get_closest_point_to_segment(physical_position, previous, global_position)
		if nearest.distance_to(physical_position) <= proximity_radius:
			global_position = nearest
			_spawn_detonation(Color(0.45, 0.78, 1.0), 6.0)
			threat.receive_damage(damage)
			_release_smoke_trail()
			queue_free()
			return true
	return false

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

func _retire_without_detonation() -> void:
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
	if not _removed_threat_matches_target(threat):
		return
	if _try_retarget():
		return
	if threat.health <= 0.0:
		target_destroyed_coast = true
		reacquisition_remaining = -1.0
		reacquisition_reason = "표적 파괴 확인"
		return
	_begin_reacquisition("표적 소실")

func _removed_threat_matches_target(threat: ThreatUnit) -> bool:
	var removed_position := threat.get_aim_position()
	var matched_track: PlayerTrack
	var matched_distance := INF
	var candidates: Array[PlayerTrack] = [target_track]
	for candidate: PlayerTrack in alternative_tracks:
		if candidate != null and not candidates.has(candidate):
			candidates.append(candidate)
	for candidate: PlayerTrack in candidates:
		if candidate == null or candidate.state == PlayerTrack.State.LOST:
			continue
		if candidate.classification != &"unknown" and candidate.classification != threat.definition.signature_class:
			continue
		var distance := removed_position.distance_to(candidate.estimated_position)
		if distance < matched_distance:
			matched_track = candidate
			matched_distance = distance
	if matched_track != target_track:
		return false
	var correlation_gate := maxf(proximity_radius * 2.0, target_track.position_uncertainty * 2.0 + proximity_radius)
	return matched_distance <= correlation_gate

func _begin_reacquisition(reason: String) -> void:
	if reacquisition_remaining >= 0.0:
		return
	reacquisition_remaining = REACQUISITION_GRACE_DURATION
	reacquisition_reason = reason

func _try_retarget() -> bool:
	var remaining_lifetime := maximum_lifetime - age
	if remaining_lifetime <= 0.1:
		return false
	var current_direction := velocity.normalized()
	var selected: PlayerTrack
	var selected_score := INF
	for candidate: PlayerTrack in alternative_tracks:
		if candidate == null or candidate == target_track or candidate.state == PlayerTrack.State.TENTATIVE or candidate.state == PlayerTrack.State.LOST:
			continue
		if candidate.affiliation != PlayerTrack.Affiliation.HOSTILE or candidate.affiliation_confidence < 0.3:
			continue
		var match := _target_match(candidate)
		if match <= 0.0:
			continue
		var guidance_point := INTERCEPT_GUIDANCE.lead_point(global_position, speed, candidate.estimated_position, candidate.estimated_velocity, 1.8)
		var candidate_direction := global_position.direction_to(guidance_point)
		var angle := current_direction.angle_to(candidate_direction)
		var turn_time := angle / maxf(turn_rate, 0.001)
		var distance := global_position.distance_to(guidance_point)
		if distance > 600.0 or distance / maxf(speed, 0.001) + turn_time > remaining_lifetime * 0.9:
			continue
		var score := distance / maxf(match, 0.1) + angle * 90.0
		if score < selected_score:
			selected = candidate
			selected_score = score
	if selected == null:
		return false
	var previous_track_id := target_track.track_id if target_track != null else -1
	target_track = selected
	target_destroyed_coast = false
	reacquisition_remaining = -1.0
	reacquisition_reason = "표적 소실"
	countermeasure_attempted = false
	countermeasure_decoy_active = false
	closest_guidance_distance = INF
	target_changed.emit(previous_track_id, selected.track_id, remaining_lifetime)
	return true

func _target_match(track: PlayerTrack) -> float:
	var result := small_target_match if track.classification == &"small_uav" else 1.0
	var constrained := not preferred_classes.is_empty() or minimum_preferred_speed > 0.0
	var preferred := preferred_classes.has(track.classification) or minimum_preferred_speed > 0.0 and track.estimated_velocity.length() >= minimum_preferred_speed
	return result if not constrained or preferred else result * other_target_match

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
		"reacquisition_remaining": reacquisition_remaining,
		"reacquisition_reason": reacquisition_reason,
		"target_destroyed_coast": target_destroyed_coast,
		"closest_guidance_distance": closest_guidance_distance if closest_guidance_distance < INF else -1.0,
		"boost_guidance_ramp_active": boost_guidance_ramp_active,
		"preferred_classes": preferred_classes.map(func(classification: StringName) -> String: return String(classification)),
		"minimum_preferred_speed": minimum_preferred_speed,
		"other_target_match": other_target_match,
		"small_target_match": small_target_match,
		"rng_state": str(rng.state),
	}

func restore_state(state: Dictionary, track: PlayerTrack, registry_value: ThreatRegistry, track_candidates: Array[PlayerTrack] = [], battlefield_value: Battlefield = null) -> void:
	target_track = track
	registry = registry_value
	battlefield = battlefield_value
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
	preferred_classes.clear()
	for classification: Variant in state.get("preferred_classes", []):
		preferred_classes.append(StringName(String(classification)))
	minimum_preferred_speed = float(state.get("minimum_preferred_speed", 0.0))
	other_target_match = float(state.get("other_target_match", 1.0))
	small_target_match = float(state.get("small_target_match", 0.22))
	alternative_tracks = track_candidates.duplicate()
	countermeasure_attempted = bool(state.get("countermeasure_attempted", false))
	countermeasure_decoy_active = bool(state.get("countermeasure_decoy_active", false))
	countermeasure_decoy_position = SaveDocument.vector3_from_data(state.get("countermeasure_decoy_position", [0.0, 0.0, 0.0]))
	reacquisition_remaining = float(state.get("reacquisition_remaining", 0.0 if bool(state.get("target_resolved", false)) else -1.0))
	reacquisition_reason = String(state.get("reacquisition_reason", state.get("target_resolution_reason", "표적 소실")))
	target_destroyed_coast = bool(state.get("target_destroyed_coast", false))
	var saved_guidance_distance := float(state.get("closest_guidance_distance", -1.0))
	closest_guidance_distance = INF if saved_guidance_distance < 0.0 else saved_guidance_distance
	boost_guidance_ramp_active = bool(state.get("boost_guidance_ramp_active", false))
	rng.state = int(state.get("rng_state", rng.state))
	_connect_registry_signal()
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)
