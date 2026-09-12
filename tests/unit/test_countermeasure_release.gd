extends GutTest

const BURST_SCENE_PATH := "res://effects/countermeasure_burst/countermeasure_burst.tscn"

func test_failed_release_spends_one_charge_and_simultaneous_seekers_share_the_burst() -> void:
	var unit := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	unit.setup(1, _countermeasure_definition())
	var response := unit.respond_to_seeker(1.0, 0.0, 0.9)
	assert_true(response.released)
	assert_false(response.defeated)
	assert_eq(response.kind, &"flare")
	assert_eq(unit.countermeasure_charges_remaining, 1)
	assert_gt(unit.countermeasure_cooldown, 0.0)
	response = unit.respond_to_seeker(1.0, 0.0, 0.1)
	assert_false(response.released)
	assert_true(response.defeated)
	assert_eq(unit.countermeasure_charges_remaining, 1)

func test_countermeasure_cooldown_and_charges_round_trip() -> void:
	var definition := _countermeasure_definition()
	var unit := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	unit.setup(1, definition)
	assert_true(unit.respond_to_seeker(1.0, 0.0, 0.9).released)
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
	var burst := _burst()
	burst.position = Vector3(100, 150, 200)
	burst.setup(&"flare", Vector3(90, 0, 0))
	var before := burst.flare_positions.duplicate()
	_advance_burst(burst, 0.6)
	assert_true(burst.get_node("Flares").visible)
	assert_false((burst.get_node("Chaff") as GPUParticles3D).emitting)
	for index: int in burst.flare_positions.size():
		var case_label := "flare %d" % index
		assert_gt(burst.flare_positions[index].distance_to(before[index]), 1.0, "%s motion" % case_label)
		assert_gt(burst.smoke_trails[index].active_puff_count(), 0, "%s smoke trail" % case_label)
		var material := burst.smoke_trails[index].puff_mesh.material as StandardMaterial3D
		assert_false(material.emission_enabled, "%s smoke emission" % case_label)
		assert_lt(material.albedo_color.a, 0.4, "%s smoke alpha" % case_label)
	_advance_burst(burst, CountermeasureBurst.BURN_DURATION)
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
	assert_true(restored.countermeasure_decoy_active)
	assert_almost_eq(restored.countermeasure_decoy_remaining, 0.01, 0.0001)
	assert_eq(restored.countermeasure_decoy_position, interceptor.countermeasure_decoy_position)
	assert_eq(restored.countermeasure_decoy_velocity, Vector3(10, 0, 0))
	var before := restored.position
	restored.gameplay_tick(0.02)
	assert_false(restored.countermeasure_decoy_active)
	assert_false(restored.is_queued_for_deletion())
	assert_almost_eq(restored.position.distance_to(before), restored.speed * 0.02, 0.001)

func test_flare_residue_outlives_burning_without_exhausting_its_slots() -> void:
	var flare := _burst()
	flare.setup(&"flare", Vector3(150,0,0))
	for tick: int in 360:
		_advance_burst(flare, 1.0 / 30.0, true)
	assert_false(flare.get_node("Flares").visible)
	assert_false(flare.is_queued_for_deletion())
	for index: int in flare.smoke_trails.size():
		var trail := flare.smoke_trails[index]
		var case_label := "flare trail %d" % index
		assert_gt(trail.active_puff_count(), 0, "%s: 연소 종료 뒤에도 잔류 연기가 남는다" % case_label)
		assert_gt(flare.duration, CountermeasureBurst.BURN_DURATION + trail.lifetime, "%s lifetime" % case_label)
		assert_lt(trail.emitted_sample_count, trail.amount, "%s: 연소 궤적이 슬롯 부족으로 일찍 지워지지 않는다" % case_label)
	_advance_burst(flare, flare.duration)
	assert_true(flare.is_queued_for_deletion())

