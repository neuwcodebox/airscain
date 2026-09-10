class_name TrackSpatialIndex
extends RefCounted
## Player estimates only. Each track occupies one cell at a scale that bounds
## its association gate; a point query visits nine neighbors per occupied scale.

const BASE_CELL_SIZE := 128.0
var _cells: Dictionary[Vector3i, Array] = {}
var _track_cells: Array[Vector3i] = []
var _track_active := PackedByteArray()
var _indices: Dictionary[PlayerTrack, int] = {}
var _level_sizes: Array[float] = []
var _level_counts: Array[int] = []

func rebuild(tracks: Array[PlayerTrack], timestamp: float, gate: float, speed: float) -> void:
	_cells.clear()
	_indices.clear()
	_track_cells.clear()
	_track_active.clear()
	_level_sizes.clear()
	_level_counts.clear()
	for index: int in tracks.size():
		insert(tracks[index], index, timestamp, gate, speed)

func insert(track: PlayerTrack, index: int, timestamp: float, gate: float, speed: float) -> void:
	# Appended source indices only; removal/reordering is handled by rebuild().
	_indices[track] = index
	_track_cells.resize(index + 1)
	_track_active.resize(index + 1)
	update(track, timestamp, gate, speed)

func update(track: PlayerTrack, timestamp: float, gate: float, speed: float) -> void:
	var index := _indices[track]
	var level := 0
	var cell_size := BASE_CELL_SIZE
	var radius := gate + speed * maxf(0.0, timestamp - track.last_observed_at) + 0.001
	while radius > cell_size:
		level += 1
		cell_size *= 2.0
	while _level_sizes.size() <= level:
		_level_sizes.append(BASE_CELL_SIZE * pow(2.0, _level_sizes.size()))
		_level_counts.append(0)
	var position := track.estimated_position
	var cell := Vector3i(floori(position.x / cell_size), floori(position.z / cell_size), level)
	var active := track.state != PlayerTrack.State.LOST
	if _track_active[index] != 0:
		var previous := _track_cells[index]
		if active and previous == cell:
			return
		_cells[previous].erase(index)
		if _cells[previous].is_empty():
			_cells.erase(previous)
		_level_counts[previous.z] -= 1
	_track_active[index] = 1 if active else 0
	_track_cells[index] = cell
	if active:
		if not _cells.has(cell):
			_cells[cell] = []
		_cells[cell].append(index)
		_level_counts[level] += 1

func candidates(position: Vector3) -> PackedInt32Array:
	var result := PackedInt32Array()
	for level: int in _level_sizes.size():
		if _level_counts[level] == 0:
			continue
		var size := _level_sizes[level]
		var x := floori(position.x / size)
		var z := floori(position.z / size)
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var cell := Vector3i(x + dx, z + dz, level)
				if _cells.has(cell):
					result.append_array(_cells[cell])
	# Ties follow source array order, even after a restored non-monotonic ID list.
	result.sort()
	return result
