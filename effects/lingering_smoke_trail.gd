class_name LingeringSmokeTrail
extends MultiMeshInstance3D

const VISUAL_UPDATE_INTERVAL := 1.0 / 15.0
const TRAIL_SHADER := preload("res://effects/trail_smoke.gdshader")
const FADE_END_RATIO := 0.88
const VISIBLE_CHUNK_SIZE := 512
const BOUND_REFRESH_INTERVAL := 0.5

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
@export_range(0.0, 4.0, 0.1) var turbulence_strength: float = 0.0

var release_remaining: float = -1.0
var release_elapsed: float = 0.0
var sample_remainder: float = 0.0
var sampled_path_length: float = 0.0
var emitted_sample_count: int = 0
var last_emitted_world_position: Vector3
var current_opacity_ratio: float = 1.0
var smoke_material: ShaderMaterial
var shadow_particles: MultiMeshInstance3D
var shadow_material: ShaderMaterial
var current_shadow_opacity_ratio: float = 1.0

var _elapsed: float = 0.0
var _visual_update_remaining: float = 0.0
var _bound_refresh_remaining: float = 0.0
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
var _visible_chunks: Array[MultiMeshInstance3D] = []
var _chunk_bounds: Array[AABB] = []
var _chunk_has_bounds: Array[bool] = []
var _chunk_oldest_birth: Array[float] = []
var _needs_bounds_rebuild: bool = false
var _bounds := AABB()
var _has_bounds := false
var _bounds_dirty := false
var _oldest_birth: float = INF

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

func visible_chunk_instances() -> Array[MultiMeshInstance3D]:
	return _visible_chunks.duplicate()

## Advances an inert sample without exposing the frame callback.
func prepare_preview(delta: float) -> void:
	_process(delta)

func _process(delta: float) -> void:
	_elapsed += delta
	smoke_material.set_shader_parameter("trail_time", _elapsed)
	shadow_material.set_shader_parameter("trail_time", _elapsed)
	_visual_update_remaining -= delta
	if _visual_update_remaining <= 0.0:
		_visual_update_remaining = VISUAL_UPDATE_INTERVAL
		_update_puffs()
	if _needs_bounds_rebuild:
		_rebuild_bounds()
	_bound_refresh_remaining -= delta
	if _bounds_dirty or _bound_refresh_remaining <= 0.0:
		_refresh_culling_bounds()
		_bound_refresh_remaining = BOUND_REFRESH_INTERVAL
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
		var source := source_material as StandardMaterial3D
		smoke_material = ShaderMaterial.new()
		smoke_material.shader = TRAIL_SHADER
		smoke_material.set_shader_parameter("puff_texture", source.albedo_texture)
		smoke_material.set_shader_parameter("tint", source.albedo_color)
		_configure_motion(smoke_material)
		unique_mesh.material = smoke_material
	for chunk_index: int in ceili(float(amount) / float(VISIBLE_CHUNK_SIZE)):
		var smoke_multimesh := MultiMesh.new()
		smoke_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		smoke_multimesh.use_colors = true
		smoke_multimesh.use_custom_data = true
		smoke_multimesh.mesh = unique_mesh
		smoke_multimesh.instance_count = mini(VISIBLE_CHUNK_SIZE, amount - chunk_index * VISIBLE_CHUNK_SIZE)
		smoke_multimesh.custom_aabb = AABB(-Vector3.ONE, Vector3.ONE * 2.0)
		smoke_multimesh.visible_instance_count = 0
		var chunk: MultiMeshInstance3D = self
		if chunk_index > 0:
			chunk = MultiMeshInstance3D.new()
			chunk.name = "SmokeChunk%d" % chunk_index
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(chunk)
		chunk.multimesh = smoke_multimesh
		_visible_chunks.append(chunk)
		_chunk_bounds.append(AABB())
		_chunk_has_bounds.append(false)
		_chunk_oldest_birth.append(INF)
	_birth_times.resize(amount)
	_positions.resize(amount)
	_size_variations.resize(amount)
	_opacity_variations.resize(amount)
	_drift_vectors.resize(amount)
	_serials.resize(amount)
	_occupied_slots.resize(amount)

