class_name WorldGenerator
extends RefCounted

const CITY_GROUND_HEIGHT := 10.0
const CITY_PRESENTATION_SCALE := 0.9

var size: float
var resolution: int
var city_size: float
var seed_value: int
var heights: PackedFloat32Array
var sea_level: float = 0.0
var layout: BattlefieldLayoutDefinition
var _city_blocks: Array[Dictionary] = []

func generate(seed_input: int, size_input: float, resolution_input: int, city_size_input: float, layout_value: BattlefieldLayoutDefinition = null) -> void:
	seed_value = seed_input
	size = size_input
	resolution = resolution_input
	city_size = city_size_input
	layout = layout_value if layout_value != null else BattlefieldLayoutDefinition.new()
	_city_blocks.clear()
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
	var coast_phase_a := float(posmod(seed_value * 3, 997)) / 997.0 * TAU
	var coast_phase_b := float(posmod(seed_value * 11, 991)) / 991.0 * TAU
	for z_index: int in resolution:
		for x_index: int in resolution:
			var x := _grid_world(x_index)
			var z := _grid_world(z_index)
			var raw := noise.get_noise_2d(x, z) * layout.terrain_height_scale
			var distance_from_city := Vector2(x, z).length()
			var flatten := smoothstep(city_size * 0.27, city_size * 0.62, distance_from_city)
			var land_height := maxf(raw * flatten + CITY_GROUND_HEIGHT, sea_level + 6.0)
			var radial_distance := Vector2(x, z).length() / (size * 0.5)
			var coast_angle := atan2(z, x)
			var coast_radius_scale := 1.0 + sin(coast_angle * 3.0 + coast_phase_a) * 0.11 + sin(coast_angle * 5.0 + coast_phase_b) * 0.065 + coast_noise.get_noise_2d(x, z) * 0.075
			coast_radius_scale = clampf(coast_radius_scale, 0.78, 1.18)
			var shaped_radial_distance := radial_distance / coast_radius_scale
			var shaped_falloff := smoothstep(layout.coast_start, layout.coast_end, shaped_radial_distance)
			var edge_falloff := smoothstep(0.9, 0.985, radial_distance)
			var coast_falloff := maxf(shaped_falloff, edge_falloff)
			heights[z_index * resolution + x_index] = lerpf(land_height, sea_level - 35.0, coast_falloff)
	_city_blocks = _create_city_block_layout()
	_flatten_city_footprint()
	_refresh_city_block_heights()

func height_at(x: float, z: float) -> float:
	var half := size * 0.5
	var gx := clampf((x + half) / size * float(resolution - 1), 0.0, float(resolution - 1))
	var gz := clampf((z + half) / size * float(resolution - 1), 0.0, float(resolution - 1))
	var x0 := mini(int(floor(gx)), resolution - 1)
	var z0 := mini(int(floor(gz)), resolution - 1)
	var x1 := mini(x0 + 1, resolution - 1)
	var z1 := mini(z0 + 1, resolution - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var a := lerpf(_height(x0, z0), _height(x1, z0), tx)
	var b := lerpf(_height(x0, z1), _height(x1, z1), tx)
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
	var result: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x51A7
	var block_step := city_size / float(layout.city_blocks)
	for block: Dictionary in city_block_layout():
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
			var x := block_center.x + (offset if split_along_x else rng.randf_range(-2.2, 2.2))
			var z := block_center.z + (rng.randf_range(-2.2, 2.2) if split_along_x else offset)
			var width_limit := block_step * (0.30 if building_count == 2 and split_along_x else 0.60)
			var depth_limit := block_step * (0.30 if building_count == 2 and not split_along_x else 0.60)
			var width := rng.randf_range(width_limit * 0.78, width_limit)
			var depth := rng.randf_range(depth_limit * 0.78, depth_limit)
			var zone_height_scale := lerpf(0.32, 1.18, center_weight)
			var height := clampf(rng.randf_range(layout.minimum_building_height, layout.maximum_building_height) * zone_height_scale, layout.minimum_building_height, layout.maximum_building_height * 1.08) * CITY_PRESENTATION_SCALE
			var basis := Basis.IDENTITY.scaled(Vector3(width, height, depth))
			result.append(Transform3D(basis, Vector3(x, height * 0.5 + height_at(x, z), z)))
	return result

func city_block_layout() -> Array[Dictionary]:
	return _city_blocks.duplicate(true)

func _create_city_block_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var block_count := layout.city_blocks
	var block_step := city_size / float(block_count)
	var center := float(block_count - 1) * 0.5
	var phase_a := float(posmod(seed_value, 997)) / 997.0 * TAU
	var phase_b := float(posmod(seed_value * 7, 991)) / 991.0 * TAU
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x2D71
	for bz: int in block_count:
		for bx: int in block_count:
			var grid := Vector2i(bx - int(center), bz - int(center))
			var grid_position := Vector2(float(grid.x), float(grid.y))
			var normalized_distance := grid_position.length() / maxf(center, 1.0)
			var angle := atan2(grid_position.y, grid_position.x)
			var boundary := 0.83 + sin(angle * 3.0 + phase_a) * 0.12 + sin(angle * 5.0 + phase_b) * 0.07 + rng.randf_range(-0.06, 0.06)
			var x := float(grid.x) * block_step
			var z := float(grid.y) * block_step
			var central_core := normalized_distance <= 0.34
			var terrain_suitable := height_at(x, z) > sea_level + 3.0 and slope_degrees_at(x, z, block_step * 0.32) <= 11.0
			if normalized_distance <= boundary and (central_core or terrain_suitable):
				result.append({
					"grid": grid,
					"position": Vector3(x, height_at(x, z), z),
					"normalized_distance": normalized_distance,
				})
	return result

func _flatten_city_footprint() -> void:
	var block_step := city_size / float(layout.city_blocks)
	var terrain_step := size / float(resolution - 1)
	var block_half_extent := block_step * 0.54 + terrain_step * 0.75
	var feather_distance := block_step * 0.72
	for z_index: int in resolution:
		for x_index: int in resolution:
			var x := _grid_world(x_index)
			var z := _grid_world(z_index)
			var flatten_weight := 0.0
			for block: Dictionary in _city_blocks:
				var position: Vector3 = block.position
				var outside_x := maxf(absf(x - position.x) - block_half_extent, 0.0)
				var outside_z := maxf(absf(z - position.z) - block_half_extent, 0.0)
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
