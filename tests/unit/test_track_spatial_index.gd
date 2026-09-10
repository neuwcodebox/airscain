extends GutTest

func test_spatial_candidates_include_every_track_inside_its_dynamic_gate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52107
	var tracks: Array[PlayerTrack] = []
	var timestamp := 5.0
	for index: int in 300:
		var track := PlayerTrack.new()
		track.track_id = 500 - index
		track.estimated_position = Vector3(rng.randf_range(-1800, 1800), rng.randf_range(0, 1200), rng.randf_range(-1800, 1800))
		track.last_observed_at = timestamp - rng.randf_range(0.0, 2.0)
		track.state = PlayerTrack.State.LOST if index % 13 == 0 else PlayerTrack.State.CONFIRMED
		tracks.append(track)
	var spatial := TrackSpatialIndex.new()
	spatial.rebuild(tracks, timestamp, 90.0, 260.0)
	var pruned := 0
	for query: int in 300:
		var position := tracks[query].estimated_position + Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-80, 80))
		var candidates := spatial.candidates(position)
		var ordered := candidates.duplicate()
		ordered.sort()
		assert_eq(candidates, ordered, "tie order follows source order, not track IDs or cell traversal")
		if candidates.size() < tracks.size():
			pruned += 1
		for index: int in tracks.size():
			var track := tracks[index]
			if track.state == PlayerTrack.State.LOST:
				assert_false(candidates.has(index))
			else:
				var gate := 90.0 + 260.0 * (timestamp - track.last_observed_at)
				if position.distance_squared_to(track.estimated_position) < gate * gate:
					assert_true(candidates.has(index), "query %d cannot omit admissible track %d" % [query, index])
	assert_gt(pruned, 0)

func test_index_updates_motion_gate_scale_lifecycle_and_appended_tracks() -> void:
	var track := PlayerTrack.new()
	track.estimated_position = Vector3(-128.01, 100, 128.01)
	track.last_observed_at = 0.0
	track.state = PlayerTrack.State.CONFIRMED
	var spatial := TrackSpatialIndex.new()
	spatial.rebuild([track], 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(Vector3(400, 100, 128)), PackedInt32Array([0]))
	track.estimated_position = Vector3(1400, 100, -1300)
	track.last_observed_at = 2.0
	spatial.update(track, 2.0, 90.0, 260.0)
	assert_true(spatial.candidates(Vector3(400, 100, 128)).is_empty())
	assert_eq(spatial.candidates(track.estimated_position), PackedInt32Array([0]))
	track.state = PlayerTrack.State.LOST
	spatial.update(track, 2.0, 90.0, 260.0)
	assert_true(spatial.candidates(track.estimated_position).is_empty())
	track.state = PlayerTrack.State.CONFIRMED
	spatial.update(track, 2.0, 90.0, 260.0)
	var added := PlayerTrack.new()
	added.estimated_position = track.estimated_position
	spatial.insert(added, 1, 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(track.estimated_position), PackedInt32Array([0, 1]))
	spatial.rebuild([added], 2.0, 90.0, 260.0)
	assert_eq(spatial.candidates(added.estimated_position), PackedInt32Array([0]))
	spatial.rebuild([], 2.0, 90.0, 260.0)
	assert_true(spatial.candidates(added.estimated_position).is_empty())
