extends GutTest

const PROPERTY_SEED := 52107
const TRACK_COUNT := 300
const QUERY_COUNT := 300

func test_spatial_candidates_include_every_track_inside_its_dynamic_gate() -> void:
	assert_eq(_candidate_property_failure(), "", "공간 후보 property seed %d" % PROPERTY_SEED)

func _candidate_property_failure() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROPERTY_SEED
	var tracks: Array[PlayerTrack] = []
	var timestamp := 5.0
	var active_count := 0
	for index: int in TRACK_COUNT:
		var track := _track(Vector3(rng.randf_range(-1800, 1800), rng.randf_range(0, 1200), rng.randf_range(-1800, 1800)), timestamp - rng.randf_range(0.0, 2.0))
		track.track_id = 500 - index
		track.state = PlayerTrack.State.LOST if index % 13 == 0 else PlayerTrack.State.CONFIRMED
		if track.state != PlayerTrack.State.LOST:
			active_count += 1
		tracks.append(track)
	var spatial := TrackSpatialIndex.new()
	spatial.rebuild(tracks, timestamp, 90.0, 260.0)
	var pruned := 0
	for query: int in QUERY_COUNT:
		var position := tracks[query].estimated_position + Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-80, 80))
		var candidates := spatial.candidates(position)
		var ordered := candidates.duplicate()
		ordered.sort()
		if candidates != ordered:
			return "seed %d query %d: 후보 순서가 원본 항적 순서와 다릅니다" % [PROPERTY_SEED, query]
		if candidates.size() < active_count:
			pruned += 1
		for index: int in tracks.size():
			var track := tracks[index]
			if track.state == PlayerTrack.State.LOST and candidates.has(index):
				return "seed %d query %d: lost 항적 %d이 후보에 포함됐습니다" % [PROPERTY_SEED, query, index]
			elif track.state != PlayerTrack.State.LOST:
				var gate := 90.0 + 260.0 * (timestamp - track.last_observed_at)
				if position.distance_squared_to(track.estimated_position) < gate * gate and not candidates.has(index):
					return "seed %d query %d: 허용 gate 안 항적 %d이 누락됐습니다" % [PROPERTY_SEED, query, index]
	if pruned <= 0:
		return "seed %d 표본이 실제 공간 pruning을 수행하지 않았습니다" % PROPERTY_SEED
	return ""

func test_index_updates_a_moving_tracks_gate_and_cell() -> void:
	var track := _track(Vector3(-128.01, 100, 128.01), 0.0)
	var spatial := TrackSpatialIndex.new()
	spatial.rebuild([track], 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(Vector3(400, 100, 128)), PackedInt32Array([0]))
	track.estimated_position = Vector3(1400, 100, -1300)
	track.last_observed_at = 2.0
	spatial.update(track, 2.0, 90.0, 260.0)
	assert_true(spatial.candidates(Vector3(400, 100, 128)).is_empty())
	assert_eq(spatial.candidates(track.estimated_position), PackedInt32Array([0]))

func test_index_excludes_lost_track_and_restores_reactivated_track() -> void:
	var track := _track(Vector3(1400, 100, -1300), 2.0)
	var spatial := TrackSpatialIndex.new()
	spatial.rebuild([track], 2.0, 90.0, 260.0)
	track.state = PlayerTrack.State.LOST
	spatial.update(track, 2.0, 90.0, 260.0)
	assert_true(spatial.candidates(track.estimated_position).is_empty())
	track.state = PlayerTrack.State.CONFIRMED
	spatial.update(track, 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(track.estimated_position), PackedInt32Array([0]))

func test_insert_and_rebuild_replace_candidate_membership() -> void:
	var track := _track(Vector3(1400, 100, -1300), 2.0)
	var added := _track(track.estimated_position, 2.0)
	var spatial := TrackSpatialIndex.new()
	spatial.rebuild([track], 2.0, 90.0, 260.0)
	spatial.insert(added, 1, 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(track.estimated_position), PackedInt32Array([0, 1]))
	spatial.rebuild([added], 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(added.estimated_position), PackedInt32Array([0]))
	spatial.rebuild([], 2.0, 90.0, 260.0)
	assert_true(spatial.candidates(added.estimated_position).is_empty())

func _track(position: Vector3, last_observed_at: float) -> PlayerTrack:
	var track := PlayerTrack.new()
	track.estimated_position = position
	track.last_observed_at = last_observed_at
	track.state = PlayerTrack.State.CONFIRMED
	return track
