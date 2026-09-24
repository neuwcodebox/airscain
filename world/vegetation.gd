class_name Vegetation
extends Node3D
## Cosmetic trees, shrubs and boulders scattered from the ground-cover field.
## Uses its own RNG and never affects placement, sensing or collision rules.

const CHUNK_SIZE := 600.0
const FOREST_SPACING := 8.5
const SHADER := preload("res://world/vegetation.gdshader")

enum Kind { BROADLEAF, PINE, SHRUB, BOULDER }

class Chunk:
	extends RefCounted
	var multimesh: MultiMesh
	var positions := PackedVector3Array()
	var radii := PackedFloat32Array()

var instance_counts: Dictionary[Kind, int] = {}
var _chunks: Array[Chunk] = []
var _pending: Dictionary[Array, Array] = {}

static var _meshes: Dictionary[Kind, ArrayMesh] = {}
static var _material: ShaderMaterial

func build(generator: WorldGenerator, cover: GroundCover) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = generator.seed_value ^ 0x45B7
	var half := generator.size * 0.5
	var cells := int(generator.size / FOREST_SPACING)
	for z_index: int in cells:
		for x_index: int in cells:
			var x := -half + (float(x_index) + rng.randf()) * FOREST_SPACING
			var z := -half + (float(z_index) + rng.randf()) * FOREST_SPACING
			var roll := rng.randf()
			if cover.is_farmed(x, z):
				continue
			var woods := cover.forest_at(x, z)
			var density := woods * (0.35 + woods * 0.6)
			var lone := 0.006 * (1.0 - woods)
			if roll >= density + lone and roll >= 0.02:
				continue
			var height := generator.height_at(x, z)
			if height < generator.sea_level + GroundCover.SHORE_HEIGHT:
				continue
			var slope := generator.slope_degrees_at(x, z, 4.0)
			if roll < density + lone:
				_scatter_tree(rng, Vector3(x, height, z), slope, woods, cover.dryness_at(x, z))
			elif slope > 17.0 or (woods > 0.2 and rng.randf() < 0.15):
				_add(Kind.BOULDER, Vector3(x, height - 0.4, z), Vector3(rng.randf_range(1.6, 4.2), rng.randf_range(1.0, 2.6), rng.randf_range(1.6, 4.0)), _rock_color(rng), rng, true)
			elif woods > 0.05 or rng.randf() < 0.3:
				var size := rng.randf_range(1.8, 3.6)
				_add(Kind.SHRUB, Vector3(x, height - 0.2, z), Vector3(size, size * 0.65, size), _leaf_color(rng, 0.3, 0.0), rng)
	_flush()

## Removes cosmetic scenery from a site so placed equipment never stands inside a tree.
func clear_around(position: Vector3, radius: float) -> void:
	var reach := radius + 2.0
	for chunk: Chunk in _chunks:
		for index: int in chunk.positions.size():
			var offset := Vector2(chunk.positions[index].x - position.x, chunk.positions[index].z - position.z)
			if offset.length() < reach + chunk.radii[index]:
				chunk.multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), chunk.positions[index]))
				chunk.radii[index] = -INF

## Positions of every scenery piece still standing.
func standing_positions() -> PackedVector3Array:
	var result := PackedVector3Array()
	for chunk: Chunk in _chunks:
		for index: int in chunk.positions.size():
			if chunk.radii[index] > -INF:
				result.append(chunk.positions[index])
	return result

## Number of scenery pieces still standing whose trunk lies within `radius`.
func standing_within(position: Vector3, radius: float) -> int:
	var count := 0
	for chunk: Chunk in _chunks:
		for index: int in chunk.positions.size():
			if chunk.radii[index] > -INF and Vector2(chunk.positions[index].x - position.x, chunk.positions[index].z - position.z).length() < radius:
				count += 1
	return count