func _create_shadow_multimesh() -> void:
	var proxy := SmokeShadowFactory.create(puff_mesh, 6, 3, shadow_radius_ratio)
	if proxy == null:
		push_error("Lingering smoke requires a StandardMaterial3D puff mesh")
		return
	shadow_material = proxy.material
	shadow_material.set_shader_parameter("trail_enabled", true)
	_configure_motion(shadow_material)
	var shadow_multimesh := MultiMesh.new()
	shadow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	shadow_multimesh.use_colors = true
	shadow_multimesh.use_custom_data = true
	shadow_multimesh.mesh = proxy.mesh
	var shadow_count := ceili(float(amount) / float(shadow_emission_stride))
	shadow_multimesh.instance_count = shadow_count
	shadow_multimesh.custom_aabb = AABB(-Vector3.ONE, Vector3.ONE * 2.0)
	_shadow_owner_serials.resize(shadow_count)
	_shadow_owner_serials.fill(-1)
	shadow_multimesh.visible_instance_count = 0
	shadow_particles = MultiMeshInstance3D.new()
	shadow_particles.name = "SmokeShadow"
	SmokeShadowFactory.register_caster(shadow_particles)
	shadow_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shadow_particles.multimesh = shadow_multimesh
	add_child(shadow_particles)

func _configure_motion(material: ShaderMaterial) -> void:
	material.set_shader_parameter("trail_lifetime", lifetime)
	material.set_shader_parameter("trail_fade_end", FADE_END_RATIO)
	material.set_shader_parameter("trail_initial_scale", initial_scale)
	material.set_shader_parameter("trail_final_scale", final_scale)
	material.set_shader_parameter("trail_drift_speed", drift_speed)
	material.set_shader_parameter("trail_turbulence_strength", turbulence_strength)

func _emit_puff(position: Vector3, variation: SmokePuffDistribution.Sample) -> void:
	var slot := _next_slot
	_next_slot = (_next_slot + 1) % amount
	if _occupied_slots[slot] == 0:
		_active_slots.append(slot)
	else:
		_hide_puff_slot(slot)
		_needs_bounds_rebuild = true
	_emission_serial += 1
	_birth_times[slot] = _elapsed
	_occupied_slots[slot] = 1
	_positions[slot] = position
	_bounds = _bounds.expand(position) if _has_bounds else AABB(position, Vector3.ZERO)
	_has_bounds = true
	_bounds_dirty = true
	_oldest_birth = minf(_oldest_birth, _elapsed)
	var chunk_index := slot / VISIBLE_CHUNK_SIZE
	_chunk_bounds[chunk_index] = _chunk_bounds[chunk_index].expand(position) if _chunk_has_bounds[chunk_index] else AABB(position, Vector3.ZERO)
	_chunk_has_bounds[chunk_index] = true
	_chunk_oldest_birth[chunk_index] = minf(_chunk_oldest_birth[chunk_index], _elapsed)
	_size_variations[slot] = variation.size_ratio
	_opacity_variations[slot] = variation.opacity_ratio
	_drift_vectors[slot] = variation.drift_direction
	_serials[slot] = _emission_serial
	var chunk_mesh := _visible_chunks[chunk_index].multimesh
	chunk_mesh.visible_instance_count = maxi(chunk_mesh.visible_instance_count, slot % VISIBLE_CHUNK_SIZE + 1)
	_update_puff(slot)

func _update_puffs() -> void:
	var retired := false
	for active_index: int in range(_active_slots.size() - 1, -1, -1):
		var slot := _active_slots[active_index]
		# Both visible and shadow shaders are exactly transparent at this age.
		if _elapsed - _birth_times[slot] >= lifetime * FADE_END_RATIO:
			_hide_puff_slot(slot)
			_occupied_slots[slot] = 0
			_active_slots[active_index] = _active_slots.back()
			_active_slots.pop_back()
			retired = true
			continue
	if retired:
		# Only trim unused tails; moving live slots would reorder alpha blending.
		for chunk_index: int in _visible_chunks.size():
			var chunk_mesh := _visible_chunks[chunk_index].multimesh
			while chunk_mesh.visible_instance_count > 0 and _occupied_slots[chunk_index * VISIBLE_CHUNK_SIZE + chunk_mesh.visible_instance_count - 1] == 0:
				chunk_mesh.visible_instance_count -= 1
		while shadow_particles.multimesh.visible_instance_count > 0 and _shadow_owner_serials[shadow_particles.multimesh.visible_instance_count - 1] < 0:
			shadow_particles.multimesh.visible_instance_count -= 1
		_rebuild_bounds()

