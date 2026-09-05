class_name LingeringSmokeTrail
extends MultiMeshInstance3D

const VISUAL_UPDATE_INTERVAL := 1.0 / 15.0

@export var puff_mesh: QuadMesh
@export_range(32, 4096, 1) var amount: int = 1024
@export_range(1.0, 40.0, 0.5) var lifetime: float = 16.0
@export_range(0.5, 20.0, 0.5) var sample_spacing: float = 3.0
@export_range(1, 4, 1) var particles_per_sample: int = 1
@export_range(0.0, 2.0, 0.05) var sample_radius: float = 0.0
@export_range(1, 4, 1) var shadow_emission_stride: int = 2
@export_range(0.1, 0.42, 0.01) var shadow_radius_ratio: float = 0.34
@export_range(0.1, 8.0, 0.05) var initial_scale: float = 1.0
@export_range(0.1, 8.0, 0.05) var final_scale: float = 3.5
@export_range(0.0, 2.0, 0.01) var drift_speed: float = 0.18
@export_range(1.0, 40.0, 0.5) var release_fade_duration: float = 16.0
@export_range(0.1, 2.0, 0.1) var transparent_cleanup_delay: float = 0.5
@export var emitting: bool = true

var release_remaining: float = -1.0
var release_elapsed: float = 0.0
var sample_remainder: float = 0.0
var sampled_path_length: float = 0.0
var emitted_sample_count: int = 0
var last_emitted_world_position: Vector3
var current_opacity_ratio: float = 1.0
var smoke_material: StandardMaterial3D
var initial_material_alpha: float = 1.0
var shadow_particles: MultiMeshInstance3D
var shadow_material: ShaderMaterial
var current_shadow_opacity_ratio: float = 1.0

var _elapsed: float = 0.0
var _visual_update_remaining: float = 0.0
var _next_slot: int = 0
var _emission_serial: int = 0
var _birth_times := PackedFloat32Array()
var _positions := PackedVector3Array()
var _size_variations := PackedFloat32Array()
var _opacity_variations := PackedFloat32Array()
var _drift_vectors := PackedVector3Array()
var _serials := PackedInt32Array()
var _occupied_slots := PackedByteArray()
var _shadow_owner_serials := PackedInt32Array()
var _active_slots: Array[int] = []

func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_create_visible_multimesh()
	_create_shadow_multimesh()
	set_process(true)

func release_to(new_parent: Node) -> void:
	if new_parent == null or not is_instance_valid(new_parent):
		queue_free()
		return
	reparent(new_parent, true)
	emitting = false
	release_elapsed = 0.0
	release_remaining = release_fade_duration + transparent_cleanup_delay
	_set_opacity_ratio(1.0)

func sample_world_segment(from_position: Vector3, to_position: Vector3) -> void:
	if not emitting or multimesh == null:
		return
	var segment := to_position - from_position
	var distance := segment.length()
	if distance <= 0.001:
		return
	sampled_path_length += distance
	var direction := segment / distance
	var cursor := sample_spacing - sample_remainder
	while cursor <= distance:
		var world_position := from_position + direction * cursor
		for _particle_index: int in particles_per_sample:
			var serial := emitted_sample_count + 1
			var variation := SmokePuffDistribution.sample(serial, sample_radius)
			_emit_puff(world_position + variation.offset, variation)
			emitted_sample_count += 1
		last_emitted_world_position = world_position
		cursor += sample_spacing
	sample_remainder = fposmod(sample_remainder + distance, sample_spacing)

func smoke_bounds() -> AABB:
	var bounds := AABB()
	var has_point := false
	for slot: int in _active_slots:
		if _birth_times[slot] < 0.0 or _elapsed - _birth_times[slot] >= lifetime:
			continue
		var position := _positions[slot]
		if not has_point:
			bounds = AABB(position, Vector3.ZERO)
			has_point = true
		else:
			bounds = bounds.expand(position)
	return bounds.grow(puff_mesh.size.x * final_scale * 0.5) if has_point else AABB()

func active_puff_count() -> int:
	return _active_slots.size()

func _process(delta: float) -> void:
	_elapsed += delta
	_visual_update_remaining -= delta
	if _visual_update_remaining <= 0.0:
		_visual_update_remaining += VISUAL_UPDATE_INTERVAL
		_update_puffs()
	if release_remaining < 0.0:
		return
	release_elapsed += delta
	release_remaining -= delta
	var fade_progress := clampf(release_elapsed / release_fade_duration, 0.0, 1.0)
	_set_opacity_ratio(1.0 - smoothstep(0.0, 1.0, fade_progress))
	if release_remaining <= 0.0:
		queue_free()