func _scatter_tree(rng: RandomNumberGenerator, ground: Vector3, slope: float, woods: float, dry: float) -> void:
	var conifer := clampf(0.25 + (ground.y - 20.0) / 60.0 + slope / 60.0 - dry * 0.2, 0.05, 0.9)
	var mature := lerpf(0.75, 1.2, woods) * rng.randf_range(0.8, 1.2)
	if rng.randf() < conifer:
		var height := rng.randf_range(10.0, 17.0) * mature
		_add(Kind.PINE, ground + Vector3.DOWN * 0.3, Vector3(height * 0.36, height, height * 0.36), _pine_color(rng), rng)
	else:
		var height := rng.randf_range(8.0, 13.0) * mature
		var width := height * rng.randf_range(0.62, 0.8)
		_add(Kind.BROADLEAF, ground + Vector3.DOWN * 0.3, Vector3(width, height, width), _leaf_color(rng, dry, woods), rng)

func _leaf_color(rng: RandomNumberGenerator, dry: float, woods: float) -> Color:
	var lush := Color("34512b").lerp(Color("2a4427"), woods)
	var autumn := Color("5f6432").lerp(Color("7a5f33"), rng.randf() * 0.5)
	var color := lush.lerp(autumn, clampf(dry * 0.5 + rng.randf_range(-0.15, 0.15), 0.0, 1.0))
	return color * rng.randf_range(0.82, 1.08)

func _pine_color(rng: RandomNumberGenerator) -> Color:
	return Color("26402f").lerp(Color("3a5236"), rng.randf()) * rng.randf_range(0.88, 1.1)

func _rock_color(rng: RandomNumberGenerator) -> Color:
	return Color("6c6a62").lerp(Color("8b867a"), rng.randf()) * rng.randf_range(0.85, 1.05)

func _add(kind: Kind, position: Vector3, scale: Vector3, color: Color, rng: RandomNumberGenerator, tumble: bool = false) -> void:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if tumble:
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
	var key: Array = [kind, floori(position.x / CHUNK_SIZE), floori(position.z / CHUNK_SIZE)]
	if not _pending.has(key):
		_pending[key] = []
	_pending[key].append([Transform3D(basis * Basis.from_scale(scale), position), color, maxf(scale.x, scale.z) * 0.5])
	instance_counts[kind] = instance_counts.get(kind, 0) + 1

func _flush() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	for key: Array in _pending:
		var kind: Kind = key[0]
		var entries: Array = _pending[key]
		var chunk := Chunk.new()
		chunk.multimesh = MultiMesh.new()
		chunk.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		# Compatibility multiplies vertex color by instance color, so keep it white.
		chunk.multimesh.use_colors = true
		chunk.multimesh.use_custom_data = true
		chunk.multimesh.mesh = _mesh(kind)
		chunk.multimesh.instance_count = entries.size()
		for index: int in entries.size():
			var pose: Transform3D = entries[index][0]
			chunk.multimesh.set_instance_transform(index, pose)
			chunk.multimesh.set_instance_color(index, Color.WHITE)
			chunk.multimesh.set_instance_custom_data(index, entries[index][1])
			chunk.positions.append(pose.origin)
			chunk.radii.append(float(entries[index][2]))
		var visual := MultiMeshInstance3D.new()
		visual.name = "%s_%d_%d" % [Kind.keys()[kind].capitalize(), key[1], key[2]]
		visual.multimesh = chunk.multimesh
		visual.material_override = _material
		add_child(visual)
		_chunks.append(chunk)
	_pending.clear()

static func _mesh(kind: Kind) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var builder := LowPolyBuilder.new()
	var bark := Color("4f3e2f")
	match kind:
		Kind.BROADLEAF:
			builder.cylinder(Vector3.ZERO, 0.035, 0.05, 0.42, 4, bark, 0.0)
			builder.blob(Vector3(0.0, 0.64, 0.0), Vector3(0.5, 0.36, 0.5), 6, 4, 0.0, 1.0)
			builder.blob(Vector3(0.15, 0.5, 0.08), Vector3(0.32, 0.24, 0.32), 5, 3, 0.25, 1.0)
		Kind.PINE:
			builder.cylinder(Vector3.ZERO, 0.05, 0.07, 0.25, 4, bark, 0.0)
			for tier: int in 3:
				var base := 0.18 + float(tier) * 0.25
				var radius := 0.5 - float(tier) * 0.12
				builder.cone(Vector3(0.0, base, 0.0), radius, 0.44 - float(tier) * 0.04, 6, float(tier) * 0.7)
		Kind.SHRUB:
			builder.blob(Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.5, 0.5), 6, 3, 0.0, 1.0)
		Kind.BOULDER:
			builder.blob(Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.5, 0.5), 6, 4, 0.0, 1.0, 0.22)
	_meshes[kind] = builder.commit()
	return _meshes[kind]

