class_name CountermeasureBurst
extends Node3D

const BURN_DURATION := 3.6
const HEAD_COUNT := 4
var elapsed: float = 0.0
var duration: float = 9.0
var flare_positions: Array[Vector3] = []
var flare_velocities: Array[Vector3] = []
var smoke_trails: Array[LingeringSmokeTrail] = []
static var smoke_mesh: QuadMesh

func setup(countermeasure_type: StringName, source_velocity: Vector3 = Vector3.ZERO) -> void:
	elapsed = 0.0
	var uses_flare := countermeasure_type == &"flare"
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
	var forward := source_velocity.normalized() if source_velocity.length() > 1.0 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP).normalized()
	for index: int in HEAD_COUNT:
		var spread := (float(index) - 1.5) * 9.0
		var velocity := source_velocity * 0.35 - forward * 10.0 + side * spread + Vector3.UP * 6.0
		flare_positions.append(global_position)
		flare_velocities.append(velocity)
		var trail := LingeringSmokeTrail.new()
		trail.puff_mesh = _smoke_mesh()
		trail.amount = 160
		trail.lifetime = 4.5
		trail.initial_scale = 0.55
		trail.final_scale = 1.8
		trail.sample_spacing = 0.35
		trail.drift_speed = 0.12
		add_child(trail)
		smoke_trails.append(trail)
	# Seed visible burn points and thin exhaust even in the first rendered frame.
	_advance_flares(0.12)

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
	var burning_delta := minf(delta, maxf(0.0, BURN_DURATION - elapsed))
	elapsed += delta
	if not flare_positions.is_empty():
		if burning_delta > 0.0:
			_advance_flares(burning_delta)
		$Flares.visible = elapsed < BURN_DURATION
	if elapsed >= duration:
		queue_free()

func _advance_flares(delta: float) -> void:
	var mesh := ($Flares as MultiMeshInstance3D).multimesh
	for index: int in flare_positions.size():
		var previous := flare_positions[index]
		flare_velocities[index] *= exp(-0.4 * delta)
		flare_velocities[index].y -= 5.0 * delta
		flare_positions[index] += flare_velocities[index] * delta
		var burn := 1.0 - smoothstep(0.4, 1.0, elapsed / BURN_DURATION)
		var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(0.05, burn)), to_local(flare_positions[index]))
		mesh.set_instance_transform(index, transform_value)
		smoke_trails[index].sample_world_segment(previous, flare_positions[index])
