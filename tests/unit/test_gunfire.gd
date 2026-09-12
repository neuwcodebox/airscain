extends GutTest

func test_expired_airburst_flashes_leave_the_draw_list_while_smoke_lingers() -> void:
	var runtime := add_child_autofree(GunfireRuntime.new()) as GunfireRuntime
	var expired_round := _round(Vector3.ZERO, Vector3.ZERO)
	expired_round.age = expired_round.lifetime
	runtime.rounds.append(expired_round)
	runtime.gameplay_tick(0.05)
	assert_eq(runtime.flashes.multimesh.visible_instance_count, 1)
	runtime.gameplay_tick(0.1)
	assert_eq(runtime.flashes.multimesh.visible_instance_count, 0)
	assert_eq(runtime.smoke.multimesh.visible_instance_count, 1)

const DEFINITION := preload("res://defense/close_in_gun/close_in_gun.tres")
const THREAT := preload("res://main/first_scenario.tres")

class MovingTarget:
	extends ThreatUnit
	var velocity := Vector3(0, 0, 45)
	func presentation_velocity() -> Vector3:
		return velocity

class ExhaustiveRuntime:
	extends GunfireRuntime
	func _candidate_indices(snapshot: TargetSnapshot, _start: Vector3, _end: Vector3, _radius: float) -> PackedInt32Array:
		return snapshot.indices

func test_spatial_candidates_match_exhaustive_combat_across_motion_and_lifecycle() -> void:
	for seed_value: int in [12, 73129, 901]:
		var spatial := _runtime()
		var exhaustive := add_child_autofree(ExhaustiveRuntime.new()) as GunfireRuntime
		spatial.registry = ThreatRegistry.new()
		exhaustive.registry = ThreatRegistry.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var actual_events: Array[Array] = []
		var expected_events: Array[Array] = []
		spatial.round_detonated.connect(func(position: Vector3, reason: StringName) -> void: actual_events.append([position, reason]))
		exhaustive.round_detonated.connect(func(position: Vector3, reason: StringName) -> void: expected_events.append([position, reason]))
		var pairs: Array[Array] = []
		for index: int in 100:
			var position := Vector3(rng.randf_range(-320, 320), rng.randf_range(60, 160), rng.randf_range(-320, 320))
			var velocity := Vector3(rng.randf_range(-300, 300), rng.randf_range(-70, 70), rng.randf_range(-300, 300))
			pairs.append(_target_pair(spatial, exhaustive, index, position, velocity))
		for index: int in 100:
			var target := pairs[index][0] as MovingTarget
			var offset := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))
			var round := _round(target.position + offset, -offset.normalized() * 620, rng.randf_range(0, 0.1))
			spatial.rounds.append(round.duplicate())
			exhaustive.rounds.append(round.duplicate())
		watch_signals(spatial)
		watch_signals(exhaustive)
		for step: int in 40:
			if step == 8:
				# Both removed targets and later registrations must be visible next step.
				spatial.registry.remove(pairs[0][0])
				exhaustive.registry.remove(pairs[0][1])
				pairs.append(_target_pair(spatial, exhaustive, 200, Vector3(-64, 100, 64), Vector3(250, 0, -250)))
			var delta := 0.035 if step % 3 == 0 else 0.01
			spatial.gameplay_tick(delta)
			exhaustive.gameplay_tick(delta)
			assert_eq(spatial.capture_state(), exhaustive.capture_state(), "seed %d step %d surviving rounds" % [seed_value, step])
			assert_eq(spatial.bursts, exhaustive.bursts, "seed %d step %d detonation positions, reasons and order" % [seed_value, step])
			assert_eq(actual_events, expected_events, "seed %d step %d event history" % [seed_value, step])
			for pair: Array in pairs:
				var actual := pair[0] as MovingTarget
				var expected := pair[1] as MovingTarget
				assert_eq(actual.health, expected.health, "seed %d step %d target %d health" % [seed_value, step, actual.runtime_id])
				actual.position += actual.velocity * delta
				expected.position += expected.velocity * delta
		assert_eq(get_signal_emit_count(spatial, "round_fired"), get_signal_emit_count(exhaustive, "round_fired"), "seed %d fired event count" % seed_value)
		assert_eq(get_signal_emit_count(spatial, "round_detonated"), get_signal_emit_count(exhaustive, "round_detonated"), "seed %d detonation event count" % seed_value)
		var damaged := 0
		for pair: Array in pairs:
			if (pair[0] as MovingTarget).health < 2.0:
				damaged += 1
		assert_gt(damaged, 0, "seed %d differential workload must exercise actual hits" % seed_value)

