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

class CapacityRadar:
	extends SearchRadar
	func altitude_in_envelope(_target_position: Vector3) -> bool:
		return true
	func _has_line_of_sight(_from: Vector3, _to: Vector3) -> bool:
		return true

class TimedThreat:
	extends ThreatUnit
	var action_seconds: float = INF
	func presentation_action_seconds() -> float:
		return action_seconds

func test_spatial_association_matches_exhaustive_observation_streams() -> void:
	for seed_value: int in [71, 73129]:
		assert_eq(_differential_stream_failure(seed_value), "", "공간 연결 differential stream seed %d" % seed_value)

func _differential_stream_failure(seed_value: int) -> String:
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
				if result.track_id != reference.track_id:
					return "seed %d frame %d sensor %d observation %d: indexed track %d, exhaustive track %d" % [seed_value, frame, sensor, index, result.track_id, reference.track_id]
		var actual_hash := JSON.stringify(actual.capture_state()).sha256_text()
		var expected_hash := JSON.stringify(expected.capture_state()).sha256_text()
		if actual_hash != expected_hash:
			return "seed %d frame %d: 전체 항적·센서 증거 상태가 다릅니다" % [seed_value, frame]
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
	if actual.narrowed_queries <= 0:
		return "seed %d: stream이 공간 후보 축소를 실행하지 않았습니다" % seed_value
	return ""

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
	assert_same(knowledge._associate(observation), knowledge.tracks[0], "동률은 track ID나 cell 순서가 아닌 원본 배열 순서를 따릅니다")
	knowledge.tracks[0].sensor_observed_at[99] = 0.0
	assert_same(knowledge._associate(observation), knowledge.tracks[1], "현재 scan에서 이미 관측된 항적은 제외합니다")
	knowledge.tracks[1].classification = &"rocket"
	assert_null(knowledge._associate(observation), "남은 호환 가능 항적이 없으면 연결하지 않습니다")

func test_association_index_is_current_inside_observation_callbacks() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var callback_result := {"count": 0, "first_failure": ""}
	var inspect := func(track: PlayerTrack) -> void:
		callback_result.count += 1
		var probe := SensorObservation.new()
		probe.setup(9999, knowledge.simulation_time, track.estimated_position, 0.9, 5.0, 0.1)
		if callback_result.first_failure.is_empty() and knowledge._associate(probe) != track:
			callback_result.first_failure = "callback %d track %d: signal 전에 새 cell membership이 반영되지 않았습니다" % [callback_result.count, track.track_id]
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
	assert_gt(int(callback_result.count), 80, "생성 및 이동 callback 경로를 모두 실행합니다")
	assert_eq(String(callback_result.first_failure), "")

func test_association_pruning_matches_nearest_compatible_unsampled_track() -> void:
	const SEED := 91271
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
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
	var first_failure := ""
	for query: int in 400:
		var observation := SensorObservation.new()
		observation.setup(3, 1.0, Vector3(rng.randf_range(-800, 800), rng.randf_range(0, 1000), rng.randf_range(-800, 800)), 0.9, 8, 0.1, classes[query % classes.size()])
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
		var actual := knowledge._associate(observation)
		if actual != expected:
			var actual_id := actual.track_id if actual != null else -1
			var expected_id := expected.track_id if expected != null else -1
			first_failure = "seed %d query %d: indexed track %d, exhaustive nearest track %d" % [SEED, query, actual_id, expected_id]
			break
	assert_eq(first_failure, "")

func test_observations_create_track_and_update_estimate() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(4, 0.0, Vector3(100.0, 60.0, 20.0), 0.9, 8.0, 0.8)
	var track := knowledge.submit_observation(first)
	assert_eq(track.track_id, 1)
	assert_eq(track.state, PlayerTrack.State.CONFIRMED)
	assert_eq(track.estimated_position, first.measured_position)
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
	assert_gt(track.classification_confidence, track.affiliation_confidence, "분류와 소속 판단은 서로 다른 증거 prior를 유지합니다")
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

func test_recent_sensor_contributors_replace_stale_history() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var first := SensorObservation.new()
	first.setup(1, 0.0, Vector3.ZERO, 0.9, 5.0, 0.4, &"uav")
	var track := knowledge.submit_observation(first)
	knowledge.gameplay_tick(1.8)
	var second := SensorObservation.new()
	second.setup(2, 1.8, Vector3.ZERO, 0.9, 5.0, 0.4, &"uav")
	knowledge.submit_observation(second)
	knowledge.gameplay_tick(0.21)
	assert_eq(track.contributing_sensor_ids, [2], "기여 센서 수는 과거 누적이 아니라 최근 관측을 뜻합니다")

func test_radar_priority_balances_damage_and_time_to_action() -> void:
	var radar := autofree(CapacityRadar.new()) as CapacityRadar
	var definition := preload("res://sensing/tracking_radar/tracking_radar.tres").duplicate(true) as SearchRadarDefinition
	radar.setup(11, definition)
	var ballistic := add_child_autofree(_timed_threat(101, preload("res://enemy/ballistic_missile/ballistic_missile.tres"), 20.0)) as TimedThreat
	var rocket := add_child_autofree(_timed_threat(102, preload("res://enemy/rocket_salvo/rocket.tres"), 20.0)) as TimedThreat
	assert_gt(radar._tracking_priority("ballistic", ballistic, 0.9), radar._tracking_priority("rocket", rocket, 0.9), "도달 시간이 같으면 예상 피해가 큰 탄도미사일을 우선합니다")
	rocket.action_seconds = 3.0
	ballistic.action_seconds = 40.0
	assert_gt(radar._tracking_priority("rocket", rocket, 0.9), radar._tracking_priority("ballistic", ballistic, 0.9), "임박한 로켓은 먼 탄도미사일보다 우선합니다")

func test_saturated_radar_limits_tracks_and_cycles_unstable_contacts() -> void:
	var radar := CapacityRadar.new()
	var antenna := Node3D.new()
	antenna.name = "Antenna"
	radar.add_child(antenna)
	add_child_autofree(radar)
	var definition := preload("res://sensing/search_radar/search_radar.tres").duplicate(true) as SearchRadarDefinition
	definition.tracking_capacity = 5
	definition.detection_range = 5000.0
	radar.setup(7, definition)
	var registry := ThreatRegistry.new()
	var knowledge := add_child_autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var battlefield := Battlefield.new()
	radar.configure_combat(registry, null)
	radar.configure_player_knowledge(battlefield, knowledge)
	for index: int in 6:
		var threat := _timed_threat(200 + index, preload("res://enemy/rocket_salvo/rocket.tres"), 20.0)
		threat.position = Vector3(index * 400.0, 100.0, 300.0)
		add_child_autofree(threat)
		registry.add(threat)
	radar._scan()
	assert_true(radar.saturated)
	assert_eq(radar.current_tracking_count(), 5)
	assert_true(radar.selection_status_rows().has({"label": "동시 추적", "value": "5 / 5", "warning": true}))
	knowledge.gameplay_tick(definition.scan_interval)
	radar._scan()
	knowledge.gameplay_tick(definition.scan_interval)
	radar._scan()
	assert_true(knowledge.tracks.any(func(track: PlayerTrack) -> bool: return track.capacity_limited), "순환 재탐색에서 빠진 기존 항적은 불안정 상태가 됩니다")
	battlefield.free()

func test_overlapping_radars_diversify_marginal_capacity_slots() -> void:
	var definition := preload("res://sensing/search_radar/search_radar.tres").duplicate(true) as SearchRadarDefinition
	definition.tracking_capacity = 5
	definition.detection_range = 5000.0
	var registry := ThreatRegistry.new()
	var knowledge := add_child_autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var battlefield := Battlefield.new()
	var radars: Array[CapacityRadar] = []
	for runtime_id: int in [7, 8]:
		var radar := CapacityRadar.new()
		var antenna := Node3D.new()
		antenna.name = "Antenna"
		radar.add_child(antenna)
		add_child_autofree(radar)
		radar.setup(runtime_id, definition)
		radar.configure_combat(registry, null)
		radar.configure_player_knowledge(battlefield, knowledge)
		radars.append(radar)
	for index: int in 6:
		var threat := add_child_autofree(_timed_threat(300 + index, preload("res://enemy/rocket_salvo/rocket.tres"), 20.0)) as TimedThreat
		threat.position = Vector3(index * 400.0, 100.0, 300.0)
		registry.add(threat)
	radars[0]._scan()
	radars[1]._scan()
	var combined: Dictionary[String, bool] = {}
	for radar: CapacityRadar in radars:
		for key: String in radar.tracked_contacts:
			combined[key] = true
	assert_gt(combined.size(), definition.tracking_capacity, "겹친 레이더의 순환 슬롯은 같은 한계 접촉만 중복하지 않습니다")
	battlefield.free()

func test_capacity_limited_marker_uses_irregular_yellow_visibility() -> void:
	var track := PlayerTrack.new()
	track.track_id = 77
	track.state = PlayerTrack.State.CONFIRMED
	track.affiliation = PlayerTrack.Affiliation.HOSTILE
	track.affiliation_confidence = 0.9
	track.capacity_limited = true
	var marker := add_child_autofree(TrackMarker.new()) as TrackMarker
	marker.setup(track)
	assert_eq(marker.icon.modulate, Color(1.0, 0.78, 0.22, 0.92))
	var saw_visible := false
	var saw_hidden := false
	for _sample: int in 100:
		marker._process(0.03)
		saw_visible = saw_visible or marker.icon.visible
		saw_hidden = saw_hidden or not marker.icon.visible
	assert_true(saw_visible and saw_hidden, "포화 항적은 고정 경고 대신 불규칙하게 나타났다 사라집니다")

func _timed_threat(id: int, definition: ThreatDefinition, seconds: float) -> TimedThreat:
	var threat := TimedThreat.new()
	threat.setup(id, definition)
	threat.action_seconds = seconds
	return threat
