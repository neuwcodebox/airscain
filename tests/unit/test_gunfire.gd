extends GutTest

func test_expired_airburst_flashes_leave_the_draw_list_while_smoke_lingers() -> void:
	var runtime := add_child_autofree(GunfireRuntime.new()) as GunfireRuntime
	runtime._detonate(Vector3.ZERO, &"timeout")
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

func _runtime() -> GunfireRuntime:
	return add_child_autofree(GunfireRuntime.new()) as GunfireRuntime

func _round(position: Vector3, velocity: Vector3, delay: float = 0) -> Dictionary:
	return {"position": position, "velocity": velocity, "age": -delay, "lifetime": 1.05, "damage": 2.0, "radius": 3.5, "emitted": false}

func _target(runtime: GunfireRuntime, position: Vector3) -> ThreatUnit:
	var registry := ThreatRegistry.new()
	var threat := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	threat.setup(9, THREAT.threat_entries[1].threat_definition)
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

func test_pause_pending_cancellation_and_snapshot_preserve_already_fired_rounds() -> void:
	var runtime := _runtime()
	runtime.rounds.append(_round(Vector3(0, 100, 0), Vector3(600, 0, 0)))
	runtime.rounds.append(_round(Vector3(0, 100, 0), Vector3(600, 0, 0), 0.2))
	runtime.gameplay_tick(0.05)
	var saved := runtime.capture_state()
	runtime.gameplay_tick(0)
	assert_eq(runtime.capture_state(), saved)
	var restored := _runtime()
	var decoded: Array = JSON.parse_string(JSON.stringify(saved))
	assert_eq(GunfireRuntime.validation_error(decoded), "")
	restored.restore_state(decoded)
	runtime.gameplay_tick(0.3)
	restored.gameplay_tick(0.3)
	for index: int in runtime.rounds.size():
		assert_almost_eq(runtime.rounds[index].position as Vector3, restored.rounds[index].position as Vector3, Vector3.ONE * 0.001)
	restored.restore_state(decoded)
	restored.cancel_pending()
	assert_eq(restored.rounds.size(), 1, "사격중지·재배치는 아직 나가지 않은 탄만 중단합니다")
	restored.gameplay_tick(0.2)
	assert_gt((restored.rounds[0].position as Vector3).x, 100.0)

func test_invalid_gunfire_save_is_rejected_and_old_magazine_state_is_migrated() -> void:
	var runtime := _runtime()
	runtime.rounds.append(_round(Vector3.ZERO, Vector3.RIGHT * 600))
	var saved := runtime.capture_state()
	assert_eq(GunfireRuntime.validation_error(saved), "")
	for invalid: Variant in [null, {}, [null]]:
		assert_ne(GunfireRuntime.validation_error(invalid), "")
	for field: String in ["position", "velocity", "age", "lifetime", "damage", "radius", "emitted"]:
		var broken := saved.duplicate(true)
		broken[0].erase(field)
		assert_ne(GunfireRuntime.validation_error(broken), "")
	var old := {"magazine": {"rounds": 12}}
	var migrated := DEFINITION.migrate_runtime_state(old, 17)
	assert_eq(migrated.gunfire, [])
	assert_eq(migrated.magazine, old.magazine)
	assert_false(old.has("gunfire"))

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
	target.setup(7, THREAT.threat_entries[1].threat_definition)
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
