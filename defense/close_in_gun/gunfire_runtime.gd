class_name GunfireRuntime
extends Node3D
## Unguided rounds and pooled airbursts, advanced only by simulation time.

signal round_fired(position: Vector3)
signal round_detonated(position: Vector3, reason: StringName)

const CAPACITY := 160
const GRAVITY := Vector3(0, -9.8, 0)
const ARM_TIME := 0.04
const SMOKE_TEXTURE := preload("res://effects/smoke_card_texture.tres")
var rounds: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var registry: ThreatRegistry
var battlefield: Battlefield
var cores: MultiMeshInstance3D
var glows: MultiMeshInstance3D
var flashes: MultiMeshInstance3D
var smoke: MultiMeshInstance3D

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cores = _buffer(Vector3(0.4, 0.4, 6.0), Color(1, 0.88, 0.52), 5.0)
	glows = _buffer(Vector3(1.0, 1.0, 8.0), Color(1, 0.38, 0.06, 0.22), 2.0)
	flashes = _buffer(Vector3.ONE, Color(1, 0.74, 0.32), 4.0, true)
	smoke = _buffer(Vector3.ONE, Color(0.21, 0.23, 0.25, 0.55), 0.0, true)

func _buffer(size: Vector3, color: Color, energy: float, card: bool = false) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.emission_enabled = energy > 0
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	var mesh: Mesh
	if card:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		material.albedo_texture = SMOKE_TEXTURE
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		quad.material = material
		mesh = quad
	else:
		var box := BoxMesh.new()
		box.size = size
		box.material = material
		mesh = box
	var instance := MultiMeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.use_colors = true
	instance.multimesh.mesh = mesh
	instance.multimesh.instance_count = CAPACITY
	instance.multimesh.custom_aabb = AABB(-Vector3.ONE, Vector3.ONE * 2.0)
	for index: int in CAPACITY:
		instance.multimesh.set_instance_color(index, Color.WHITE)
	instance.multimesh.visible_instance_count = 0
	add_child(instance)
	return instance

func enqueue(origin: Vector3, target: Vector3, target_velocity: Vector3, quality: float, match_ratio: float, definition: CloseInGunDefinition, rng: RandomNumberGenerator) -> void:
	var flight := origin.distance_to(target) / definition.muzzle_velocity
	var dispersion := (0.006 + (1.0 - quality * definition.base_accuracy) * 0.06 + flight * 0.008) / sqrt(maxf(0.15, match_ratio))
	for index: int in definition.rounds_per_burst:
		if rounds.size() >= CAPACITY:
			break
		var delay := float(index) / definition.rounds_per_second
		var aim := target + target_velocity * (flight + delay) - GRAVITY * flight * flight * 0.5
		var direction := origin.direction_to(aim)
		var basis := Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP)
		direction = (direction + basis.x * rng.randfn(0, dispersion) + basis.y * rng.randfn(0, dispersion)).normalized()
		rounds.append({"position": origin, "velocity": direction * definition.muzzle_velocity, "age": -delay, "lifetime": definition.shell_lifetime * rng.randf_range(0.9, 1.1), "damage": definition.burst_damage / definition.rounds_per_burst, "radius": definition.fuze_radius, "emitted": false})

func cancel_pending() -> void:
	for index: int in range(rounds.size() - 1, -1, -1):
		if not bool(rounds[index].emitted):
			rounds.remove_at(index)

func gameplay_tick(delta: float) -> void:
	if delta <= 0 or rounds.is_empty() and bursts.is_empty():
		return
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining, 0.02)
		_step(step)
		remaining -= step
	_sync_visuals()

func _step(delta: float) -> void:
	for index: int in range(bursts.size() - 1, -1, -1):
		bursts[index].age = float(bursts[index].age) + delta
		if float(bursts[index].age) >= 0.85:
			bursts.remove_at(index)
	var targets: Array[ThreatUnit] = []
	if registry != null:
		targets = registry.get_active()
	var target_positions := PackedVector3Array()
	var target_steps := PackedVector3Array()
	var target_reaches := PackedFloat32Array()
	for target: ThreatUnit in targets:
		target_positions.append(target.get_aim_position())
		var target_velocity := target.presentation_velocity()
		target_steps.append(target_velocity)
		target_reaches.append(target_velocity.length() * delta)
	for index: int in range(rounds.size() - 1, -1, -1):
		var round := rounds[index]
		var previous_age := float(round.age)
		round.age = minf(previous_age + delta, float(round.lifetime))
		if float(round.age) < 0:
			continue
		if not bool(round.emitted):
			round.emitted = true
			round_fired.emit(round.position)
		var travel_time := float(round.age) - maxf(0, previous_age)
		var start: Vector3 = round.position
		var velocity: Vector3 = round.velocity
		var end := start + velocity * travel_time + GRAVITY * travel_time * travel_time * 0.5
		round.velocity = velocity + GRAVITY * travel_time
		var stop := 1.0
		var reason: StringName = &""
		if battlefield != null:
			var terrain_hit := battlefield.terrain_segment_impact(start, end)
			var building_hit := battlefield.building_segment_impact(start, end)
			for hit: Dictionary in [terrain_hit, building_hit]:
				if not hit.is_empty():
					var fraction := start.distance_to(hit.position) / maxf(0.001, start.distance_to(end))
					if fraction <= stop:
						stop = fraction
						reason = &"surface"
		var victim: ThreatUnit
		if float(round.age) >= ARM_TIME:
			var armed_fraction := clampf((ARM_TIME - maxf(0, previous_age)) / maxf(0.00001, travel_time), 0, 1)
			var round_reach := start.distance_to(end) + float(round.radius)
			for target_index: int in targets.size():
				var offset := start - target_positions[target_index]
				# Conservative swept sphere: moving targets can enter the fuze this step.
				var reach := round_reach + target_reaches[target_index] + 0.001
				if offset.length_squared() > reach * reach:
					continue
				var target := targets[target_index]
				if not is_instance_valid(target) or not target.is_targetable():
					continue
				var relative_step := end - start - target_steps[target_index] * travel_time
				var along := clampf(-offset.dot(relative_step) / maxf(0.00001, relative_step.length_squared()), armed_fraction, 1)
				if along <= stop and (offset + relative_step * along).length_squared() <= float(round.radius) * float(round.radius):
					stop = along
					victim = target
					reason = &"proximity"
		round.position = start.lerp(end, stop)
		if reason.is_empty() and float(round.age) >= float(round.lifetime):
			reason = &"timeout"
		if not reason.is_empty():
			_detonate(round.position, reason)
			rounds.remove_at(index)
			if is_instance_valid(victim):
				victim.receive_damage(float(round.damage))

