class_name RadarTerrainCoverage
extends Node

class CoverageResult extends RefCounted:
	var source: RadarCoverageSource
	var mask: PackedByteArray

	func _init(source_value: RadarCoverageSource, mask_value: PackedByteArray) -> void:
		source = source_value
		mask = mask_value

class CoverageJob extends RefCounted:
	var source: RadarCoverageSource
	var mask: PackedByteArray
	var minimum_x: int
	var maximum_x: int
	var maximum_z: int
	var x: int
	var z: int
	var complete: bool = false

const ANTENNA_HEIGHT := 11.0
const SURFACE_CLEARANCE := RadarLineOfSight.TERRAIN_CLEARANCE + 0.1
const DEFAULT_WORK_BUDGET_USEC := 1000
const DEFAULT_MAXIMUM_CELLS_PER_FRAME := 512
const WORK_BATCH_SIZE := 64

var battlefield: Battlefield
var work_budget_usec: int = DEFAULT_WORK_BUDGET_USEC
var maximum_cells_per_frame: int = DEFAULT_MAXIMUM_CELLS_PER_FRAME
var coverage_texture: ImageTexture
var _sources: Array[RadarCoverageSource] = []
var _cache: Dictionary[String, CoverageResult] = {}
var _jobs: Array[CoverageJob] = []
var _composite_pixels := PackedByteArray()
var _terrain_revision: int = -1

func configure(field: Battlefield) -> void:
	battlefield = field
	_terrain_revision = field.terrain_revision
	_rebuild_texture()
	set_process(false)

func _exit_tree() -> void:
	if is_instance_valid(battlefield):
		battlefield.set_radar_coverage(coverage_texture, false)

func set_sources(sources: Array[RadarCoverageSource]) -> void:
	_invalidate_changed_terrain()
	if _sources_match(sources):
		return
	_sources = sources.duplicate()
	_jobs.clear()
	for source: RadarCoverageSource in _sources:
		var cached: CoverageResult = _cache.get(source.key)
		if cached != null and cached.source.matches(source):
			continue
		_cache.erase(source.key)
		_jobs.append(_create_job(source))
	_rebuild_texture()
	set_process(not _jobs.is_empty())

func _invalidate_changed_terrain() -> void:
	if battlefield.terrain_revision == _terrain_revision:
		return
	_terrain_revision = battlefield.terrain_revision
	_sources.clear()
	_cache.clear()
	_jobs.clear()

func requested_source_count() -> int:
	return _sources.size()

func completed_source_count() -> int:
	var count := 0
	for source: RadarCoverageSource in _sources:
		var cached: CoverageResult = _cache.get(source.key)
		if cached != null and cached.source.matches(source):
			count += 1
	return count

func is_calculating() -> bool:
	return not _jobs.is_empty()

func coverage_color_at(world_position: Vector2) -> Color:
	if battlefield == null or _composite_pixels.is_empty():
		return Color.TRANSPARENT
	var resolution := battlefield.generator.resolution
	var half := battlefield.generator.size * 0.5
	var x := clampi(roundi((world_position.x + half) / battlefield.generator.size * float(resolution - 1)), 0, resolution - 1)
	var z := clampi(roundi((world_position.y + half) / battlefield.generator.size * float(resolution - 1)), 0, resolution - 1)
	var offset := (z * resolution + x) * 4
	return Color8(_composite_pixels[offset], _composite_pixels[offset + 1], _composite_pixels[offset + 2], _composite_pixels[offset + 3])

func _process(_delta: float) -> void:
	if _jobs.is_empty() or battlefield == null:
		set_process(false)
		return
	var started := Time.get_ticks_usec()
	var processed := 0
	while not _jobs.is_empty() and processed < maximum_cells_per_frame:
		var job := _jobs[0]
		processed += _advance_job(job, mini(WORK_BATCH_SIZE, maximum_cells_per_frame - processed))
		if job.complete:
			_complete_job(job)
			_jobs.pop_front()
		if processed > 0 and Time.get_ticks_usec() - started >= work_budget_usec:
			break
	set_process(not _jobs.is_empty())

