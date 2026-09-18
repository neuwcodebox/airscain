class_name WorldGenerator
extends RefCounted

const CITY_GROUND_HEIGHT := 10.0
const CITY_PRESENTATION_SCALE := 0.9
const CENTRAL_DISTRICT_ID := &"central"
const DISTRICT_SITE_CANDIDATES := 32

var size: float
var resolution: int
var city_size: float
var seed_value: int
var heights: PackedFloat32Array
var sea_level: float = 0.0
var layout: BattlefieldLayoutDefinition
var terrain_rotation_degrees: float = 0.0
var _city_blocks: Array[Dictionary] = []
var _city_buildings: Array[Transform3D] = []
var _city_districts: Array[CityDistrict] = []
var _coast_phase_a: float = 0.0
var _coast_phase_b: float = 0.0

func generate(seed_input: int, size_input: float, resolution_input: int, city_size_input: float, layout_value: BattlefieldLayoutDefinition = null) -> void:
	seed_value = seed_input
	size = size_input
	resolution = resolution_input
	city_size = city_size_input
	layout = layout_value if layout_value != null else BattlefieldLayoutDefinition.new()
	_city_blocks.clear()
	_city_buildings.clear()
	_city_districts.clear()
	heights = PackedFloat32Array()
	heights.resize(resolution * resolution)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = layout.noise_frequency
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.48
	var coast_noise := FastNoiseLite.new()
	coast_noise.seed = seed_value ^ 0x6389
	coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast_noise.frequency = 0.0014
	coast_noise.fractal_octaves = 3
	_coast_phase_a = float(posmod(seed_value * 3, 997)) / 997.0 * TAU
	_coast_phase_b = float(posmod(seed_value * 11, 991)) / 991.0 * TAU
	var terrain_rng := RandomNumberGenerator.new()
	terrain_rng.seed = seed_value ^ 0x7A31B9
	terrain_rotation_degrees = layout.terrain_rotation_degrees + terrain_rng.randf_range(-12.0, 12.0)
	var district_definitions := _resolve_district_definitions(_district_definitions(), coast_noise)
	for z_index: int in resolution:
		for x_index: int in resolution:
			var x := _grid_world(x_index)
			var z := _grid_world(z_index)
			var raw := noise.get_noise_2d(x, z) * layout.terrain_height_scale
			var terrain_local := Vector2(x, z).rotated(-deg_to_rad(terrain_rotation_degrees))
			var flatten := _broad_terrain_weight(Vector2(x, z), district_definitions)
			var macro_height := _macro_terrain_height(terrain_local)
			var land_height := maxf((raw + macro_height) * flatten + CITY_GROUND_HEIGHT, sea_level + 6.0)
			var coast_falloff := _coast_falloff(terrain_local, coast_noise)
			heights[z_index * resolution + x_index] = lerpf(land_height, sea_level - 35.0, coast_falloff)
	for district_index: int in district_definitions.size():
		var blocks := _create_city_block_layout(district_definitions[district_index], district_index)
		_city_blocks.append_array(blocks)
	_flatten_city_footprint()
	_refresh_city_block_heights()
	for district_index: int in district_definitions.size():
		var blocks: Array[Dictionary] = []
		for block: Dictionary in _city_blocks:
			if int(block.district_index) == district_index:
				blocks.append(block)
		var buildings := _create_building_transforms(district_definitions[district_index], blocks, district_index)
		_city_buildings.append_array(buildings)
		_city_districts.append(CityDistrict.new(district_definitions[district_index], blocks, buildings))