func _create_visible_multimesh() -> void:
	var unique_mesh := puff_mesh.duplicate() as QuadMesh
	var source_material := unique_mesh.material
	if source_material is StandardMaterial3D:
		smoke_material = (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
		smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		unique_mesh.material = smoke_material
		initial_material_alpha = smoke_material.albedo_color.a
	var smoke_multimesh := MultiMesh.new()
	smoke_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	smoke_multimesh.use_colors = true
	smoke_multimesh.mesh = unique_mesh
	smoke_multimesh.instance_count = amount
	multimesh = smoke_multimesh
	_birth_times.resize(amount)
	_positions.resize(amount)
	_size_variations.resize(amount)
	_opacity_variations.resize(amount)
	_drift_vectors.resize(amount)
	_serials.resize(amount)
	_occupied_slots.resize(amount)
	smoke_multimesh.visible_instance_count = 0

func _create_shadow_multimesh() -> void:
	var proxy := SmokeShadowFactory.create(puff_mesh, 6, 3, shadow_radius_ratio)
	if proxy == null:
		push_error("Lingering smoke requires a StandardMaterial3D puff mesh")
		return
	shadow_material = proxy.material
	var shadow_multimesh := MultiMesh.new()
	shadow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	shadow_multimesh.use_colors = true
	shadow_multimesh.mesh = proxy.mesh
	var shadow_count := ceili(float(amount) / float(shadow_emission_stride))
	shadow_multimesh.instance_count = shadow_count
	_shadow_owner_serials.resize(shadow_count)
	shadow_multimesh.visible_instance_count = 0
	shadow_particles = MultiMeshInstance3D.new()
	shadow_particles.name = "SmokeShadow"
	shadow_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow_particles.multimesh = shadow_multimesh
	add_child(shadow_particles)

func _emit_puff(position: Vector3, variation: SmokePuffDistribution.Sample) -> void:
	var slot := _next_slot
	_next_slot = (_next_slot + 1) % amount
	if _occupied_slots[slot] == 0:
		_active_slots.append(slot)
	else:
		_hide_puff_slot(slot)
	_emission_serial += 1
	_birth_times[slot] = _elapsed
	_occupied_slots[slot] = 1
	_positions[slot] = position
	_size_variations[slot] = variation.size_ratio
	_opacity_variations[slot] = variation.opacity_ratio
	_drift_vectors[slot] = variation.drift_direction
	_serials[slot] = _emission_serial
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, slot + 1)
	_update_puff(slot)

func _update_puffs() -> void:
	for active_index: int in range(_active_slots.size() - 1, -1, -1):
		var slot := _active_slots[active_index]
		if _elapsed - _birth_times[slot] >= lifetime:
			_hide_puff_slot(slot)
			_occupied_slots[slot] = 0
			_active_slots.remove_at(active_index)
			continue
		_update_puff(slot)
	if _active_slots.is_empty():
		multimesh.visible_instance_count = 0
		shadow_particles.multimesh.visible_instance_count = 0

func _update_puff(slot: int) -> void:
	var age := _elapsed - _birth_times[slot]
	if age < 0.0 or age >= lifetime:
		_hide_puff_slot(slot)
		return
	var normalized_age := age / lifetime
	var alpha := _puff_alpha(normalized_age) * _opacity_variations[slot]
	var scale_value := lerpf(initial_scale, final_scale, smoothstep(0.0, 1.0, normalized_age)) * _size_variations[slot]
	var drift := _drift_vectors[slot] * drift_speed * age
	var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_value), _positions[slot] + drift)
	multimesh.set_instance_transform(slot, transform)
	multimesh.set_instance_color(slot, Color(1.0, 1.0, 1.0, alpha))
	if shadow_particles == null or not SmokePuffDistribution.casts_shadow(_serials[slot], shadow_emission_stride):
		return
	var shadow_slot := _shadow_slot_for_serial(_serials[slot])
	_shadow_owner_serials[shadow_slot] = _serials[slot]
	shadow_particles.multimesh.visible_instance_count = maxi(shadow_particles.multimesh.visible_instance_count, shadow_slot + 1)
	shadow_particles.multimesh.set_instance_transform(shadow_slot, transform)
	shadow_particles.multimesh.set_instance_color(shadow_slot, Color(1.0, 1.0, 1.0, alpha))

func _puff_alpha(normalized_age: float) -> float:
	if normalized_age < 0.015:
		return smoothstep(0.0, 0.015, normalized_age)
	if normalized_age < 0.45:
		return 1.0
	return 1.0 - smoothstep(0.45, 0.88, normalized_age)

func _set_opacity_ratio(ratio: float) -> void:
	current_opacity_ratio = clampf(ratio, 0.0, 1.0)
	current_shadow_opacity_ratio = current_opacity_ratio
	if smoke_material != null:
		var color := smoke_material.albedo_color
		color.a = initial_material_alpha * current_opacity_ratio
		smoke_material.albedo_color = color
	if shadow_material != null:
		shadow_material.set_shader_parameter("opacity_ratio", current_shadow_opacity_ratio)

func _hide_puff_slot(slot: int) -> void:
	_hide_instance(multimesh, slot)
	var serial := _serials[slot]
	if serial < 0 or not SmokePuffDistribution.casts_shadow(serial, shadow_emission_stride) or shadow_particles == null:
		return
	var shadow_slot := _shadow_slot_for_serial(serial)
	if _shadow_owner_serials[shadow_slot] == serial:
		_hide_instance(shadow_particles.multimesh, shadow_slot)
		_shadow_owner_serials[shadow_slot] = -1

func _shadow_slot_for_serial(serial: int) -> int:
	return SmokePuffDistribution.shadow_group(serial, shadow_emission_stride) % shadow_particles.multimesh.instance_count

func _hide_instance(target: MultiMesh, slot: int) -> void:
	var zero_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	target.set_instance_transform(slot, Transform3D(zero_basis, Vector3.ZERO))
	target.set_instance_color(slot, Color(1.0, 1.0, 1.0, 0.0))
