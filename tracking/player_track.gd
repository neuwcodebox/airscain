class_name PlayerTrack
extends RefCounted

enum State { TENTATIVE, CONFIRMED, COASTING, LOST }
enum Affiliation { UNKNOWN, FRIENDLY, NEUTRAL, HOSTILE }

var track_id: int
var estimated_position: Vector3
var estimated_velocity: Vector3
var last_measured_position: Vector3
var last_observed_at: float
var track_quality: float
var position_uncertainty: float
var detection_evidence: float
var state := State.TENTATIVE
var contributing_sensor_ids: Array[int] = []
var sensor_observed_at: Dictionary[int, float] = {}
var classification_scores: Dictionary[StringName, float] = {}
var classification: StringName = &"unknown"
var classification_confidence: float = 0.0
var affiliation_scores: Dictionary[int, float] = {}
var affiliation := Affiliation.UNKNOWN
var affiliation_confidence: float = 0.0

func setup(id_value: int, observation: SensorObservation) -> void:
	track_id = id_value
	estimated_position = observation.measured_position
	last_measured_position = observation.measured_position
	last_observed_at = observation.timestamp
	track_quality = observation.quality
	position_uncertainty = observation.uncertainty
	detection_evidence = observation.quality * observation.observed_duration
	contributing_sensor_ids.append(observation.sensor_id)
	sensor_observed_at[observation.sensor_id] = observation.timestamp
	_apply_identity_evidence(observation)

func apply_observation(observation: SensorObservation, confirmation_threshold: float) -> void:
	var elapsed := observation.timestamp - last_observed_at
	var measured_velocity := estimated_velocity
	if elapsed > 0.001:
		measured_velocity = (observation.measured_position - last_measured_position) / elapsed
	var position_gain := lerpf(0.25, 0.85, observation.quality)
	var velocity_gain := lerpf(0.15, 0.65, observation.quality)
	estimated_position = estimated_position.lerp(observation.measured_position, position_gain)
	estimated_velocity = estimated_velocity.lerp(measured_velocity, velocity_gain)
	last_measured_position = observation.measured_position
	last_observed_at = observation.timestamp
	track_quality = clampf(track_quality + observation.quality * 0.35, 0.0, 1.0)
	position_uncertainty = lerpf(position_uncertainty, observation.uncertainty, position_gain)
	detection_evidence += observation.quality * observation.observed_duration
	if not contributing_sensor_ids.has(observation.sensor_id):
		contributing_sensor_ids.append(observation.sensor_id)
	sensor_observed_at[observation.sensor_id] = observation.timestamp
	_apply_identity_evidence(observation)
	state = State.CONFIRMED if detection_evidence >= confirmation_threshold else State.TENTATIVE

func predict(delta: float, unobserved_time: float, coast_after: float, lost_after: float) -> void:
	estimated_position += estimated_velocity * delta
	track_quality = maxf(0.0, track_quality - delta * 0.12)
	position_uncertainty += estimated_velocity.length() * delta * 0.08 + delta * 2.0
	if unobserved_time >= lost_after:
		state = State.LOST
	elif unobserved_time >= coast_after:
		state = State.COASTING

func _apply_identity_evidence(observation: SensorObservation) -> void:
	if not observation.classification_hint.is_empty() and observation.classification_evidence > 0.0:
		classification_scores[observation.classification_hint] = classification_scores.get(observation.classification_hint, 0.0) + observation.classification_evidence
		var best_class_score := 0.0
		var total_class_score := 0.0
		for class_id: StringName in classification_scores:
			var score: float = classification_scores[class_id]
			total_class_score += score
			if score > best_class_score:
				best_class_score = score
				classification = class_id
		classification_confidence = best_class_score / (total_class_score + 1.5)
	if observation.affiliation_evidence > 0.0:
		affiliation_scores[observation.affiliation_hint] = affiliation_scores.get(observation.affiliation_hint, 0.0) + observation.affiliation_evidence
		var best_affiliation_score := 0.0
		var total_affiliation_score := 0.0
		for affiliation_id: int in affiliation_scores:
			var score: float = affiliation_scores[affiliation_id]
			total_affiliation_score += score
			if score > best_affiliation_score:
				best_affiliation_score = score
				affiliation = affiliation_id
		affiliation_confidence = best_affiliation_score / (total_affiliation_score + 1.8)
