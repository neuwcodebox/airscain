extends GutTest

class ExhaustiveKnowledge:
	extends PlayerKnowledge
	func _association_candidates(_observation: SensorObservation) -> PackedInt32Array:
		return PackedInt32Array(range(tracks.size()))

class IndexedKnowledge:
	extends PlayerKnowledge
	var narrowed_queries: int = 0
	func _association_candidates(observation: SensorObservation) -> PackedInt32Array:
		var result := super._association_candidates(observation)
		if result.size() < tracks.size():
			narrowed_queries += 1
		return result

func test_spatial_association_matches_exhaustive_observation_streams() -> void:
	for seed_value: int in [71, 73129]:
		var actual := autofree(IndexedKnowledge.new()) as IndexedKnowledge
		var expected := autofree(ExhaustiveKnowledge.new()) as ExhaustiveKnowledge
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var classes: Array[StringName] = [&"air_contact", &"uav", &"rocket"]
		for frame: int in 18:
			actual.gameplay_tick(0.1)
			expected.gameplay_tick(0.1)
			for sensor: int in range(1, 4):
				for index: int in 96:
					var position := Vector3((index % 16) * 180 - 1350, 100 + (index % 5) * 120, (index / 16) * 220 - 550)
					position += Vector3(index % 5 * 10, 0, 20) * actual.simulation_time
					position += Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
					var timestamp := actual.simulation_time
					if frame % 7 == 0:
						timestamp += 0.3
					elif frame % 5 == 0:
						timestamp -= 0.15
					var observation := SensorObservation.new()
					observation.setup(sensor, timestamp, position, 0.85, 8.0, 0.1, classes[index % classes.size()], ThreatDefinition.Affiliation.HOSTILE, 0.3)
					var result := actual.submit_observation(observation)
					var reference := expected.submit_observation(observation)
					assert_eq(result.track_id, reference.track_id, "seed %d frame %d sensor %d observation %d" % [seed_value, frame, sensor, index])
					if result.track_id != reference.track_id:
						return
			assert_eq(JSON.stringify(actual.capture_state()).sha256_text(), JSON.stringify(expected.capture_state()).sha256_text(), "all tracked estimates and sensor evidence stay identical")
			if frame == 9:
				var saved := actual.capture_state()
				(saved.tracks as Array).reverse()
				actual.restore_state(saved)
				expected.restore_state(saved)
			elif frame == 12:
				actual.gameplay_tick(5.0)
				expected.gameplay_tick(5.0)
			elif frame == 15:
				actual.reset()
				expected.reset()
		assert_gt(actual.narrowed_queries, 0, "the stream must exercise spatial pruning")

func test_spatial_association_preserves_ties_and_current_sensor_exclusions() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	for index: int in 80:
		var track := PlayerTrack.new()
		track.track_id = 100 - index
		track.estimated_position = Vector3(-5 if index == 0 else 5, 100, 0) if index < 2 else Vector3(index * 100, 100, 2000)
		track.state = PlayerTrack.State.CONFIRMED
		knowledge.tracks.append(track)
	var observation := SensorObservation.new()
	observation.setup(99, 0.0, Vector3(0, 100, 0), 0.9, 5.0, 0.1, &"uav")
	assert_same(knowledge._associate(observation), knowledge.tracks[0], "ties retain array order, not lowest track ID")
	knowledge.tracks[0].sensor_observed_at[99] = 0.0
	assert_same(knowledge._associate(observation), knowledge.tracks[1], "current same-scan exclusion still applies")
	knowledge.tracks[1].classification = &"rocket"
	assert_null(knowledge._associate(observation))

func test_association_index_is_current_inside_observation_callbacks() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var inspect := func(track: PlayerTrack) -> void:
		var probe := SensorObservation.new()
		probe.setup(9999, knowledge.simulation_time, track.estimated_position, 0.9, 5.0, 0.1)
		assert_same(knowledge._associate(probe), track, "observation callbacks see new cell membership immediately")
	knowledge.track_created.connect(inspect)
	knowledge.track_updated.connect(inspect)
	for index: int in 80:
		var observation := SensorObservation.new()
		observation.setup(1, 0.0, Vector3(index * 220 - 8800, 100, 0), 0.9, 5.0, 0.1)
		knowledge.submit_observation(observation)
	knowledge.gameplay_tick(0.2)
	for track: PlayerTrack in knowledge.tracks.duplicate():
		var observation := SensorObservation.new()
		observation.setup(1, knowledge.simulation_time, track.estimated_position + Vector3(120, 0, 0), 0.9, 5.0, 0.1)
		knowledge.submit_observation(observation)