func _create_job(source: RadarCoverageSource) -> CoverageJob:
	var resolution := battlefield.generator.resolution
	var size := battlefield.generator.size
	var half := size * 0.5
	var step := size / float(resolution - 1)
	var job := CoverageJob.new()
	job.source = source
	job.minimum_x = clampi(floori((source.position.x - source.radius + half) / step), 0, resolution - 1)
	job.maximum_x = clampi(ceili((source.position.x + source.radius + half) / step), 0, resolution - 1)
	job.x = job.minimum_x
	job.z = clampi(floori((source.position.z - source.radius + half) / step), 0, resolution - 1)
	job.maximum_z = clampi(ceili((source.position.z + source.radius + half) / step), 0, resolution - 1)
	job.mask.resize(resolution * resolution)
	job.mask.fill(0)
	return job

func _advance_job(job: CoverageJob, cell_limit: int) -> int:
	var resolution := battlefield.generator.resolution
	var size := battlefield.generator.size
	var step := size / float(resolution - 1)
	var half := size * 0.5
	var origin := job.source.position + Vector3.UP * ANTENNA_HEIGHT
	var radius_squared := job.source.radius * job.source.radius
	var processed := 0
	while processed < cell_limit and not job.complete:
		var world_x := -half + float(job.x) * step
		var world_z := -half + float(job.z) * step
		var flat_offset := Vector2(world_x - origin.x, world_z - origin.z)
		if flat_offset.length_squared() <= radius_squared:
			var target := Vector3(world_x, battlefield.terrain_height(world_x, world_z) + SURFACE_CLEARANCE, world_z)
			if RadarLineOfSight.is_clear(battlefield, origin, target):
				job.mask[job.z * resolution + job.x] = 255
		job.x += 1
		if job.x > job.maximum_x:
			job.x = job.minimum_x
			job.z += 1
		job.complete = job.z > job.maximum_z
		processed += 1
	return processed

func _complete_job(job: CoverageJob) -> void:
	var desired := _source_for_key(job.source.key)
	if not job.source.matches(desired):
		return
	_cache[job.source.key] = CoverageResult.new(job.source, job.mask)
	_rebuild_texture()

func _source_for_key(key: String) -> RadarCoverageSource:
	for source: RadarCoverageSource in _sources:
		if source.key == key:
			return source
	return null

func _rebuild_texture() -> void:
	if battlefield == null or battlefield.generator.resolution < 2:
		return
	var resolution := battlefield.generator.resolution
	_composite_pixels.resize(resolution * resolution * 4)
	_composite_pixels.fill(0)
	for source: RadarCoverageSource in _sources:
		var cached: CoverageResult = _cache.get(source.key)
		if cached != null and cached.source.matches(source):
			_blend_mask(cached.mask, cached.source.color)
	var image := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGBA8, _composite_pixels)
	if coverage_texture == null:
		coverage_texture = ImageTexture.create_from_image(image)
	else:
		coverage_texture.update(image)
	battlefield.set_radar_coverage(coverage_texture, not _sources.is_empty())

func _blend_mask(mask: PackedByteArray, color: Color) -> void:
	var red := roundi(clampf(color.r, 0.0, 1.0) * 255.0)
	var green := roundi(clampf(color.g, 0.0, 1.0) * 255.0)
	var blue := roundi(clampf(color.b, 0.0, 1.0) * 255.0)
	var alpha := roundi(clampf(color.a, 0.0, 1.0) * 255.0)
	for index: int in mask.size():
		if mask[index] == 0:
			continue
		var offset := index * 4
		if _composite_pixels[offset + 3] == 0:
			_composite_pixels[offset] = red
			_composite_pixels[offset + 1] = green
			_composite_pixels[offset + 2] = blue
			_composite_pixels[offset + 3] = alpha
		elif _composite_pixels[offset] != red or _composite_pixels[offset + 1] != green or _composite_pixels[offset + 2] != blue:
			_composite_pixels[offset] = (_composite_pixels[offset] + red) / 2
			_composite_pixels[offset + 1] = (_composite_pixels[offset + 1] + green) / 2
			_composite_pixels[offset + 2] = (_composite_pixels[offset + 2] + blue) / 2
			_composite_pixels[offset + 3] = maxi(_composite_pixels[offset + 3], alpha)

func _sources_match(sources: Array[RadarCoverageSource]) -> bool:
	if _sources.size() != sources.size():
		return false
	for index: int in sources.size():
		if not _sources[index].matches(sources[index]):
			return false
	return true