func height_at(x: float, z: float) -> float:
	var half := size * 0.5
	var gx := clampf((x + half) / size * float(resolution - 1), 0.0, float(resolution - 1))
	var gz := clampf((z + half) / size * float(resolution - 1), 0.0, float(resolution - 1))
	var x0 := int(gx)
	var z0 := int(gz)
	var x1 := mini(x0 + 1, resolution - 1)
	var z1 := mini(z0 + 1, resolution - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var row0 := z0 * resolution
	var row1 := z1 * resolution
	var a := lerpf(heights[row0 + x0], heights[row0 + x1], tx)
	var b := lerpf(heights[row1 + x0], heights[row1 + x1], tx)
	return lerpf(a, b, tz)

func slope_degrees_at(x: float, z: float, radius: float) -> float:
	var h_left := height_at(x - radius, z)
	var h_right := height_at(x + radius, z)
	var h_back := height_at(x, z - radius)
	var h_front := height_at(x, z + radius)
	var gradient := Vector2((h_right - h_left) / (radius * 2.0), (h_front - h_back) / (radius * 2.0))
	return rad_to_deg(atan(gradient.length()))

func create_terrain_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z_index: int in resolution - 1:
		for x_index: int in resolution - 1:
			var a := _vertex(x_index, z_index)
			var b := _vertex(x_index + 1, z_index)
			var c := _vertex(x_index, z_index + 1)
			var d := _vertex(x_index + 1, z_index + 1)
			_add_triangle(surface, a, b, c)
			_add_triangle(surface, b, d, c)
	surface.generate_normals()
	return surface.commit()

func building_transforms() -> Array[Transform3D]:
	return _city_buildings.duplicate()

func city_districts() -> Array[CityDistrict]:
	var result: Array[CityDistrict] = []
	result.assign(_city_districts)
	return result

func primary_city_center() -> Vector2:
	for district: CityDistrict in _city_districts:
		if district.definition.role == CityDistrictDefinition.Role.CORE:
			return district.center
	return _city_districts[0].center if not _city_districts.is_empty() else Vector2.ZERO

func _create_building_transforms(district: CityDistrictDefinition, blocks: Array[Dictionary], district_index: int) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value ^ 0x51A7) if district_index == 0 else (seed_value ^ 0x51A7 ^ district_index * 0x1F123BB5)
	var block_step := district.size / float(district.block_count)
	var rotation := deg_to_rad(district.rotation_degrees)
	var district_basis := Basis(Vector3.UP, rotation)
	for block: Dictionary in blocks:
		var grid: Vector2i = block.grid
		var block_center: Vector3 = block.position
		var distance: float = block.normalized_distance
		if grid == Vector2i.ZERO or rng.randf() < lerpf(0.04, 0.16, distance):
			continue
		var center_weight := 1.0 - smoothstep(0.12, 1.0, distance)
		var building_count := 1 if distance < 0.52 else (2 if rng.randf() < 0.78 else 1)
		for building_index: int in building_count:
			var split_along_x := (grid.x + grid.y) % 2 == 0
			var offset := 0.0 if building_count == 1 else (-1.0 if building_index == 0 else 1.0) * block_step * 0.19
			var local_offset := Vector3(offset if split_along_x else rng.randf_range(-2.2, 2.2), 0.0, rng.randf_range(-2.2, 2.2) if split_along_x else offset)
			var world_offset := district_basis * local_offset
			var x := block_center.x + world_offset.x
			var z := block_center.z + world_offset.z
			var width_limit := block_step * (0.30 if building_count == 2 and split_along_x else 0.60)
			var depth_limit := block_step * (0.30 if building_count == 2 and not split_along_x else 0.60)
			var width := rng.randf_range(width_limit * 0.78, width_limit)
			var depth := rng.randf_range(depth_limit * 0.78, depth_limit)
			var zone_height_scale := lerpf(0.32, 1.18, center_weight)
			var height := clampf(rng.randf_range(district.minimum_building_height, district.maximum_building_height) * zone_height_scale, district.minimum_building_height, district.maximum_building_height * 1.08) * CITY_PRESENTATION_SCALE
			var basis := district_basis * Basis.from_scale(Vector3(width, height, depth))
			result.append(Transform3D(basis, Vector3(x, height * 0.5 + height_at(x, z), z)))
	return result

func city_block_layout() -> Array[Dictionary]:
	return _city_blocks.duplicate(true)

func _create_city_block_layout(district: CityDistrictDefinition, district_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var block_count := district.block_count
	var block_step := district.size / float(block_count)
	var center := float(block_count - 1) * 0.5
	var phase_a := float(posmod(seed_value, 997)) / 997.0 * TAU
	var phase_b := float(posmod(seed_value * 7, 991)) / 991.0 * TAU
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value ^ 0x2D71) if district_index == 0 else (seed_value ^ 0x2D71 ^ district_index * 0x45D9F3B)
	var rotation := deg_to_rad(district.rotation_degrees)
	var district_basis := Basis(Vector3.UP, rotation)
	for bz: int in block_count:
		for bx: int in block_count:
			var grid := Vector2i(bx - int(center), bz - int(center))
			var grid_position := Vector2(float(grid.x), float(grid.y))
			var normalized_distance := grid_position.length() / maxf(center, 1.0)
			var angle := atan2(grid_position.y, grid_position.x)
			var boundary := 0.83 + sin(angle * 3.0 + phase_a) * 0.12 + sin(angle * 5.0 + phase_b) * 0.07 + rng.randf_range(-0.06, 0.06)
			var local_position := Vector3(float(grid.x) * block_step, 0.0, float(grid.y) * block_step)
			var rotated_position := district_basis * local_position
			var x := district.center.x + rotated_position.x
			var z := district.center.y + rotated_position.z
			var central_core := normalized_distance <= 0.34
			var terrain_suitable := height_at(x, z) > sea_level + 3.0 and slope_degrees_at(x, z, block_step * 0.32) <= 11.0
			if normalized_distance <= boundary and (central_core or terrain_suitable):
				result.append({
					"grid": grid,
					"district_id": district.id,
					"district_index": district_index,
					"position": Vector3(x, height_at(x, z), z),
					"normalized_distance": normalized_distance,
					"block_step": block_step,
					"rotation": rotation,
				})
	return result

