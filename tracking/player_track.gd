class_name PlayerTrack
extends RefCounted

enum State { TENTATIVE, CONFIRMED, COASTING, LOST }

var track_id: int
var estimated_position: Vector3
var estimated_velocity: Vector3
var last_observed_at: float
var track_quality: float
var position_uncertainty: float
var detection_evidence: float
var state := State.TENTATIVE
var contributing_sensor_ids: Array[int] = []

func setup(id_value: int, observation: SensorObservation) -> void:
	track_id = id_value
	estimated_position = observation.measured_position
	last_observed_at = observation.timestamp
	track_quality = observation.quality
	position_uncertainty = observation.uncertainty
	detection_evidence = observation.quality * observation.observed_duration
	contributing_sensor_ids.append(observation.sensor_id)

func apply_observation(observation: SensorObservation, confirmation_threshold: float) -> void:
	var elapsed := maxf(0.001, observation.timestamp - last_observed_at)
	var predicted_position := estimated_position + estimated_velocity * elapsed
	var measured_velocity := (observation.measured_position - estimated_position) / elapsed
	var position_gain := lerpf(0.25, 0.85, observation.quality)
	var velocity_gain := lerpf(0.15, 0.65, observation.quality)
	estimated_position = predicted_position.lerp(observation.measured_position, position_gain)
	estimated_velocity = estimated_velocity.lerp(measured_velocity, velocity_gain)
	last_observed_at = observation.timestamp
	track_quality = clampf(track_quality + observation.quality * 0.35, 0.0, 1.0)
	position_uncertainty = lerpf(position_uncertainty, observation.uncertainty, position_gain)
	detection_evidence += observation.quality * observation.observed_duration
	if not contributing_sensor_ids.has(observation.sensor_id):
		contributing_sensor_ids.append(observation.sensor_id)
	state = State.CONFIRMED if detection_evidence >= confirmation_threshold else State.TENTATIVE

func predict(delta: float, unobserved_time: float, coast_after: float, lost_after: float) -> void:
	estimated_position += estimated_velocity * delta
	track_quality = maxf(0.0, track_quality - delta * 0.12)
	position_uncertainty += estimated_velocity.length() * delta * 0.08 + delta * 2.0
	if unobserved_time >= lost_after:
		state = State.LOST
	elif unobserved_time >= coast_after:
		state = State.COASTING
