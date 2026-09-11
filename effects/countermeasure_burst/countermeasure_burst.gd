class_name CountermeasureBurst
extends Node3D

const BURN_DURATION := 4.0
const SMOKE_LIFETIME := 12.0
const HEAD_COUNT := 4
const RELEASE_INTERVAL := 0.14
const DRAG := 0.85
const LATERAL_EJECTION_SPEED := 24.0
var elapsed: float = 0.0
var duration: float = 0.0
var flare_positions: Array[Vector3] = []
var flare_velocities: Array[Vector3] = []
var smoke_trails: Array[LingeringSmokeTrail] = []
static var smoke_mesh: QuadMesh
var source: ThreatUnit
var follows_source := false
var launch_velocity := Vector3.ZERO
var previous_source_position := Vector3.ZERO
var released_count := 0
var flare_ages: Array[float] = []
var release_positions: Array[Vector3] = []

func setup(countermeasure_type: StringName, source_velocity: Vector3 = Vector3.ZERO, source_unit: ThreatUnit = null) -> void:
	elapsed = 0.0
	source = source_unit
	follows_source = source_unit != null
	launch_velocity = source_velocity
	previous_source_position = global_position
	released_count = 0
	flare_ages.clear()
	release_positions.clear()
	var uses_flare := countermeasure_type == &"flare"
	duration = (HEAD_COUNT - 1) * RELEASE_INTERVAL + BURN_DURATION + SMOKE_LIFETIME + 0.5 if uses_flare else maxf($Chaff.lifetime, $ChaffGlints.lifetime) + 0.5
	$Flares.visible = uses_flare
	$Chaff.emitting = not uses_flare
	$ChaffGlints.emitting = not uses_flare
	for trail: LingeringSmokeTrail in smoke_trails:
		trail.queue_free()
	smoke_trails.clear()
	flare_positions.clear()
	flare_velocities.clear()
	if not uses_flare:
		return
	($Flares as MultiMeshInstance3D).multimesh.instance_count = HEAD_COUNT
	for index: int in HEAD_COUNT:
		flare_positions.append(Vector3.ZERO)
		flare_velocities.append(Vector3.ZERO)
		flare_ages.append(-1.0)
		release_positions.append(Vector3.ZERO)
		($Flares as MultiMeshInstance3D).multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
		var trail := LingeringSmokeTrail.new()
		trail.puff_mesh = _smoke_mesh()
		trail.amount = 1024
		trail.lifetime = SMOKE_LIFETIME
		trail.initial_scale = 0.55
		trail.final_scale = 3.2
		trail.sample_spacing = 0.35
		trail.drift_speed = 0.12
		add_child(trail)
		smoke_trails.append(trail)
	_emit_flare(0, global_position, source_velocity)

static func _smoke_mesh() -> QuadMesh:
	if smoke_mesh == null:
		smoke_mesh = QuadMesh.new()
		smoke_mesh.size = Vector2.ONE
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(0.94, 0.94, 0.92, 0.3)
		material.albedo_texture = preload("res://effects/smoke_card_texture.tres")
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		smoke_mesh.material = material
	return smoke_mesh

func _process(delta: float) -> void:
	var before := elapsed
	elapsed += delta
	if not flare_positions.is_empty():
		var source_valid := not follows_source or is_instance_valid(source) and source.active and not source.is_queued_for_deletion()
		var current_position := source.global_position if follows_source and source_valid else global_position + launch_velocity * elapsed
		var current_velocity := source.presentation_velocity() if follows_source and source_valid else launch_velocity
		for index: int in HEAD_COUNT:
			var release_at := float(index) * RELEASE_INTERVAL
			if flare_ages[index] < 0.0 and elapsed >= release_at and source_valid:
				var fraction := clampf((release_at - before) / delta, 0.0, 1.0) if delta > 0.0 else 0.0
				_emit_flare(index, previous_source_position.lerp(current_position, fraction), current_velocity)
			if flare_ages[index] >= 0.0:
				var step := minf(maxf(0.0, elapsed - maxf(before, release_at)), maxf(0.0, BURN_DURATION - flare_ages[index]))
				_advance_flare(index, step)
		previous_source_position = current_position
	if elapsed >= duration:
		queue_free()

func _emit_flare(index: int, origin: Vector3, inherited_velocity: Vector3) -> void:
	var forward := inherited_velocity.normalized() if inherited_velocity.length() > 1.0 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var side := right.normalized() * (-1.0 if index % 2 == 0 else 1.0)
	var position := origin - forward * 3.0 + side * 2.0
	flare_positions[index] = position
	release_positions[index] = position
	flare_velocities[index] = inherited_velocity + side * LATERAL_EJECTION_SPEED - Vector3.UP * 2.0
	flare_ages[index] = 0.0
	released_count += 1
	_update_head(index)

func _advance_flare(index: int, delta: float) -> void:
	var previous := flare_positions[index]
	var decay := exp(-DRAG * delta)
	var travel := (1.0 - decay) / DRAG
	var terminal_velocity := Vector3.DOWN * (9.8 / DRAG)
	flare_positions[index] += flare_velocities[index] * travel + terminal_velocity * (delta - travel)
	flare_velocities[index] = flare_velocities[index] * decay + terminal_velocity * (1.0 - decay)
	flare_ages[index] += delta
	_update_head(index)
	smoke_trails[index].sample_world_segment(previous, flare_positions[index])

func _update_head(index: int) -> void:
	var burn := 1.0 - smoothstep(0.4, 1.0, flare_ages[index] / BURN_DURATION)
	var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * burn), to_local(flare_positions[index]))
	($Flares as MultiMeshInstance3D).multimesh.set_instance_transform(index, transform_value)
	$Flares.visible = flare_ages.any(func(age: float) -> bool: return age >= 0.0 and age < BURN_DURATION)
