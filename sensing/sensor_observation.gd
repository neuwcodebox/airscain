class_name SensorObservation
extends RefCounted

var sensor_id: int
var timestamp: float
var measured_position: Vector3
var quality: float
var uncertainty: float
var observed_duration: float
var classification_hint: StringName
var classification_evidence: float
var affiliation_hint: int = ThreatDefinition.Affiliation.UNKNOWN
var affiliation_evidence: float

func setup(sensor_id_value: int, timestamp_value: float, position_value: Vector3, quality_value: float, uncertainty_value: float, duration_value: float, classification_hint_value: StringName = &"", affiliation_hint_value: int = ThreatDefinition.Affiliation.UNKNOWN, identity_evidence: float = 0.0) -> void:
	sensor_id = sensor_id_value
	timestamp = timestamp_value
	measured_position = position_value
	quality = clampf(quality_value, 0.0, 1.0)
	uncertainty = maxf(0.0, uncertainty_value)
	observed_duration = maxf(0.0, duration_value)
	classification_hint = classification_hint_value
	classification_evidence = maxf(0.0, identity_evidence)
	affiliation_hint = affiliation_hint_value
	affiliation_evidence = maxf(0.0, identity_evidence)