func _rebuild_bounds() -> void:
	_needs_bounds_rebuild = false
	_has_bounds = false
	_oldest_birth = INF
	for chunk_index: int in _visible_chunks.size():
		_chunk_has_bounds[chunk_index] = false
		_chunk_oldest_birth[chunk_index] = INF
	for slot: int in _active_slots:
		var position := _positions[slot]
		_bounds = _bounds.expand(position) if _has_bounds else AABB(position, Vector3.ZERO)
		_has_bounds = true
		_oldest_birth = minf(_oldest_birth, _birth_times[slot])
		var chunk_index := slot / VISIBLE_CHUNK_SIZE
		_chunk_bounds[chunk_index] = _chunk_bounds[chunk_index].expand(position) if _chunk_has_bounds[chunk_index] else AABB(position, Vector3.ZERO)
		_chunk_has_bounds[chunk_index] = true
		_chunk_oldest_birth[chunk_index] = minf(_chunk_oldest_birth[chunk_index], _birth_times[slot])
	_bounds_dirty = _has_bounds

func _refresh_culling_bounds() -> void:
	for chunk_index: int in _visible_chunks.size():
		if _chunk_has_bounds[chunk_index]:
			var age_horizon := minf(lifetime, _elapsed - _chunk_oldest_birth[chunk_index] + BOUND_REFRESH_INTERVAL + 0.1)
			_visible_chunks[chunk_index].multimesh.custom_aabb = _chunk_bounds[chunk_index].grow(_culling_margin(age_horizon))
	if _has_bounds:
		var shadow_horizon := minf(lifetime, _elapsed - _oldest_birth + BOUND_REFRESH_INTERVAL + 0.1)
		shadow_particles.multimesh.custom_aabb = _bounds.grow(_culling_margin(shadow_horizon))
	_bounds_dirty = false

func _culling_margin(age_horizon: float) -> float:
	var t := clampf(age_horizon / lifetime, 0.0, 1.0)
	var scale_limit := maxf(initial_scale, lerpf(initial_scale, final_scale, smoothstep(0.0, 1.0, t)))
	var turbulence_extent := turbulence_strength * 3.6 * (sqrt(1.0 + age_horizon * 0.5) - 1.0)
	return puff_mesh.size.length() * scale_limit * 1.3 + age_horizon * drift_speed * 2.0 + turbulence_extent

func _update_puff(slot: int) -> void:
	# Upload a birth record once. Both passes animate from the same GPU data.
	var transform := Transform3D(Basis.IDENTITY, _positions[slot])
	var drift := _drift_vectors[slot] * 0.25 + Vector3.ONE * 0.5
	var color := Color(drift.x, drift.y, drift.z, 1.0)
	var data := Color(_birth_times[slot], _size_variations[slot], _opacity_variations[slot], 0.0)
	var chunk_mesh := _visible_chunks[slot / VISIBLE_CHUNK_SIZE].multimesh
	var local_slot := slot % VISIBLE_CHUNK_SIZE
	chunk_mesh.set_instance_transform(local_slot, transform)
	chunk_mesh.set_instance_color(local_slot, color)
	chunk_mesh.set_instance_custom_data(local_slot, data)
	if shadow_particles == null or not SmokePuffDistribution.casts_shadow(_serials[slot], shadow_emission_stride):
		return
	var shadow_slot := _shadow_slot_for_serial(_serials[slot])
	_shadow_owner_serials[shadow_slot] = _serials[slot]
	shadow_particles.multimesh.visible_instance_count = maxi(shadow_particles.multimesh.visible_instance_count, shadow_slot + 1)
	shadow_particles.multimesh.set_instance_transform(shadow_slot, transform)
	shadow_particles.multimesh.set_instance_color(shadow_slot, color)
	shadow_particles.multimesh.set_instance_custom_data(shadow_slot, data)

func _set_opacity_ratio(ratio: float) -> void:
	current_opacity_ratio = clampf(ratio, 0.0, 1.0)
	current_shadow_opacity_ratio = current_opacity_ratio
	if smoke_material != null:
		smoke_material.set_shader_parameter("opacity_ratio", current_opacity_ratio)
	if shadow_material != null:
		shadow_material.set_shader_parameter("opacity_ratio", current_shadow_opacity_ratio)

func _hide_puff_slot(slot: int) -> void:
	_hide_instance(_visible_chunks[slot / VISIBLE_CHUNK_SIZE].multimesh, slot % VISIBLE_CHUNK_SIZE)
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
	# Billboard shaders reconstruct the basis; invalidate their birth data too.
	target.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