func test_chaff_parent_waits_for_both_particle_systems_to_expire() -> void:
	var chaff := _burst()
	chaff.setup(&"chaff")
	_advance_burst(chaff, 12.0)
	assert_false(chaff.is_queued_for_deletion())
	for name: String in ["Chaff", "ChaffGlints"]:
		var particles := chaff.get_node(name) as GPUParticles3D
		assert_gt(particles.lifetime, 12.0, "%s particle lifetime" % name)
		assert_gt(chaff.duration, particles.lifetime, "%s parent lifetime" % name)
		var ramp := (particles.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D
		assert_gt(ramp.gradient.sample(0.5).a, ramp.gradient.sample(0.9).a, "%s fade progression" % name)
		assert_eq(ramp.gradient.sample(1.0).a, 0.0, "%s terminal alpha" % name)
	_advance_burst(chaff, chaff.duration)
	assert_true(chaff.is_queued_for_deletion())

func test_chaff_uses_nonemissive_reflective_dipoles_and_sparse_glints() -> void:
	var burst := _burst()
	burst.setup(&"chaff")
	var chaff := burst.get_node("Chaff") as GPUParticles3D
	var glints := burst.get_node("ChaffGlints") as GPUParticles3D
	assert_between(chaff.amount, 160, 220)
	assert_gte(chaff.lifetime, 6.5)
	assert_between(glints.amount, 32, 64)
	assert_lt(glints.amount, chaff.amount / 3)
	var chaff_mesh := chaff.draw_pass_1 as BoxMesh
	var chaff_material := chaff_mesh.material as StandardMaterial3D
	var chaff_process := chaff.process_material as ParticleProcessMaterial
	var glint_process := glints.process_material as ParticleProcessMaterial
	assert_lt(chaff_mesh.size.x, 0.5)
	assert_gt(chaff_mesh.size.z, chaff_mesh.size.x * 5.0)
	assert_eq(chaff_material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	assert_gt(chaff_material.metallic, 0.8)
	assert_false(chaff_material.emission_enabled)
	assert_gte(chaff_process.emission_sphere_radius, 18.0)
	assert_lte(chaff_process.initial_velocity_max, 0.5)
	assert_lte(chaff_process.gravity.length(), 0.1)
	assert_true(chaff_process.particle_flag_align_y, "박편의 얇은 면은 무작위 방출 방향을 따라 기울어집니다")
	assert_true(chaff_process.particle_flag_rotate_y, "각 박편은 자신의 면 안에서도 서로 다른 각도를 가집니다")
	assert_eq(chaff_process.angle_min, -180.0)
	assert_eq(chaff_process.angle_max, 180.0)
	assert_lt(chaff_process.angular_velocity_min, 0.0)
	assert_gt(chaff_process.angular_velocity_max, 0.0)
	assert_eq(chaff.explosiveness, 1.0)
	assert_eq(glint_process.emission_sphere_radius, chaff_process.emission_sphere_radius)
	assert_lte(glint_process.initial_velocity_max, 0.2)
	assert_true(glints.draw_pass_1 is QuadMesh)
	var glint_material := (glints.draw_pass_1 as QuadMesh).material as ShaderMaterial
	# Headless rendering cannot sample the spatial shader's built-in TIME value.
	# Inspect only the active fragment body and verify a complete TIME-to-alpha path,
	# while leaving shimmer frequencies free to be tuned.
	var fragment := _shader_function_body(glint_material.shader, "void fragment()")
	assert_ne(fragment, "", "채프 glint에는 실행되는 fragment 함수가 필요합니다")
	assert_true(fragment.contains("float wave_a = sin(TIME"), "첫 시간 파형이 fragment에서 계산됩니다")
	assert_true(fragment.contains("float wave_b = sin(TIME"), "둘째 시간 파형이 fragment에서 계산됩니다")
	assert_true(fragment.contains("wave_a + wave_b"), "두 시간 파형이 실제 flash 강도에 사용됩니다")
	assert_true(fragment.contains("ALPHA = flash * COLOR.a * radial"), "시간 기반 flash가 최종 glint alpha를 구동합니다")
	assert_true(fragment.contains("distance(UV"), "glint alpha는 원형 falloff를 사용합니다")

func test_flares_release_in_sequence_from_the_moving_source() -> void:
	var source := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	source.setup(900, ThreatDefinition.new())
	source.position = Vector3(0, 200, 0)
	var burst := _burst()
	burst.position = source.position
	burst.setup(&"flare", Vector3(100,0,0), source)
	assert_eq(burst.released_count, 1)
	source.position.x = 10.0
	_advance_burst(burst, 0.1)
	assert_eq(burst.released_count, 1)
	source.position.x = 20.0
	_advance_burst(burst, 0.1)
	assert_eq(burst.released_count, 2)
	assert_gt(burst.release_positions[1].x, burst.release_positions[0].x + 8.0)
	assert_lt(burst.flare_ages[1], burst.flare_ages[0])
	source.active = false
	_advance_burst(burst, 1.0)
	assert_eq(burst.released_count, 2, "기체 소실 후 허공에서 추가 사출하지 않는다")
	assert_gt(burst.flare_ages[0], 1.0, "이미 사출된 플레어는 독립적으로 움직인다")

func test_flares_spread_on_both_sides_of_different_flight_directions() -> void:
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 0.4, 1).normalized(), Vector3.UP]
	for forward: Vector3 in directions:
		var right := forward.cross(Vector3.UP).normalized() if forward != Vector3.UP else Vector3.RIGHT
		var burst := _burst()
		var origin := Vector3(150, 200, 350)
		burst.position = origin
		burst.setup(&"flare", forward * 96.0)
		_advance_burst(burst, 1.0)
		for index: int in CountermeasureBurst.HEAD_COUNT:
			var case_label := "forward %s flare %d" % [forward, index]
			var side := -1.0 if index % 2 == 0 else 1.0
			var release_offset := (burst.release_positions[index] - origin).dot(right) * side
			var spread := (burst.flare_positions[index] - origin).dot(right) * side
			assert_gt(release_offset, 0.0, "%s: 사출구는 진행 방향 기준 좌우를 번갈아 사용한다" % case_label)
			assert_gt(spread, release_offset, "%s: 양쪽 플레어가 각각 기체 중심선 바깥으로 퍼진다" % case_label)
			assert_gt(burst.flare_velocities[index].dot(right) * side, 0.0, "%s 측방 속도" % case_label)
		var before := burst.flare_velocities[0].dot(right)
		_advance_burst(burst, 0.5)
		assert_lt(absf(burst.flare_velocities[0].dot(right)), absf(before), "forward %s: 측방 속도는 가속하지 않고 감쇠한다" % forward)

