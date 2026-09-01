extends GutTest

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
