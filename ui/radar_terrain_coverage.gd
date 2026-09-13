class_name RadarTerrainCoverage
extends Node

const ANTENNA_HEIGHT := 11.0
const SURFACE_CLEARANCE := TerrainLineOfSight.TERRAIN_CLEARANCE + 0.1
const DEFAULT_WORK_BUDGET_USEC := 1000
const DEFAULT_MAXIMUM_CELLS_PER_FRAME := 512

var battlefield: Battlefield
var work_budget_usec: int = DEFAULT_WORK_BUDGET_USEC
var maximum_cells_per_frame: int = DEFAULT_MAXIMUM_CELLS_PER_FRAME
var coverage_texture: ImageTexture
var _sources: Array[Dictionary] = []
var _requested_signature: String = ""
var _cache: Dictionary[String, Dictionary] = {}
var _jobs: Array[Dictionary] = []
var _composite_pixels := PackedByteArray()

func configure(field: Battlefield) -> void:
	battlefield = field
	_rebuild_texture()
	set_process(false)

func set_sources(sources: Array[Dictionary]) -> void:
	var requested_signature := _sources_signature(sources)
	if requested_signature == _requested_signature:
		return
	_requested_signature = requested_signature
	_sources = sources.duplicate(true)
	_jobs.clear()
	for source: Dictionary in _sources:
		var key := String(source.get("key", ""))
		var signature := _source_signature(source)
		var cached: Dictionary = _cache.get(key, {})
		if String(cached.get("signature", "")) == signature:
			continue
		_cache.erase(key)
		_jobs.append(_create_job(source, signature))
	_rebuild_texture()
	set_process(not _jobs.is_empty())

func requested_source_count() -> int:
	return _sources.size()

func completed_source_count() -> int:
	var count := 0
	for source: Dictionary in _sources:
		var key := String(source.get("key", ""))
		var cached: Dictionary = _cache.get(key, {})
		if String(cached.get("signature", "")) == _source_signature(source):
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
		processed += _advance_job(job, mini(64, maximum_cells_per_frame - processed))
		if bool(job.get("complete", false)):
			_complete_job(job)
			_jobs.pop_front()
		if processed > 0 and Time.get_ticks_usec() - started >= work_budget_usec:
			break
	set_process(not _jobs.is_empty())

func _create_job(source: Dictionary, signature: String) -> Dictionary:
	var resolution := battlefield.generator.resolution
	var size := battlefield.generator.size
	var half := size * 0.5
	var step := size / float(resolution - 1)
	var position: Vector3 = source.position
	var radius := float(source.radius)
	var minimum_x := clampi(floori((position.x - radius + half) / step), 0, resolution - 1)
	var maximum_x := clampi(ceili((position.x + radius + half) / step), 0, resolution - 1)
	var minimum_z := clampi(floori((position.z - radius + half) / step), 0, resolution - 1)
	var maximum_z := clampi(ceili((position.z + radius + half) / step), 0, resolution - 1)
	var mask := PackedByteArray()
	mask.resize(resolution * resolution)
	mask.fill(0)
	return {
		"key": String(source.key),
		"signature": signature,
		"position": position,
		"radius_squared": radius * radius,
		"color": source.color as Color,
		"minimum_x": minimum_x,
		"maximum_x": maximum_x,
		"maximum_z": maximum_z,
		"x": minimum_x,
		"z": minimum_z,
		"mask": mask,
		"complete": false,
	}

func _advance_job(job: Dictionary, cell_limit: int) -> int:
	var resolution := battlefield.generator.resolution
	var size := battlefield.generator.size
	var step := size / float(resolution - 1)
	var half := size * 0.5
	var origin: Vector3 = (job.position as Vector3) + Vector3.UP * ANTENNA_HEIGHT
	var mask: PackedByteArray = job.mask
	var processed := 0
	while processed < cell_limit and not bool(job.complete):
		var x := int(job.x)
		var z := int(job.z)
		var world_x := -half + float(x) * step
		var world_z := -half + float(z) * step
		var flat_offset := Vector2(world_x - origin.x, world_z - origin.z)
		if flat_offset.length_squared() <= float(job.radius_squared):
			var target := Vector3(world_x, battlefield.terrain_height(world_x, world_z) + SURFACE_CLEARANCE, world_z)
			if TerrainLineOfSight.is_clear(battlefield, origin, target):
				mask[z * resolution + x] = 255
		x += 1
		if x > int(job.maximum_x):
			x = int(job.minimum_x)
			z += 1
		job.x = x
		job.z = z
		job.complete = z > int(job.maximum_z)
		processed += 1
	job.mask = mask
	return processed

func _complete_job(job: Dictionary) -> void:
	var key := String(job.key)
	var desired := _source_for_key(key)
	if desired.is_empty() or _source_signature(desired) != String(job.signature):
		return
	_cache[key] = {
		"signature": String(job.signature),
		"mask": job.mask as PackedByteArray,
		"color": job.color as Color,
	}
	_rebuild_texture()

func _source_for_key(key: String) -> Dictionary:
	for source: Dictionary in _sources:
		if String(source.get("key", "")) == key:
			return source
	return {}

func _rebuild_texture() -> void:
	if battlefield == null or battlefield.generator.resolution < 2:
		return
	var resolution := battlefield.generator.resolution
	_composite_pixels.resize(resolution * resolution * 4)
	_composite_pixels.fill(0)
	for source: Dictionary in _sources:
		var cached: Dictionary = _cache.get(String(source.get("key", "")), {})
		if String(cached.get("signature", "")) != _source_signature(source):
			continue
		_blend_mask(cached.mask as PackedByteArray, cached.color as Color)
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

func _sources_signature(sources: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for source: Dictionary in sources:
		parts.append(_source_signature(source))
	return "\n".join(parts)

func _source_signature(source: Dictionary) -> String:
	var position: Vector3 = source.position
	var color: Color = source.color
	return "%s|%.2f|%.2f|%.2f|%.2f|%s" % [String(source.key), position.x, position.y, position.z, float(source.radius), color.to_html()]