func _flatten_city_footprint() -> void:
	var terrain_step := size / float(resolution - 1)
	for z_index: int in resolution:
		for x_index: int in resolution:
			var x := _grid_world(x_index)
			var z := _grid_world(z_index)
			var flatten_weight := 0.0
			for block: Dictionary in _city_blocks:
				var position: Vector3 = block.position
				var block_step: float = block.block_step
				var block_half_extent := block_step * 0.54 + terrain_step * 0.75
				var feather_distance := block_step * 0.72
				var local := Vector2(x - position.x, z - position.z).rotated(-float(block.rotation))
				var outside_x := maxf(absf(local.x) - block_half_extent, 0.0)
				var outside_z := maxf(absf(local.y) - block_half_extent, 0.0)
				var distance := Vector2(outside_x, outside_z).length()
				flatten_weight = maxf(flatten_weight, 1.0 - smoothstep(0.0, feather_distance, distance))
				if is_equal_approx(flatten_weight, 1.0):
					break
			var height_index := z_index * resolution + x_index
			heights[height_index] = lerpf(heights[height_index], CITY_GROUND_HEIGHT, flatten_weight)

func _refresh_city_block_heights() -> void:
	for index: int in _city_blocks.size():
		var block: Dictionary = _city_blocks[index]
		var position: Vector3 = block.position
		position.y = height_at(position.x, position.z)
		block.position = position
		_city_blocks[index] = block

func _district_definitions() -> Array[CityDistrictDefinition]:
	if not layout.city_districts.is_empty():
		return layout.city_districts
	var central := CityDistrictDefinition.new()
	central.id = CENTRAL_DISTRICT_ID
	central.size = city_size
	central.block_count = layout.city_blocks
	central.minimum_building_height = layout.minimum_building_height
	central.maximum_building_height = layout.maximum_building_height
	var result: Array[CityDistrictDefinition] = [central]
	return result

func _resolve_district_definitions(authored: Array[CityDistrictDefinition], coast_noise: FastNoiseLite) -> Array[CityDistrictDefinition]:
	var result: Array[CityDistrictDefinition] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x36D4A7
	var rotation_delta := deg_to_rad(terrain_rotation_degrees - layout.terrain_rotation_degrees)
	var shared_offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(35.0, 105.0)
	for district_index: int in authored.size():
		var source := authored[district_index]
		var district := source.duplicate(true) as CityDistrictDefinition
		district.size *= rng.randf_range(0.96, 1.14)
		district.rotation_degrees = wrapf(source.rotation_degrees + rad_to_deg(rotation_delta) + rng.randf_range(-16.0, 16.0), -180.0, 180.0)
		var anchor := source.center.rotated(rotation_delta) + shared_offset
		var jitter_radius := clampf(district.size * 0.38, 90.0, 180.0)
		var best_center := anchor
		var best_score := -INF
		for candidate_index: int in DISTRICT_SITE_CANDIDATES:
			var offset := Vector2.ZERO
			if candidate_index > 0:
				offset = Vector2.from_angle(rng.randf_range(0.0, TAU)) * sqrt(rng.randf()) * jitter_radius
			var candidate := anchor + offset
			var score := _district_site_score(candidate, district.size, coast_noise, result)
			if score > best_score:
				best_score = score
				best_center = candidate
		district.center = best_center
		result.append(district)
	return result

