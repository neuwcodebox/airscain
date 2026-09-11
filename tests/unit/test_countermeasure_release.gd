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
