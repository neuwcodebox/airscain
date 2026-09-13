class_name PlayerKnowledge
extends Node

signal track_created(track: PlayerTrack)
signal track_updated(track: PlayerTrack)
signal track_state_changed(track: PlayerTrack, previous_state: PlayerTrack.State)
signal track_removed(track_id: int)

const ASSOCIATION_LINEAR_LIMIT := 64
@export var association_gate: float = 90.0
@export var simultaneous_fusion_gate: float = 6.0
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
		if track.prune_sensor_contributions(simulation_time, lost_after):
			track_revision += 1
			track_updated.emit(track)
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
	return _apply_observation(observation, _associate(observation))

func submit_scan(observations: Array[SensorObservation]) -> Array[PlayerTrack]:
	var associated_tracks := _associate_scan(observations)
	var submitted_tracks: Array[PlayerTrack] = []
	for observation_index: int in observations.size():
		submitted_tracks.append(_apply_observation(observations[observation_index], associated_tracks[observation_index]))
	return submitted_tracks

func _apply_observation(observation: SensorObservation, track: PlayerTrack) -> PlayerTrack:
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

func note_capacity_gap(track_id: int, sensor_id: int, timestamp: float) -> void:
	var track := find_track(track_id)
	if track == null or not track.sensor_observed_at.has(sensor_id):
		return
	if track.mark_capacity_limited(timestamp):
		track_revision += 1
		track_updated.emit(track)

func get_active_tracks() -> Array[PlayerTrack]:
	var result: Array[PlayerTrack] = []
	for track: PlayerTrack in tracks:
		if track.state != PlayerTrack.State.LOST:
			result.append(track)
	return result

func _associate(observation: SensorObservation) -> PlayerTrack:
	var selected: PlayerTrack
	var lowest_cost := GlobalNearestNeighbor.BLOCKED_COST
	for index: int in _association_candidates(observation):
		var track := tracks[index]
		var cost := _association_cost(track, observation)
		if cost >= lowest_cost:
			continue
		lowest_cost = cost
		selected = track
	return selected

func _associate_scan(observations: Array[SensorObservation]) -> Array[PlayerTrack]:
	var associated_tracks: Array[PlayerTrack] = []
	associated_tracks.resize(observations.size())
	if observations.is_empty():
		return associated_tracks

	# Candidate pruning stays spatial; only tracks sharing a validation gate with
	# this small, capacity-limited scan enter the global assignment.
	var candidate_track_indices: Array[int] = []
	var candidate_columns: Dictionary[int, int] = {}
	for observation: SensorObservation in observations:
		for track_index: int in _association_candidates(observation):
			if _association_cost(tracks[track_index], observation) >= GlobalNearestNeighbor.BLOCKED_COST:
				continue
			if not candidate_columns.has(track_index):
				candidate_columns[track_index] = candidate_track_indices.size()
				candidate_track_indices.append(track_index)

	var track_column_count := candidate_track_indices.size()
	var costs: Array[PackedFloat64Array] = []
	for observation: SensorObservation in observations:
		var row := PackedFloat64Array()
		row.resize(track_column_count + observations.size())
		row.fill(GlobalNearestNeighbor.BLOCKED_COST)
		for column_index: int in track_column_count:
			row[column_index] = _association_cost(tracks[candidate_track_indices[column_index]], observation)
		# Any dummy column means this plot starts a new track. A valid gated
		# association is always cheaper, while one-to-one assignment is preserved.
		for column_index: int in range(track_column_count, row.size()):
			row[column_index] = 1.0
		costs.append(row)

	var assigned_columns := GlobalNearestNeighbor.solve(costs)
	for observation_index: int in observations.size():
		var column_index := assigned_columns[observation_index]
		if column_index >= 0 and column_index < track_column_count:
			associated_tracks[observation_index] = tracks[candidate_track_indices[column_index]]
	return associated_tracks

func _association_cost(track: PlayerTrack, observation: SensorObservation) -> float:
	if track.state == PlayerTrack.State.LOST:
		return GlobalNearestNeighbor.BLOCKED_COST
	if not _classifications_compatible(track.classification, observation.classification_hint):
		return GlobalNearestNeighbor.BLOCKED_COST
	if track.sensor_observed_at.has(observation.sensor_id) and is_equal_approx(track.sensor_observed_at[observation.sensor_id], observation.timestamp):
		return GlobalNearestNeighbor.BLOCKED_COST
	var elapsed := maxf(0.0, observation.timestamp - track.last_observed_at)
	var prediction_lead := maxf(0.0, observation.timestamp - simulation_time)
	var reference_position := track.estimated_position + track.estimated_velocity * prediction_lead
	var dynamic_gate := association_gate + maximum_association_speed * elapsed
	# A sensor's earlier contribution does not make a different plot from the
	# current timestamp a plausible continuation. Same-time fusion always uses
	# the previous raw plot rather than the deliberately lagging filtered state;
	# duplicate reports from this sensor were already rejected above.
	if is_zero_approx(elapsed):
		reference_position = track.last_measured_position
		dynamic_gate = minf(dynamic_gate, simultaneous_fusion_gate)
	if dynamic_gate <= 0.0 or not is_finite(dynamic_gate):
		return GlobalNearestNeighbor.BLOCKED_COST
	var distance_squared := reference_position.distance_squared_to(observation.measured_position)
	var gate_squared := dynamic_gate * dynamic_gate
	if not is_finite(distance_squared) or distance_squared >= gate_squared:
		return GlobalNearestNeighbor.BLOCKED_COST
	return distance_squared / gate_squared

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