func _target_pair(spatial: GunfireRuntime, exhaustive: GunfireRuntime, id_value: int, position: Vector3, velocity: Vector3) -> Array:
	var pair: Array[MovingTarget] = []
	for runtime: GunfireRuntime in [spatial, exhaustive]:
		var target := add_child_autofree(MovingTarget.new()) as MovingTarget
		target.setup(id_value, _threat_definition(&"swarm_uav"))
		target.position = position
		target.velocity = velocity
		target.health = 2.0
		runtime.registry.add(target)
		pair.append(target)
	return pair

func test_spatial_query_keeps_boundary_crossings_and_registry_tie_order() -> void:
	var runtime := _runtime()
	runtime.registry = ThreatRegistry.new()
	for index: int in 80:
		var target := add_child_autofree(MovingTarget.new()) as MovingTarget
		target.setup(index, _threat_definition(&"swarm_uav"))
		target.position = Vector3(1000 + index * 90, 100, 1000)
		target.velocity = Vector3.ZERO
		target.health = 100
		runtime.registry.add(target)
	var first := runtime.registry.get_active()[0] as MovingTarget
	var last := runtime.registry.get_active()[-1] as MovingTarget
	# Initial target positions straddle a negative cell boundary and converge
	# at the round's closest point with equal fractions in this integration step.
	first.position = Vector3(-65, 100, -65)
	last.position = Vector3(-63, 100, -65)
	first.velocity = Vector3(100, 0, 0)
	last.velocity = Vector3(-100, 0, 0)
	var round := _round(Vector3(-64, 100, -71), Vector3(0, 0, 600))
	round.age = 0.1
	runtime.rounds.append(round)
	runtime.gameplay_tick(0.02)
	assert_true(runtime.rounds.is_empty())
	assert_eq(first.health, 100.0)
	assert_eq(last.health, 98.0, "equal closest fractions keep the last registry candidate")

func _runtime() -> GunfireRuntime:
	return add_child_autofree(GunfireRuntime.new()) as GunfireRuntime

func test_fast_crossing_target_is_not_rejected_by_swept_broad_phase() -> void:
	var runtime := _runtime()
	var target := add_child_autofree(MovingTarget.new()) as MovingTarget
	target.setup(9, _threat_definition(&"swarm_uav"))
	target.health = 100
	target.position = Vector3(6, 100, 100)
	target.velocity = Vector3(0, 0, -10000)
	runtime.registry = ThreatRegistry.new()
	runtime.registry.add(target)
	var round := _round(Vector3(0, 100, 0), Vector3(600, 0, 0))
	round.age = 0.1
	runtime.rounds.append(round)
	runtime.gameplay_tick(0.02)
	assert_eq(target.health, 98.0)
	assert_true(runtime.rounds.is_empty())

func _round(position: Vector3, velocity: Vector3, delay: float = 0) -> Dictionary:
	return {"position": position, "velocity": velocity, "age": -delay, "lifetime": 1.05, "damage": 2.0, "radius": 3.5, "emitted": false}

func _target(runtime: GunfireRuntime, position: Vector3) -> ThreatUnit:
	var registry := ThreatRegistry.new()
	var threat := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	threat.setup(9, _threat_definition(&"swarm_uav"))
	threat.health = 100
	threat.position = position
	registry.add(threat)
	runtime.registry = registry
	return threat

func test_rounds_deal_damage_only_at_a_swept_proximity_encounter() -> void:
	var runtime := _runtime()
	var target := _target(runtime, Vector3(120, 100, 0))
	runtime.rounds.append(_round(Vector3(0, 100, 0), Vector3(600, 0, 0)))
	watch_signals(runtime)
	runtime.gameplay_tick(0.1)
	assert_eq(target.health, 100.0)
	assert_eq(runtime.rounds.size(), 1)
	assert_almost_eq((runtime.rounds[0].position as Vector3).x, 60.0, 0.01)
	runtime.gameplay_tick(0.15)
	assert_eq(target.health, 98.0)
	assert_eq(runtime.rounds.size(), 0)
	assert_signal_emit_count(runtime, "round_detonated", 1)
	assert_eq(get_signal_parameters(runtime, "round_detonated")[1], &"proximity")
	runtime.gameplay_tick(1.0)
	assert_eq(target.health, 98.0, "폭발 시각 효과가 피해를 반복하지 않습니다")

func test_evading_target_leaves_round_flying_past_aim_point_until_timed_burst() -> void:
	var runtime := _runtime()
	var target := _target(runtime, Vector3(120, 100, 0))
	runtime.rounds.append(_round(Vector3(0, 100, 0), Vector3(600, 0, 0)))
	watch_signals(runtime)
	runtime.gameplay_tick(0.1)
	target.position.z = 30
	runtime.gameplay_tick(0.4)
	assert_eq(target.health, 100.0)
	assert_eq(runtime.rounds.size(), 1)
	assert_gt((runtime.rounds[0].position as Vector3).x, 250.0)
	assert_eq((runtime.rounds[0].position as Vector3).z, 0.0, "발사 후 표적을 따라 휘지 않습니다")
	runtime.gameplay_tick(0.6)
	assert_eq(runtime.rounds.size(), 0)
	assert_signal_emit_count(runtime, "round_detonated", 1)
	assert_eq(get_signal_parameters(runtime, "round_detonated")[1], &"timeout")
	assert_gt((get_signal_parameters(runtime, "round_detonated")[0] as Vector3).x, 600.0)
	assert_eq(target.health, 100.0)
	assert_gt(runtime.flashes.multimesh.visible_instance_count, 0)

func test_burst_emits_rounds_over_time_and_reuses_fixed_render_buffers() -> void:
	var runtime := _runtime()
	var child_count := runtime.get_child_count()
	var buffer := runtime.cores.multimesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	watch_signals(runtime)
	runtime.enqueue(Vector3(0, 100, 0), Vector3(260, 140, 0), Vector3(0, 0, 30), 0.8, 1, DEFINITION, rng)
	assert_eq(runtime.rounds.size(), DEFINITION.rounds_per_burst)
	assert_signal_not_emitted(runtime, "round_fired")
	runtime.gameplay_tick(0.01)
	assert_signal_emit_count(runtime, "round_fired", 1)
	assert_eq(runtime.cores.multimesh.visible_instance_count, 1)
	runtime.gameplay_tick(0.25)
	assert_signal_emit_count(runtime, "round_fired", DEFINITION.rounds_per_burst)
	assert_ne(runtime.rounds[0].velocity, runtime.rounds[1].velocity, "탄별 분산은 고정된 독립 탄도를 만듭니다")
	runtime.gameplay_tick(2.0)
	assert_eq(runtime.rounds.size(), 0)
	assert_eq(runtime.bursts.size(), 0)
	assert_same(runtime.cores.multimesh, buffer)
	assert_eq(runtime.get_child_count(), child_count)
	assert_eq(runtime.cores.multimesh.instance_count, GunfireRuntime.CAPACITY)

func test_zero_delta_and_snapshot_restore_preserve_round_flight() -> void:
	var runtime := _runtime_with_fired_and_pending_rounds()
	var saved := runtime.capture_state()
	runtime.gameplay_tick(0)
	assert_eq(runtime.capture_state(), saved)
	var restored := _runtime()
	var decoded: Array = JSON.parse_string(JSON.stringify(saved))
	assert_eq(GunfireRuntime.validation_error(decoded), "")
	restored.restore_state(decoded)
	runtime.gameplay_tick(0.3)
	restored.gameplay_tick(0.3)
	assert_eq(restored.rounds.size(), runtime.rounds.size())
	for index: int in runtime.rounds.size():
		assert_almost_eq(runtime.rounds[index].position as Vector3, restored.rounds[index].position as Vector3, Vector3.ONE * 0.001, "restored round %d position" % index)

func test_cancel_pending_preserves_already_fired_rounds() -> void:
	var runtime := _runtime_with_fired_and_pending_rounds()
	runtime.cancel_pending()
	assert_eq(runtime.rounds.size(), 1, "사격중지·재배치는 아직 나가지 않은 탄만 중단합니다")
	runtime.gameplay_tick(0.2)
	assert_gt((runtime.rounds[0].position as Vector3).x, 100.0)

func test_invalid_gunfire_save_is_rejected() -> void:
	var runtime := _runtime()
	runtime.rounds.append(_round(Vector3.ZERO, Vector3.RIGHT * 600))
	var saved := runtime.capture_state()
	assert_eq(GunfireRuntime.validation_error(saved), "")
	var invalid_variants: Array[Dictionary] = [
		{"label": "null document", "value": null},
		{"label": "object document", "value": {}},
		{"label": "null round", "value": [null]},
	]
	for variant: Dictionary in invalid_variants:
		assert_ne(GunfireRuntime.validation_error(variant.value), "", "invalid variant %s" % variant.label)
	for field: String in ["position", "velocity", "age", "lifetime", "damage", "radius", "emitted"]:
		var broken := saved.duplicate(true)
		broken[0].erase(field)
		assert_ne(GunfireRuntime.validation_error(broken), "", "invalid variant missing field %s" % field)

func test_legacy_magazine_state_is_migrated_without_mutating_the_source() -> void:
	var old := {"magazine": {"rounds": 12}}
	var migrated := DEFINITION.migrate_runtime_state(old, 17)
	assert_eq(migrated.gunfire, [])
	assert_eq(migrated.magazine, old.magazine)
	assert_false(old.has("gunfire"))

func _runtime_with_fired_and_pending_rounds() -> GunfireRuntime:
	var runtime := _runtime()
	runtime.rounds.append(_round(Vector3(0, 100, 0), Vector3(600, 0, 0)))
	runtime.rounds.append(_round(Vector3(0, 100, 0), Vector3(600, 0, 0), 0.2))
	runtime.gameplay_tick(0.05)
	return runtime

func test_round_stops_at_the_first_building_surface() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(THREAT)
	var runtime := _runtime()
	runtime.battlefield = battlefield
	var bounds := battlefield.city_building_bounds(0)
	var roof := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	runtime.rounds.append(_round(roof + Vector3.UP * 30, Vector3.DOWN * 600))
	watch_signals(runtime)
	runtime.gameplay_tick(0.1)
	assert_eq(runtime.rounds.size(), 0)
	assert_signal_emit_count(runtime, "round_detonated", 1)
	assert_eq(get_signal_parameters(runtime, "round_detonated")[1], &"surface")
	assert_almost_eq(get_signal_parameters(runtime, "round_detonated")[0] as Vector3, roof, Vector3.ONE * 0.01)

func test_leading_a_moving_track_can_intercept_its_physical_target() -> void:
	var runtime := _runtime()
	var target := add_child_autofree(MovingTarget.new()) as MovingTarget
	target.setup(7, _threat_definition(&"swarm_uav"))
	target.position = Vector3(220, 100, 0)
	target.health = 100
	runtime.registry = ThreatRegistry.new()
	runtime.registry.add(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 193
	runtime.enqueue(Vector3(0, 100, 0), target.position, target.velocity, 0.98, 1, DEFINITION, rng)
	for frame: int in 80:
		runtime.gameplay_tick(0.01)
		target.position += target.velocity * 0.01
	assert_lt(target.health, 100.0)
	assert_gte(target.health, 100.0 - DEFINITION.burst_damage)

func _threat_definition(id: StringName) -> ThreatDefinition:
	for entry: ThreatSpawnEntry in THREAT.threat_entries:
		if entry.threat_definition.id == id:
			return entry.threat_definition
	fail_test("missing threat definition %s" % id)
	return null
