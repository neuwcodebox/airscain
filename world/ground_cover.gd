class_name GroundCover
extends RefCounted
## Cosmetic land-cover field shared by terrain shading and scenery scattering.
## Channels: R forest, G dry grass, B farmland, A terrain curvature (0.5 = flat).
## Derived from the world seed only; never read by gameplay rules.

const TEXELS := 192
const CITY_CLEARANCE := 0.62
const SHORE_HEIGHT := 7.0
## Rectangular field cells in the rotated field frame; the terrain shader uses the same size.
const FIELD_CELL := Vector2(64.0, 40.0)
## Farmed cells must be lowland near a town with little relief across the whole field.
const FIELD_MAXIMUM_RELIEF := 6.0
const FIELD_MAXIMUM_HEIGHT := 32.0
const MINIMUM_FARM_CLUSTER := 4

var size: float = 2400.0
var forest := PackedFloat32Array()
var dryness := PackedFloat32Array()
var farmland := PackedFloat32Array()
var curvature := PackedFloat32Array()
var field_rotation: float = 0.0
var farmed_cells: Dictionary[Vector2i, bool] = {}
var texture: ImageTexture

func build(generator: WorldGenerator, blocks: Array[Dictionary]) -> void:
	size = generator.size
	var count := TEXELS * TEXELS
	for channel: PackedFloat32Array in [forest, dryness, farmland, curvature]:
		channel.resize(count)
	var forest_noise := _noise(generator.seed_value ^ 0x51F0, 0.0021, 4)
	var dry_noise := _noise(generator.seed_value ^ 0x2C93, 0.0012, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = generator.seed_value ^ 0x3F11
	field_rotation = rng.randf_range(-0.6, 0.6)
	var city_mask := _city_mask(blocks)
	var districts := generator.city_districts()
	var texel := size / float(TEXELS)
	var probe := texel * 2.0
	var land := PackedFloat32Array()
	land.resize(count)
	for z_index: int in TEXELS:
		for x_index: int in TEXELS:
			var index := z_index * TEXELS + x_index
			var x := -size * 0.5 + (float(x_index) + 0.5) * texel
			var z := -size * 0.5 + (float(z_index) + 0.5) * texel
			var height := generator.height_at(x, z)
			var around := (generator.height_at(x - probe, z) + generator.height_at(x + probe, z) + generator.height_at(x, z - probe) + generator.height_at(x, z + probe)) * 0.25
			# Positive values are hollows and valley floors, negative values ridges.
			var bend := clampf((around - height) / 6.0, -1.0, 1.0)
			curvature[index] = bend * 0.5 + 0.5
			land[index] = smoothstep(generator.sea_level + 3.0, generator.sea_level + SHORE_HEIGHT + 3.0, height) * (1.0 - city_mask[index])
			dryness[index] = clampf(dry_noise.get_noise_2d(x, z) * 0.9 + 0.45 - bend * 0.35 + smoothstep(35.0, 80.0, height) * 0.25, 0.0, 1.0)
	_plan_fields(generator, districts, city_mask)
	for z_index: int in TEXELS:
		for x_index: int in TEXELS:
			var index := z_index * TEXELS + x_index
			var x := -size * 0.5 + (float(x_index) + 0.5) * texel
			var z := -size * 0.5 + (float(z_index) + 0.5) * texel
			var farm := 1.0 if is_farmed(x, z) else 0.0
			farmland[index] = farm
			var slope := generator.slope_degrees_at(x, z, texel)
			var bend := curvature[index] * 2.0 - 1.0
			var woods := smoothstep(-0.12, 0.28, forest_noise.get_noise_2d(x, z) + bend * 0.25 - dryness[index] * 0.25 + smoothstep(8.0, 22.0, slope) * 0.15)
			forest[index] = woods * land[index] * (1.0 - smoothstep(30.0, 40.0, slope)) * (1.0 - farm)
	var image := Image.create(TEXELS, TEXELS, false, Image.FORMAT_RGBA8)
	for z_index: int in TEXELS:
		for x_index: int in TEXELS:
			var index := z_index * TEXELS + x_index
			image.set_pixel(x_index, z_index, Color(forest[index], dryness[index], farmland[index], curvature[index]))
	texture = ImageTexture.create_from_image(image)

func forest_at(x: float, z: float) -> float:
	return _sample(forest, x, z)

func farmland_at(x: float, z: float) -> float:
	return 1.0 if is_farmed(x, z) else 0.0

## Exact field membership, matching the terrain shader's per-cell decision.
func is_farmed(x: float, z: float) -> bool:
	return farmed_cells.has(field_cell(x, z))

func field_cell(x: float, z: float) -> Vector2i:
	var local := _to_field(Vector2(x, z))
	return Vector2i(floori(local.x / FIELD_CELL.x), floori(local.y / FIELD_CELL.y))

func _to_field(point: Vector2) -> Vector2:
	var c := cos(field_rotation)
	var s := sin(field_rotation)
	return Vector2(c * point.x - s * point.y, s * point.x + c * point.y)

func _from_field(local: Vector2) -> Vector2:
	var c := cos(field_rotation)
	var s := sin(field_rotation)
	return Vector2(c * local.x + s * local.y, -s * local.x + c * local.y)

func _plan_fields(generator: WorldGenerator, districts: Array[CityDistrict], city_mask: PackedFloat32Array) -> void:
	farmed_cells.clear()
	var reach := size * 0.75
	var first := Vector2i(floori(-reach / FIELD_CELL.x), floori(-reach / FIELD_CELL.y))
	var last := Vector2i(ceili(reach / FIELD_CELL.x), ceili(reach / FIELD_CELL.y))
	for cell_z: int in range(first.y, last.y + 1):
		for cell_x: int in range(first.x, last.x + 1):
			var cell := Vector2i(cell_x, cell_z)
			var center := _from_field((Vector2(cell) + Vector2(0.5, 0.5)) * FIELD_CELL)
			if absf(center.x) > size * 0.46 or absf(center.y) > size * 0.46:
				continue
			var town_distance := _district_edge_distance(center, districts)
			if town_distance < 30.0 or town_distance > 700.0:
				continue
			if _field_is_arable(generator, cell, city_mask):
				farmed_cells[cell] = true
	# Farmland forms patchworks on sizeable flat lowland; drop small clusters.
	var visited: Dictionary[Vector2i, bool] = {}
	for start: Vector2i in farmed_cells.keys():
		if visited.has(start):
			continue
		var cluster: Array[Vector2i] = [start]
		visited[start] = true
		var cursor := 0
		while cursor < cluster.size():
			var cell := cluster[cursor]
			cursor += 1
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := cell + offset
				if farmed_cells.has(next) and not visited.has(next):
					visited[next] = true
					cluster.append(next)
		if cluster.size() < MINIMUM_FARM_CLUSTER:
			for cell: Vector2i in cluster:
				farmed_cells.erase(cell)

func _field_is_arable(generator: WorldGenerator, cell: Vector2i, city_mask: PackedFloat32Array) -> bool:
	var lowest := INF
	var highest := -INF
	for sample_z: int in 3:
		for sample_x: int in 3:
			var local := (Vector2(cell) + Vector2(0.1 + 0.4 * float(sample_x), 0.1 + 0.4 * float(sample_z))) * FIELD_CELL
			var point := _from_field(local)
			var index := _texel_index(point)
			if city_mask[index.y * TEXELS + index.x] > 0.02:
				return false
			var height := generator.height_at(point.x, point.y)
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
	if lowest <= generator.sea_level + SHORE_HEIGHT + 2.0 or highest >= generator.sea_level + FIELD_MAXIMUM_HEIGHT or highest - lowest > FIELD_MAXIMUM_RELIEF:
		return false
	# Skip crests: the field center must not stand above its surroundings.
	var center := _from_field((Vector2(cell) + Vector2(0.5, 0.5)) * FIELD_CELL)
	var reach := FIELD_CELL.x
	var around := (generator.height_at(center.x - reach, center.y) + generator.height_at(center.x + reach, center.y) + generator.height_at(center.x, center.y - reach) + generator.height_at(center.x, center.y + reach)) * 0.25
	return generator.height_at(center.x, center.y) <= around + 1.0

func dryness_at(x: float, z: float) -> float:
	return _sample(dryness, x, z)

func _sample(channel: PackedFloat32Array, x: float, z: float) -> float:
	if channel.is_empty():
		return 0.0
	var gx := clampf((x / size + 0.5) * float(TEXELS) - 0.5, 0.0, float(TEXELS - 1))
	var gz := clampf((z / size + 0.5) * float(TEXELS) - 0.5, 0.0, float(TEXELS - 1))
	var x0 := int(gx)
	var z0 := int(gz)
	var x1 := mini(x0 + 1, TEXELS - 1)
	var z1 := mini(z0 + 1, TEXELS - 1)
	var a := lerpf(channel[z0 * TEXELS + x0], channel[z0 * TEXELS + x1], gx - float(x0))
	var b := lerpf(channel[z1 * TEXELS + x0], channel[z1 * TEXELS + x1], gx - float(x0))
	return lerpf(a, b, gz - float(z0))

func _city_mask(blocks: Array[Dictionary]) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(TEXELS * TEXELS)
	var texel := size / float(TEXELS)
	for block: Dictionary in blocks:
		var center: Vector3 = block.position
		var step: float = block.block_step
		var reach := step * (0.5 + CITY_CLEARANCE)
		var first := _texel_index(Vector2(center.x, center.z) - Vector2.ONE * reach * 1.5)
		var last := _texel_index(Vector2(center.x, center.z) + Vector2.ONE * reach * 1.5)
		for z_index: int in range(first.y, last.y + 1):
			for x_index: int in range(first.x, last.x + 1):
				var point := Vector2(-size * 0.5 + (float(x_index) + 0.5) * texel, -size * 0.5 + (float(z_index) + 0.5) * texel)
				var local := (point - Vector2(center.x, center.z)).rotated(-float(block.rotation))
				var outside := Vector2(maxf(absf(local.x) - step * 0.5, 0.0), maxf(absf(local.y) - step * 0.5, 0.0)).length()
				var index := z_index * TEXELS + x_index
				mask[index] = maxf(mask[index], 1.0 - smoothstep(step * 0.1, step * CITY_CLEARANCE, outside))
	return mask

func _texel_index(point: Vector2) -> Vector2i:
	var texel := size / float(TEXELS)
	return Vector2i(
		clampi(int((point.x + size * 0.5) / texel), 0, TEXELS - 1),
		clampi(int((point.y + size * 0.5) / texel), 0, TEXELS - 1)
	)

func _district_edge_distance(point: Vector2, districts: Array[CityDistrict]) -> float:
	var best := INF
	for district: CityDistrict in districts:
		best = minf(best, point.distance_to(district.center) - district.definition.size * 0.5)
	return best

static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise
