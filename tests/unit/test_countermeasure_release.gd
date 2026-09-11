extends GutTest

func test_failed_release_is_spent_and_a_burst_is_shared_by_simultaneous_seekers() -> void:
	var unit := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.countermeasure_charges = 2
	definition.flare_effectiveness = 0.6
	unit.setup(1, definition)
	var response := unit.respond_to_seeker(1.0, 0.0, 0.9)
	assert_true(response.released)
	assert_false(response.defeated)
	assert_eq(response.kind, &"flare")
	assert_eq(unit.countermeasure_charges_remaining, 1)
	response = unit.respond_to_seeker(1.0, 0.0, 0.1)
	assert_false(response.released)
	assert_true(response.defeated)
	assert_eq(unit.countermeasure_charges_remaining, 1)
	unit.gameplay_tick(0.0)
	assert_gt(unit.countermeasure_cooldown, 0.0)
	var restored := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	restored.setup(1, definition)
	restored.restore_state(unit.capture_state(), null, null)
	assert_eq(restored.countermeasure_cooldown, unit.countermeasure_cooldown)
	assert_eq(restored.countermeasure_kind, unit.countermeasure_kind)
	assert_eq(restored.countermeasure_charges_remaining, 1)
	restored.gameplay_tick(1.0)
	assert_true(restored.respond_to_seeker(1.0, 0.0, 0.9).released)
	assert_eq(restored.countermeasure_charges_remaining, 0)

func test_flare_burn_points_move_and_leave_thin_nonemissive_smoke() -> void:
	var burst := add_child_autofree(preload("res://effects/countermeasure_burst/countermeasure_burst.tscn").instantiate()) as CountermeasureBurst
	burst.position = Vector3(100, 150, 200)
	burst.setup(&"flare", Vector3(90, 0, 0))
	var before := burst.flare_positions.duplicate()
	burst._process(0.6)
	assert_true(burst.get_node("Flares").visible)
	assert_false((burst.get_node("Chaff") as GPUParticles3D).emitting)
	for index: int in burst.flare_positions.size():
		assert_gt(burst.flare_positions[index].distance_to(before[index]), 1.0)
		assert_gt(burst.smoke_trails[index].active_puff_count(), 0)
		var material := burst.smoke_trails[index].puff_mesh.material as StandardMaterial3D
		assert_false(material.emission_enabled)
		assert_lt(material.albedo_color.a, 0.4)
	burst._process(CountermeasureBurst.BURN_DURATION)
	assert_false(burst.get_node("Flares").visible)
	assert_false(burst.is_queued_for_deletion(), "연소가 끝나도 연기는 남는다")

func test_countermeasure_save_rejects_invalid_time_and_kind() -> void:
	var definition := ThreatDefinition.new()
	assert_eq(definition.countermeasure_state_validation_error({}), "")
	assert_ne(definition.countermeasure_state_validation_error({"cooldown": -1.0}), "")
	assert_ne(definition.countermeasure_state_validation_error({"evasion": INF}), "")
	assert_ne(definition.countermeasure_state_validation_error({"kind": "unknown"}), "")

func test_expired_decoy_resumes_guidance_without_teleporting() -> void:
	var interceptor := add_child_autofree(HomingInterceptor.new()) as HomingInterceptor
	var track := PlayerTrack.new()
	track.state = PlayerTrack.State.CONFIRMED
	track.estimated_position = Vector3(2000, 200, 0)
	interceptor.position = Vector3(0, 200, 0)
	interceptor.configure(track, ThreatRegistry.new(), MissileMunitionDefinition.new(), Vector3.RIGHT)
	interceptor.countermeasure_attempted = true
	interceptor.countermeasure_decoy_active = true
	interceptor.countermeasure_decoy_position = Vector3(1000, 200, 100)
	interceptor.countermeasure_decoy_remaining = 0.01
	interceptor.countermeasure_decoy_velocity = Vector3(10, 0, 0)
	var restored := add_child_autofree(HomingInterceptor.new()) as HomingInterceptor
	restored.restore_state(interceptor.capture_state(), track, ThreatRegistry.new())
	assert_almost_eq(restored.countermeasure_decoy_remaining, 0.01, 0.0001)
	assert_eq(restored.countermeasure_decoy_velocity, Vector3(10, 0, 0))
	var before := interceptor.position
	interceptor.gameplay_tick(0.02)
	assert_false(interceptor.countermeasure_decoy_active)
	assert_false(interceptor.is_queued_for_deletion())
	assert_almost_eq(interceptor.position.distance_to(before), interceptor.speed * 0.02, 0.001)

func test_residue_outlives_burning_and_parent_waits_for_particle_expiry() -> void:
	var scene := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
	var flare := add_child_autofree(scene.instantiate()) as CountermeasureBurst
	flare.setup(&"flare", Vector3(150,0,0))
	for tick: int in 360:
		flare._process(1.0 / 30.0)
		for trail: LingeringSmokeTrail in flare.smoke_trails:
			trail._process(1.0 / 30.0)
	assert_false(flare.get_node("Flares").visible)
	assert_false(flare.is_queued_for_deletion())
	for trail: LingeringSmokeTrail in flare.smoke_trails:
		assert_gt(trail.active_puff_count(), 0, "연소 종료 뒤에도 잔류 연기가 남는다")
		assert_gt(flare.duration, CountermeasureBurst.BURN_DURATION + trail.lifetime)
		assert_lt(trail.emitted_sample_count, trail.amount, "연소 궤적이 슬롯 부족으로 일찍 지워지지 않는다")
	var chaff := add_child_autofree(scene.instantiate()) as CountermeasureBurst
	chaff.setup(&"chaff")
	chaff._process(12.0)
	assert_false(chaff.is_queued_for_deletion())
	for name: String in ["Chaff", "ChaffGlints"]:
		var particles := chaff.get_node(name) as GPUParticles3D
		assert_gt(particles.lifetime, 12.0)
		assert_gt(chaff.duration, particles.lifetime)
		var ramp := (particles.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D
		assert_gt(ramp.gradient.sample(0.5).a, ramp.gradient.sample(0.9).a)
		assert_eq(ramp.gradient.sample(1.0).a, 0.0)
	flare._process(flare.duration)
	chaff._process(chaff.duration)
	assert_true(flare.is_queued_for_deletion())
	assert_true(chaff.is_queued_for_deletion())

func test_flares_release_in_sequence_from_the_moving_source() -> void:
	var source := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	source.setup(900, ThreatDefinition.new())
	source.position = Vector3(0, 200, 0)
	var burst := add_child_autofree(preload("res://effects/countermeasure_burst/countermeasure_burst.tscn").instantiate()) as CountermeasureBurst
	burst.position = source.position
	burst.setup(&"flare", Vector3(100,0,0), source)
	assert_eq(burst.released_count, 1)
	source.position.x = 10.0
	burst._process(0.1)
	assert_eq(burst.released_count, 1)
	source.position.x = 20.0
	burst._process(0.1)
	assert_eq(burst.released_count, 2)
	assert_gt(burst.release_positions[1].x, burst.release_positions[0].x + 8.0)
	assert_lt(burst.flare_ages[1], burst.flare_ages[0])
	source.active = false
	burst._process(1.0)
	assert_eq(burst.released_count, 2, "기체 소실 후 허공에서 추가 사출하지 않는다")
	assert_gt(burst.flare_ages[0], 1.0, "이미 사출된 플레어는 독립적으로 움직인다")

func test_flares_spread_on_both_sides_of_different_flight_directions() -> void:
	var scene := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 0.4, 1).normalized(), Vector3.UP]
	for forward: Vector3 in directions:
		var right := forward.cross(Vector3.UP).normalized() if forward != Vector3.UP else Vector3.RIGHT
		var burst := add_child_autofree(scene.instantiate()) as CountermeasureBurst
		var origin := Vector3(150, 200, 350)
		burst.position = origin
		burst.setup(&"flare", forward * 96.0)
		burst._process(1.0)
		for index: int in CountermeasureBurst.HEAD_COUNT:
			var side := -1.0 if index % 2 == 0 else 1.0
			var release_offset := (burst.release_positions[index] - origin).dot(right) * side
			var spread := (burst.flare_positions[index] - origin).dot(right) * side
			assert_gt(release_offset, 0.0, "사출구는 진행 방향 기준 좌우를 번갈아 사용한다")
			assert_gt(spread, release_offset, "양쪽 플레어가 각각 기체 중심선 바깥으로 퍼진다")
			assert_gt(burst.flare_velocities[index].dot(right) * side, 0.0)
		var before := burst.flare_velocities[0].dot(right)
		burst._process(0.5)
		assert_lt(absf(burst.flare_velocities[0].dot(right)), absf(before), "측방 속도는 가속하지 않고 감쇠한다")

func test_flare_sequence_and_drag_are_independent_of_frame_size() -> void:
	var scene := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
	var coarse := add_child_autofree(scene.instantiate()) as CountermeasureBurst
	var fine := add_child_autofree(scene.instantiate()) as CountermeasureBurst
	coarse.setup(&"flare", Vector3(100,0,0))
	fine.setup(&"flare", Vector3(100,0,0))
	coarse._process(0.7)
	for tick: int in 70:
		fine._process(0.01)
	assert_eq(coarse.released_count, CountermeasureBurst.HEAD_COUNT)
	assert_eq(fine.released_count, coarse.released_count)
	for index: int in CountermeasureBurst.HEAD_COUNT:
		assert_lt(coarse.flare_positions[index].distance_to(fine.flare_positions[index]), 0.002)
		assert_lt(coarse.flare_velocities[index].distance_to(fine.flare_velocities[index]), 0.002)
		assert_lt(coarse.flare_positions[index].y, coarse.release_positions[index].y)
		assert_gt(coarse.flare_velocities[index].x, 0.0)
		assert_lt(coarse.flare_velocities[index].x, 100.0)
