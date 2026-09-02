class_name LingeringSmokeTrail
extends GPUParticles3D

@export_range(0.5, 20.0, 0.5) var sample_spacing: float = 3.0
@export_range(1, 4, 1) var particles_per_sample: int = 1
@export_range(0.0, 2.0, 0.05) var sample_radius: float = 0.0
@export_range(1.0, 40.0, 0.5) var release_fade_duration: float = 16.0
@export_range(0.1, 2.0, 0.1) var transparent_cleanup_delay: float = 0.5

var release_remaining: float = -1.0
var release_elapsed: float = 0.0
var sample_remainder: float = 0.0
var sampled_path_length: float = 0.0
var emitted_sample_count: int = 0
var last_emitted_world_position: Vector3
var current_opacity_ratio: float = 1.0
var smoke_material: StandardMaterial3D
var initial_material_alpha: float = 1.0

func _ready() -> void:
	_make_draw_material_unique()
	set_process(false)

func release_to(new_parent: Node) -> void:
	if new_parent == null or not is_instance_valid(new_parent):
		queue_free()
		return
	reparent(new_parent, true)
	emitting = false
	release_elapsed = 0.0
	release_remaining = release_fade_duration + transparent_cleanup_delay
	_set_opacity_ratio(1.0)
	set_process(true)

func sample_world_segment(from_position: Vector3, to_position: Vector3) -> void:
	var segment := to_position - from_position
	var distance := segment.length()
	if distance <= 0.001:
		return
	sampled_path_length += distance
	var visibility_extent := maxf(120.0, sampled_path_length + 120.0)
	visibility_aabb = AABB(Vector3.ONE * -visibility_extent, Vector3.ONE * visibility_extent * 2.0)
	var direction := segment / distance
	var cursor := sample_spacing - sample_remainder
	while cursor <= distance:
		var world_position := from_position + direction * cursor
		for particle_index: int in particles_per_sample:
			var phase := float(emitted_sample_count + particle_index) * 2.399963
			var offset := Vector3(cos(phase), sin(phase * 0.73) * 0.55, sin(phase)) * sample_radius
			emit_particle(Transform3D(Basis.IDENTITY, world_position + offset), Vector3.ZERO, Color.WHITE, Color.WHITE, EMIT_FLAG_POSITION)
			emitted_sample_count += 1
		last_emitted_world_position = world_position
		cursor += sample_spacing
	sample_remainder = fposmod(sample_remainder + distance, sample_spacing)

func _process(delta: float) -> void:
	release_elapsed += delta
	release_remaining -= delta
	var fade_progress := clampf(release_elapsed / release_fade_duration, 0.0, 1.0)
	_set_opacity_ratio(1.0 - smoothstep(0.0, 1.0, fade_progress))
	if release_remaining <= 0.0:
		queue_free()

func _make_draw_material_unique() -> void:
	var source_mesh := draw_pass_1
	if source_mesh == null or source_mesh.get_surface_count() == 0:
		return
	var unique_mesh := source_mesh.duplicate() as Mesh
	var source_material := unique_mesh.surface_get_material(0)
	if source_material is not StandardMaterial3D:
		return
	smoke_material = (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
	unique_mesh.surface_set_material(0, smoke_material)
	draw_pass_1 = unique_mesh
	initial_material_alpha = smoke_material.albedo_color.a

func _set_opacity_ratio(ratio: float) -> void:
	current_opacity_ratio = clampf(ratio, 0.0, 1.0)
	if smoke_material == null:
		return
	var color := smoke_material.albedo_color
	color.a = initial_material_alpha * current_opacity_ratio
	smoke_material.albedo_color = color