func _district_site_score(center: Vector2, district_size: float, coast_noise: FastNoiseLite, accepted: Array[CityDistrictDefinition]) -> float:
	var local_center := center.rotated(-deg_to_rad(terrain_rotation_degrees))
	var sample_radius := district_size * 0.42
	var worst_water := _coast_falloff(local_center, coast_noise)
	for direction_index: int in 8:
		var offset := Vector2.from_angle(TAU * float(direction_index) / 8.0) * sample_radius
		var local_sample := (center + offset).rotated(-deg_to_rad(terrain_rotation_degrees))
		worst_water = maxf(worst_water, _coast_falloff(local_sample, coast_noise))
	var score := (1.0 - worst_water) * 12.0
	for other: CityDistrictDefinition in accepted:
		var preferred_separation := (district_size + other.size) * 0.56
		var separation := center.distance_to(other.center)
		if separation < preferred_separation:
			score -= (preferred_separation - separation) / preferred_separation * 8.0
	return score

func _broad_terrain_weight(position: Vector2, districts: Array[CityDistrictDefinition]) -> float:
	var weight := 1.0
	for district: CityDistrictDefinition in districts:
		var distance := position.distance_to(district.center)
		weight = minf(weight, smoothstep(district.size * 0.27, district.size * 0.62, distance))
	return weight

func _macro_terrain_height(local: Vector2) -> float:
	var half := size * 0.5
	match layout.terrain_shape:
		BattlefieldLayoutDefinition.TerrainShape.VALLEY:
			var wall := pow(clampf(absf(local.x) / half, 0.0, 1.0), 1.7)
			return wall * layout.terrain_height_scale * 1.45
		BattlefieldLayoutDefinition.TerrainShape.BAY:
			return smoothstep(0.2, 0.9, absf(local.y) / half) * layout.terrain_height_scale * 0.28
		BattlefieldLayoutDefinition.TerrainShape.COASTAL_PLAIN:
			return smoothstep(-0.2, 0.9, -local.x / half) * layout.terrain_height_scale * 0.18
	return 0.0

func _coast_falloff(local: Vector2, coast_noise: FastNoiseLite) -> float:
	var half := size * 0.5
	var radial_distance := local.length() / half
	var coast_angle := atan2(local.y, local.x)
	var radius_scale := 0.91 + sin(coast_angle * 3.0 + _coast_phase_a) * 0.075 + sin(coast_angle * 5.0 + _coast_phase_b) * 0.045 + coast_noise.get_noise_2d(local.x, local.y) * 0.055
	radius_scale = clampf(radius_scale, 0.76, 1.0)
	var shaped_radial_distance := radial_distance / radius_scale
	var edge_falloff := smoothstep(0.88, 0.985, shaped_radial_distance)
	match layout.terrain_shape:
		BattlefieldLayoutDefinition.TerrainShape.BAY:
			var ellipse := Vector2(local.x / 1.08, local.y / 0.86).length() / half
			var outer := smoothstep(layout.coast_start, layout.coast_end, ellipse)
			var bay_center := Vector2(size * 0.34, 0.0)
			var bay_distance := local.distance_to(bay_center) / (size * 0.31)
			var inlet := 1.0 - smoothstep(0.62, 1.0, bay_distance)
			return maxf(maxf(outer, inlet), edge_falloff)
		BattlefieldLayoutDefinition.TerrainShape.VALLEY:
			var valley_perimeter := Vector2(local.x / 0.82, local.y / 1.08).length() / half
			return maxf(smoothstep(0.82, 0.98, valley_perimeter / radius_scale), edge_falloff)
		BattlefieldLayoutDefinition.TerrainShape.COASTAL_PLAIN:
			var coast_line := 0.56 + coast_noise.get_noise_2d(local.y, 0.0) * 0.1
			return maxf(smoothstep(coast_line, coast_line + 0.12, local.x / half), edge_falloff)
	return maxf(smoothstep(layout.coast_start, layout.coast_end, shaped_radial_distance), edge_falloff)

func _grid_world(index: int) -> float:
	return -size * 0.5 + size * float(index) / float(resolution - 1)

func _height(x_index: int, z_index: int) -> float:
	return heights[z_index * resolution + x_index]

func _vertex(x_index: int, z_index: int) -> Vector3:
	return Vector3(_grid_world(x_index), _height(x_index, z_index), _grid_world(z_index))

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.set_uv(Vector2(a.x / size, a.z / size))
	surface.add_vertex(a)
	surface.set_uv(Vector2(b.x / size, b.z / size))
	surface.add_vertex(b)
	surface.set_uv(Vector2(c.x / size, c.z / size))
	surface.add_vertex(c)