## Flat-shaded low-poly assembly with baked vertical shading in vertex color.
class LowPolyBuilder:
	extends RefCounted
	var _surface := SurfaceTool.new()

	func _init() -> void:
		_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	func cylinder(base: Vector3, top_radius: float, bottom_radius: float, height: float, sides: int, color: Color, phase: float) -> void:
		for side: int in sides:
			var a0 := TAU * float(side) / float(sides) + phase
			var a1 := TAU * float(side + 1) / float(sides) + phase
			var b0 := base + Vector3(cos(a0), 0.0, sin(a0)) * bottom_radius
			var b1 := base + Vector3(cos(a1), 0.0, sin(a1)) * bottom_radius
			var t0 := base + Vector3(cos(a0) * top_radius, height, sin(a0) * top_radius)
			var t1 := base + Vector3(cos(a1) * top_radius, height, sin(a1) * top_radius)
			var axis := base + Vector3.UP * height * 0.5
			_triangle(b0, t0, b1, color, color, color, 0.0, axis)
			_triangle(b1, t0, t1, color, color, color, 0.0, axis)

	func cone(base: Vector3, radius: float, height: float, sides: int, phase: float) -> void:
		var tip := base + Vector3.UP * height
		for side: int in sides:
			var a0 := TAU * float(side) / float(sides) + phase
			var a1 := TAU * float(side + 1) / float(sides) + phase
			var jitter := 1.0 + sin(float(side) * 2.3 + phase * 3.0) * 0.08
			var p0 := base + Vector3(cos(a0), -0.02 * jitter, sin(a0)) * radius * jitter
			var p1 := base + Vector3(cos(a1), 0.0, sin(a1)) * radius
			_triangle(p0, tip, p1, _shade(0.62), _shade(1.0), _shade(0.62), 1.0, base + Vector3.UP * height * 0.3)
			_triangle(p1, base + Vector3.UP * 0.02, p0, _shade(0.4), _shade(0.4), _shade(0.4), 1.0, base + Vector3.UP * height)

	func blob(center: Vector3, radii: Vector3, sides: int, rings: int, phase: float, tint: float, roughness: float = 0.1) -> void:
		var points: Array[Vector3] = []
		for ring: int in rings + 1:
			var latitude := PI * float(ring) / float(rings)
			for side: int in sides:
				var longitude := TAU * float(side) / float(sides) + phase + float(ring) * 0.4
				var direction := Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
				var bump := 1.0 + sin(float(ring * 7 + side * 3) + phase * 5.0) * roughness
				points.append(center + direction * radii * bump)
		for ring: int in rings:
			for side: int in sides:
				var next := (side + 1) % sides
				var a := points[ring * sides + side]
				var b := points[ring * sides + next]
				var c := points[(ring + 1) * sides + side]
				var d := points[(ring + 1) * sides + next]
				var upper := _shade(0.55 + 0.45 * (1.0 - float(ring) / float(rings)))
				var lower := _shade(0.55 + 0.45 * (1.0 - float(ring + 1) / float(rings)))
				if ring > 0:
					_triangle(a, b, c, upper, upper, lower, tint, center)
				if ring < rings - 1:
					_triangle(b, d, c, upper, lower, lower, tint, center)

	func commit() -> ArrayMesh:
		return _surface.commit()

	func _shade(value: float) -> Color:
		return Color(value, value, value)

	## Orients each face away from `inside`; Godot treats clockwise faces as front.
	func _triangle(a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color, tint: float, inside: Vector3) -> void:
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 1e-12:
			return
		var corners: Array = [[a, color_a], [b, color_b], [c, color_c]]
		if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
			corners = [[a, color_a], [c, color_c], [b, color_b]]
			normal = -normal
		_surface.set_normal(normal.normalized())
		for pair: Array in corners:
			var color: Color = pair[1]
			color.a = tint
			_surface.set_color(color)
			_surface.add_vertex(pair[0])
