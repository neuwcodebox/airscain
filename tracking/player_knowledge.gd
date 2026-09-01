class_name PlayerKnowledge
extends Node

signal track_created(track: PlayerTrack)
signal track_updated(track: PlayerTrack)
signal track_state_changed(track: PlayerTrack, previous_state: PlayerTrack.State)
signal track_removed(track_id: int)

@export var association_gate: float = 90.0
@export var confirmation_threshold: float = 0.6
@export var coast_after: float = 0.6
@export var lost_after: float = 2.0
@export var remove_after: float = 4.0

var simulation_time: float = 0.0
var next_track_id: int = 1
var tracks: Array[PlayerTrack] = []

func reset() -> void:
	simulation_time = 0.0
	next_track_id = 1
	tracks.clear()

func gameplay_tick(delta: float) -> void:
	simulation_time += delta
	for index: int in range(tracks.size() - 1, -1, -1):
		var track := tracks[index]
		var previous_state := track.state
		var unobserved_time := simulation_time - track.last_observed_at
		track.predict(delta, unobserved_time, coast_after, lost_after)
		if track.state != previous_state:
			track_state_changed.emit(track, previous_state)
		if unobserved_time >= remove_after:
			tracks.remove_at(index)
			track_removed.emit(track.track_id)

func submit_observation(observation: SensorObservation) -> PlayerTrack:
	var track := _associate(observation)
	if track == null:
		track = PlayerTrack.new()
		track.setup(next_track_id, observation)
		if track.detection_evidence >= confirmation_threshold:
			track.state = PlayerTrack.State.CONFIRMED
		next_track_id += 1
		tracks.append(track)
		track_created.emit(track)
	else:
		var previous_state := track.state
		track.apply_observation(observation, confirmation_threshold)
		if track.state != previous_state:
			track_state_changed.emit(track, previous_state)
	track_updated.emit(track)
	return track

func get_active_tracks() -> Array[PlayerTrack]:
	var result: Array[PlayerTrack] = []
	for track: PlayerTrack in tracks:
		if track.state != PlayerTrack.State.LOST:
			result.append(track)
	return result

func _associate(observation: SensorObservation) -> PlayerTrack:
	var selected: PlayerTrack
	var nearest_distance := association_gate
	for track: PlayerTrack in tracks:
		if track.state == PlayerTrack.State.LOST:
			continue
		if track.sensor_observed_at.has(observation.sensor_id) and is_equal_approx(track.sensor_observed_at[observation.sensor_id], observation.timestamp):
			continue
		var elapsed := maxf(0.0, observation.timestamp - track.last_observed_at)
		var predicted_position := track.estimated_position + track.estimated_velocity * elapsed
		var distance := predicted_position.distance_to(observation.measured_position)
		if distance < nearest_distance:
			nearest_distance = distance
			selected = track
	return selected