func test_association_pruning_matches_nearest_compatible_unsampled_track() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var rng := RandomNumberGenerator.new()
	rng.seed = 91271
	var classes: Array[StringName] = [&"unknown", &"air_contact", &"uav", &"rocket"]
	for index: int in 200:
		var track := PlayerTrack.new()
		track.track_id = index + 1
		track.estimated_position = Vector3(rng.randf_range(-800, 800), rng.randf_range(0, 1000), rng.randf_range(-800, 800))
		track.estimated_velocity = Vector3(rng.randf_range(-200, 200), 0, 0)
		track.classification = classes[index % classes.size()]
		track.last_observed_at = rng.randf_range(0, 1)
		track.state = PlayerTrack.State.LOST if index % 7 == 0 else PlayerTrack.State.CONFIRMED
		if index % 5 == 0:
			track.sensor_observed_at[3] = 1.0
		knowledge.tracks.append(track)
	for index: int in 400:
		var observation := SensorObservation.new()
		observation.setup(3, 1.0, Vector3(rng.randf_range(-800, 800), rng.randf_range(0, 1000), rng.randf_range(-800, 800)), 0.9, 8, 0.1, classes[index % classes.size()])
		var expected: PlayerTrack
		var nearest := INF
		for track: PlayerTrack in knowledge.tracks:
			if track.state == PlayerTrack.State.LOST or not knowledge._classifications_compatible(track.classification, observation.classification_hint):
				continue
			if track.sensor_observed_at.has(3) and is_equal_approx(track.sensor_observed_at[3], observation.timestamp):
				continue
			var prediction := track.estimated_position + track.estimated_velocity * maxf(0, observation.timestamp - knowledge.simulation_time)
			var distance := prediction.distance_to(observation.measured_position)
			var gate := knowledge.association_gate + knowledge.maximum_association_speed * maxf(0, observation.timestamp - track.last_observed_at)
			if distance < gate and distance < nearest:
				expected = track
				nearest = distance
		assert_same(knowledge._associate(observation), expected)

func test_observations_create_independent_tracks_and_update_estimates() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(4, 0.0, Vector3(100.0, 60.0, 20.0), 0.9, 8.0, 0.8)
	var track := knowledge.submit_observation(first)
	assert_eq(track.track_id, 1)
	assert_eq(track.state, PlayerTrack.State.CONFIRMED)
	assert_eq(track.estimated_position, first.measured_position)
	assert_ne(track as Variant, first as Variant)
	var second := SensorObservation.new()
	second.setup(4, 1.0, Vector3(110.0, 60.0, 20.0), 0.8, 10.0, 0.8)
	assert_same(knowledge.submit_observation(second), track)
	assert_gt(track.estimated_velocity.x, 0.0)
	assert_eq(track.contributing_sensor_ids, [4])

func test_unobserved_track_coasts_then_is_lost_and_removed() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var observation := SensorObservation.new()
	observation.setup(2, 0.0, Vector3.ZERO, 0.9, 5.0, 0.8)
	var track := knowledge.submit_observation(observation)
	knowledge.gameplay_tick(knowledge.coast_after)
	assert_eq(track.state, PlayerTrack.State.COASTING)
	knowledge.gameplay_tick(knowledge.lost_after - knowledge.coast_after)
	assert_eq(track.state, PlayerTrack.State.LOST)
	assert_true(knowledge.get_active_tracks().is_empty())
	knowledge.gameplay_tick(knowledge.remove_after - knowledge.lost_after)
	assert_true(knowledge.tracks.is_empty())

func test_nearest_observation_outside_gate_creates_another_track() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(1, 0.0, Vector3.ZERO, 0.8, 10.0, 0.8)
	knowledge.submit_observation(first)
	var distant := SensorObservation.new()
	var elapsed := 0.1
	var dynamic_gate := knowledge.association_gate + knowledge.maximum_association_speed * elapsed
	distant.setup(1, elapsed, Vector3(dynamic_gate + 1.0, 0.0, 0.0), 0.8, 10.0, 0.8)
	knowledge.submit_observation(distant)
	assert_eq(knowledge.tracks.size(), 2)

