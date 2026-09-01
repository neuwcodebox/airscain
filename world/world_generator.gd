class_name WorldGenerator
extends RefCounted

var size: float
var resolution: int
var city_size: float
var seed_value: int
var heights: PackedFloat32Array
var sea_level: float = 0.0

func generate(seed_input: int, size_input: float, resolution_input: int, city_size_input: float) -> void:
	seed_value = seed_input
	size = size_input
	resolution = resolution_input
	city_size = city_size_input
	heights = PackedFloat32Array()
	heights.resize(resolution * resolution)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0035
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.48
	for z_index: int in resolution:
		for x_index: int in resolution:
			var x := _grid_world(x_index)
			var z := _grid_world(z_index)
			var raw := noise.get_noise_2d(x, z) * 42.0
			var distance_from_city := maxf(absf(x), absf(z))
			var flatten := smoothstep(city_size * 0.42, city_size * 0.72, distance_from_city)
			var land_height := maxf(raw * flatten + 10.0, sea_level + 6.0)
			var radial_distance := Vector2(x, z).length() / (size * 0.5)
			var coast_falloff := smoothstep(0.72, 0.98, radial_distance)
			heights[z_index * resolution + x_index] = lerpf(land_height, sea_level - 35.0, coast_falloff)

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
	var blocks := 7
	var block_step := city_size / float(blocks)
	for bz: int in blocks:
		for bx: int in blocks:
			if (bx == 3 and bz == 3) or rng.randf() < 0.08:
				continue
			var width := rng.randf_range(20.0, 34.0)
			var depth := rng.randf_range(20.0, 34.0)
			var height := rng.randf_range(8.0, 70.0)
			var x := (float(bx) - 3.0) * block_step + rng.randf_range(-4.0, 4.0)
			var z := (float(bz) - 3.0) * block_step + rng.randf_range(-4.0, 4.0)
			var basis := Basis.IDENTITY.scaled(Vector3(width, height, depth))
			result.append(Transform3D(basis, Vector3(x, height * 0.5 + height_at(x, z), z)))
	return result

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