func test_flare_sequence_and_drag_are_independent_of_frame_size() -> void:
	var coarse := _burst()
	var fine := _burst()
	coarse.setup(&"flare", Vector3(100,0,0))
	fine.setup(&"flare", Vector3(100,0,0))
	_advance_burst(coarse, 0.7)
	for tick: int in 70:
		_advance_burst(fine, 0.01)
	assert_eq(coarse.released_count, CountermeasureBurst.HEAD_COUNT)
	assert_eq(fine.released_count, coarse.released_count)
	for index: int in CountermeasureBurst.HEAD_COUNT:
		var case_label := "flare %d" % index
		assert_lt(coarse.flare_positions[index].distance_to(fine.flare_positions[index]), 0.002, "%s position" % case_label)
		assert_lt(coarse.flare_velocities[index].distance_to(fine.flare_velocities[index]), 0.002, "%s velocity" % case_label)
		assert_lt(coarse.flare_positions[index].y, coarse.release_positions[index].y, "%s descends" % case_label)
		assert_gt(coarse.flare_velocities[index].x, 0.0, "%s keeps forward velocity" % case_label)
		assert_lt(coarse.flare_velocities[index].x, 100.0, "%s forward drag" % case_label)

func _countermeasure_definition() -> ThreatDefinition:
	var definition := ThreatDefinition.new()
	definition.countermeasure_charges = 2
	definition.flare_effectiveness = 0.6
	return definition

func _burst() -> CountermeasureBurst:
	var scene := ResourceLoader.load(BURST_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_not_null(scene, "countermeasure burst scene loads independently")
	var burst := scene.instantiate() as CountermeasureBurst
	assert_not_null(burst, "countermeasure burst scene instantiates independently")
	return add_child_autofree(burst) as CountermeasureBurst

func _advance_burst(burst: CountermeasureBurst, delta: float, advance_trails: bool = false) -> void:
	burst._process(delta)
	if advance_trails:
		for trail: LingeringSmokeTrail in burst.smoke_trails:
			trail._process(delta)

func _shader_function_body(shader: Shader, signature: String) -> String:
	var code := shader.code
	var signature_start := code.find(signature)
	if signature_start < 0:
		return ""
	var body_start := code.find("{", signature_start)
	var body_end := code.find("}", body_start + 1)
	if body_start < 0 or body_end < 0:
		return ""
	var active_lines := PackedStringArray()
	for line: String in code.substr(body_start + 1, body_end - body_start - 1).split("\n"):
		active_lines.append(line.split("//", true, 1)[0])
	return "\n".join(active_lines)