func test_elapsed_time_expands_gate_for_high_speed_contact() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(1, 0.0, Vector3.ZERO, 0.9, 8.0, 0.4)
	var track := knowledge.submit_observation(first)
	var fast_followup := SensorObservation.new()
	fast_followup.setup(1, 0.4, Vector3(100.0, 0.0, 0.0), 0.9, 8.0, 0.4)
	assert_same(knowledge.submit_observation(fast_followup), track)
	assert_eq(knowledge.tracks.size(), 1)

func test_close_formation_misassociation_cannot_launch_track_marker_away() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(1, 0.0, Vector3.ZERO, 0.9, 8.0, 0.4, &"small_uav")
	var track := knowledge.submit_observation(first)
	var adjacent_contact := SensorObservation.new()
	adjacent_contact.setup(1, 0.01, Vector3(80.0, 0.0, 0.0), 0.9, 8.0, 0.4, &"small_uav")
	assert_same(knowledge.submit_observation(adjacent_contact), track)
	assert_lte(track.estimated_velocity.length(), knowledge.maximum_association_speed)
	knowledge.gameplay_tick(0.4)
	var followup := SensorObservation.new()
	followup.setup(1, knowledge.simulation_time, Vector3(17.0, 0.0, 0.0), 0.9, 8.0, 0.4, &"small_uav")
	assert_same(knowledge.submit_observation(followup), track)
	assert_eq(knowledge.tracks.size(), 1)
	assert_lte(track.estimated_velocity.length(), knowledge.maximum_association_speed)

func test_dynamic_gate_does_not_merge_different_classifications() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var aircraft := SensorObservation.new()
	aircraft.setup(1, 0.0, Vector3.ZERO, 0.9, 8.0, 0.4, &"aircraft", ThreatDefinition.Affiliation.HOSTILE, 0.4)
	knowledge.submit_observation(aircraft)
	var rocket := SensorObservation.new()
	rocket.setup(1, 0.4, Vector3(100.0, 0.0, 0.0), 0.9, 8.0, 0.4, &"rocket", ThreatDefinition.Affiliation.HOSTILE, 0.4)
	knowledge.submit_observation(rocket)
	assert_eq(knowledge.tracks.size(), 2)

func test_same_scan_observations_cannot_collapse_into_one_track() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(1, 1.0, Vector3.ZERO, 0.8, 10.0, 0.8)
	knowledge.submit_observation(first)
	var nearby := SensorObservation.new()
	nearby.setup(1, 1.0, Vector3(20.0, 0.0, 0.0), 0.8, 10.0, 0.8)
	knowledge.submit_observation(nearby)
	assert_eq(knowledge.tracks.size(), 2)

func test_track_quality_classification_and_affiliation_confidence_are_independent() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var observation := SensorObservation.new()
	observation.setup(3, 0.0, Vector3.ZERO, 0.9, 5.0, 0.8, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.4)
	var track := knowledge.submit_observation(observation)
	assert_eq(track.classification, &"uav")
	assert_eq(track.affiliation, PlayerTrack.Affiliation.HOSTILE)
	assert_gt(track.track_quality, track.classification_confidence)
	assert_ne(track.classification_confidence, track.affiliation_confidence)
	var second := SensorObservation.new()
	second.setup(3, 0.4, Vector3(10.0, 0.0, 0.0), 0.9, 5.0, 0.4, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.4)
	knowledge.submit_observation(second)
	assert_gt(track.classification_confidence, 0.2)

func test_different_sensors_fuse_same_time_observations_into_one_track() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var search_observation := SensorObservation.new()
	search_observation.setup(1, 1.0, Vector3(100.0, 50.0, 0.0), 0.55, 20.0, 0.4, &"air_contact", ThreatDefinition.Affiliation.HOSTILE, 0.2)
	var track := knowledge.submit_observation(search_observation)
	var precision_observation := SensorObservation.new()
	precision_observation.setup(2, 1.0, Vector3(102.0, 50.0, 0.0), 0.9, 5.0, 0.15, &"uav", ThreatDefinition.Affiliation.HOSTILE, 0.5)
	assert_same(knowledge.submit_observation(precision_observation), track)
	assert_eq(knowledge.tracks.size(), 1)
	assert_eq(track.contributing_sensor_ids, [1, 2])
	assert_lt(track.position_uncertainty, 20.0)
	assert_eq(track.classification, &"uav")
