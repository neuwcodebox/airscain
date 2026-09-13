class_name RadarTrackCandidate
extends RefCounted

var key: String
var measured_position: Vector3
var quality: float
var classification_hint: StringName
var affiliation_hint: int
var false_echo: bool
var priority: float

func setup(
	key_value: String,
	position_value: Vector3,
	quality_value: float,
	classification_value: StringName,
	affiliation_value: int,
	false_echo_value: bool,
	priority_value: float,
) -> void:
	key = key_value
	measured_position = position_value
	quality = quality_value
	classification_hint = classification_value
	affiliation_hint = affiliation_value
	false_echo = false_echo_value
	priority = priority_value