func _detonate(position: Vector3, reason: StringName) -> void:
	if bursts.size() >= CAPACITY:
		bursts.pop_front()
	bursts.append({"position": position, "age": 0.0})
	round_detonated.emit(position, reason)

func _sync_visuals() -> void:
	var visible_rounds := 0
	var bounds := AABB()
	var has_bounds := false
	for round: Dictionary in rounds:
		if not bool(round.emitted):
			continue
		var direction := (round.velocity as Vector3).normalized()
		var basis := Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP)
		var pose := Transform3D(basis, round.position)
		bounds = bounds.expand(pose.origin) if has_bounds else AABB(pose.origin, Vector3.ZERO)
		has_bounds = true
		cores.multimesh.set_instance_transform(visible_rounds, pose)
		glows.multimesh.set_instance_transform(visible_rounds, pose)
		visible_rounds += 1
	cores.multimesh.visible_instance_count = visible_rounds
	glows.multimesh.visible_instance_count = visible_rounds
	var visible_flashes := 0
	for index: int in bursts.size():
		var burst := bursts[index]
		var age := float(burst.age)
		bounds = bounds.expand(burst.position) if has_bounds else AABB(burst.position, Vector3.ZERO)
		has_bounds = true
		var flash_size := 3.0 + minf(age / 0.08, 1.0) * 4.0
		if age < 0.12:
			flashes.multimesh.set_instance_transform(visible_flashes, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * flash_size), burst.position))
			flashes.multimesh.set_instance_color(visible_flashes, Color(1, 1, 1, maxf(0, 1 - age / 0.12)))
			visible_flashes += 1
		var smoke_size := 2.0 + age * 5.0
		smoke.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * smoke_size), (burst.position as Vector3) + Vector3(1, 1, 0) * age))
		smoke.multimesh.set_instance_color(index, Color(1, 1, 1, minf(age / 0.08, 1.0) * maxf(0, 1 - age / 0.85)))
	flashes.multimesh.visible_instance_count = visible_flashes
	smoke.multimesh.visible_instance_count = bursts.size()
	if has_bounds:
		for layer: MultiMeshInstance3D in [cores, glows, flashes, smoke]:
			layer.multimesh.custom_aabb = bounds.grow(12.0)

func capture_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for round: Dictionary in rounds:
		var state := round.duplicate()
		state.position = SaveDocument.vector3_to_data(round.position)
		state.velocity = SaveDocument.vector3_to_data(round.velocity)
		result.append(state)
	return result

func restore_state(states: Array) -> void:
	rounds.clear()
	bursts.clear()
	for state: Dictionary in states:
		var round := state.duplicate()
		round.position = SaveDocument.vector3_from_data(state.position)
		round.velocity = SaveDocument.vector3_from_data(state.velocity)
		rounds.append(round)
	_sync_visuals()

static func validation_error(states: Variant) -> String:
	if not states is Array or states.size() > CAPACITY:
		return "기관포 비행탄 목록이 올바르지 않습니다"
	for state: Variant in states:
		if not state is Dictionary:
			return "기관포 비행탄 상태가 올바르지 않습니다"
		for field: String in ["position", "velocity"]:
			if not state.get(field) is Array or state[field].size() != 3:
				return "기관포 비행 벡터가 올바르지 않습니다"
			for value: Variant in state[field]:
				if not (value is int or value is float) or not is_finite(float(value)):
					return "기관포 비행 좌표가 올바르지 않습니다"
		for field: String in ["age", "lifetime", "damage", "radius"]:
			var value: Variant = state.get(field)
			if not (value is int or value is float) or not is_finite(float(value)):
				return "기관포 신관 상태가 올바르지 않습니다"
		if not state.get("emitted") is bool or float(state.age) < -1 or float(state.age) > float(state.lifetime) or float(state.lifetime) <= ARM_TIME or float(state.lifetime) > 5 or float(state.damage) <= 0 or float(state.radius) <= 0:
			return "기관포 신관 범위가 올바르지 않습니다"
	return ""
