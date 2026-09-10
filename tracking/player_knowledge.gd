class_name PlayerKnowledge
extends Node

signal track_created(track: PlayerTrack)
signal track_updated(track: PlayerTrack)
signal track_state_changed(track: PlayerTrack, previous_state: PlayerTrack.State)
signal track_removed(track_id: int)

const ASSOCIATION_LINEAR_LIMIT := 64
@export var association_gate: float = 90.0
@export var maximum_association_speed: float = 260.0
@export var confirmation_threshold: float = 0.6
@export var coast_after: float = 0.6
@export var lost_after: float = 2.0
@export var remove_after: float = 4.0

var simulation_time: float = 0.0
var next_track_id: int = 1
var tracks: Array[PlayerTrack] = []
# Changes to owned observations/lifecycle invalidate shared C2 membership views.
# Moving estimates remain live through the PlayerTrack references in those views.
var track_revision: int = 0
var _association_index := TrackSpatialIndex.new()
var _association_dirty: bool = true
var _indexed_count: int = -1
var _indexed_gate: float = -1.0
var _indexed_speed: float = -1.0

func reset() -> void:
	track_revision += 1
	simulation_time = 0.0
	next_track_id = 1
	tracks.clear()
	_association_index = TrackSpatialIndex.new()
	_association_dirty = true

func gameplay_tick(delta: float) -> void:
	simulation_time += delta
	for index: int in range(tracks.size() - 1, -1, -1):
		var track := tracks[index]
		var previous_state := track.state
		var unobserved_time := simulation_time - track.last_observed_at
		track.predict(delta, unobserved_time, coast_after, lost_after)
		_association_dirty = true
		if track.state != previous_state:
			track_revision += 1
			track_state_changed.emit(track, previous_state)
		if unobserved_time >= remove_after:
			tracks.remove_at(index)
			_association_dirty = true
			track_revision += 1
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
		_index_new_track(track)
		track_revision += 1
		track_created.emit(track)
	else:
		var previous_state := track.state
		track.apply_observation(observation, confirmation_threshold, maximum_association_speed)
		if not _association_dirty:
			_association_index.update(track, simulation_time, association_gate, maximum_association_speed)
		track_revision += 1
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
	var nearest_distance := INF
	var prediction_lead := maxf(0.0, observation.timestamp - simulation_time)
	for index: int in _association_candidates(observation):
		var track := tracks[index]
		if track.state == PlayerTrack.State.LOST:
			continue
		var predicted_position := track.estimated_position + track.estimated_velocity * prediction_lead
		var distance := predicted_position.distance_squared_to(observation.measured_position)
		if distance >= nearest_distance:
			continue
		if not _classifications_compatible(track.classification, observation.classification_hint):
			continue
		if track.sensor_observed_at.has(observation.sensor_id) and is_equal_approx(track.sensor_observed_at[observation.sensor_id], observation.timestamp):
			continue
		var elapsed := maxf(0.0, observation.timestamp - track.last_observed_at)
		var dynamic_gate := association_gate + maximum_association_speed * elapsed
		if distance < dynamic_gate * dynamic_gate:
			nearest_distance = distance
			selected = track
	return selected

func _association_candidates(observation: SensorObservation) -> PackedInt32Array:
	# Future observations require extra prediction and a larger gate. Retain the
	# exhaustive path for those uncommon inputs and for small/invalid gate setups.
	if tracks.size() <= ASSOCIATION_LINEAR_LIMIT or observation.timestamp > simulation_time or association_gate < 0.0 or maximum_association_speed < 0.0 or not is_finite(association_gate) or not is_finite(maximum_association_speed) or not observation.measured_position.is_finite():
		return PackedInt32Array(range(tracks.size()))
	if _association_dirty or _indexed_count != tracks.size() or _indexed_gate != association_gate or _indexed_speed != maximum_association_speed:
		_association_index.rebuild(tracks, simulation_time, association_gate, maximum_association_speed)
		_association_dirty = false
		_indexed_count = tracks.size()
		_indexed_gate = association_gate
		_indexed_speed = maximum_association_speed
	return _association_index.candidates(observation.measured_position)

func _index_new_track(track: PlayerTrack) -> void:
	if not _association_dirty:
		_association_index.insert(track, tracks.size() - 1, simulation_time, association_gate, maximum_association_speed)
		_indexed_count = tracks.size()

func _classifications_compatible(track_class: StringName, observation_class: StringName) -> bool:
	if track_class == &"unknown" or observation_class.is_empty() or track_class == &"air_contact" or observation_class == &"air_contact":
		return true
	return track_class == observation_class

func capture_state() -> Dictionary:
	var track_states: Array[Dictionary] = []
	for track: PlayerTrack in tracks:
		track_states.append(track.capture_state())
	return {
		"simulation_time": simulation_time,
		"next_track_id": next_track_id,
		"tracks": track_states,
	}

func restore_state(data: Dictionary) -> void:
	reset()
	simulation_time = float(data.get("simulation_time", 0.0))
	next_track_id = int(data.get("next_track_id", 1))
	for track_data: Dictionary in data.get("tracks", []):
		var track := PlayerTrack.new()
		track.restore_state(track_data)
		tracks.append(track)
		_index_new_track(track)
		track_revision += 1
		track_created.emit(track)
		track_updated.emit(track)

func find_track(track_id: int) -> PlayerTrack:
	for track: PlayerTrack in tracks:
		if track.track_id == track_id:
			return track
	return null
