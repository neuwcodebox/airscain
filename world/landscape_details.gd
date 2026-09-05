class_name LandscapeDetails
extends Node3D
## Cosmetic scenery uses its own RNG and batched geometry, never gameplay state.

var _batches: Dictionary[String, Array] = {}
var _colors: Dictionary[String, Color] = {
	"leaf": Color("435a3e"), "pine": Color("344d41"), "trunk": Color("65513e"),
	"rock": Color("79786a"), "paint": Color("d6d3bb"), "car": Color("69858c"),
	"car_warm": Color("aa795b"), "glass": Color("283c42"), "metal": Color("4d5655"),
}

func build(generator: WorldGenerator, blocks: Array[Dictionary], buildings: Array[Transform3D], road_width: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = generator.seed_value ^ 0x45B7
	var block_step := generator.city_size / float(generator.layout.city_blocks)
	for index: int in 1700:
		var x := rng.randf_range(-0.46, 0.46) * generator.size
		var z := rng.randf_range(-0.46, 0.46) * generator.size
		var height := generator.height_at(x, z)
		var slope := generator.slope_degrees_at(x, z, 8.0)
		if height < 16.0 or slope < 7.0 or slope > 32.0 or _near_blocks(Vector2(x, z), blocks, block_step):
			continue
		var cluster := sin(x * 0.019) * cos(z * 0.015)
		if cluster < -0.1:
			continue
		var scale_value := rng.randf_range(0.75, 1.65)
		var position := Vector3(x, height - 0.5, z)
		if slope > 21.0:
			_append("rock", position + Vector3.UP, Vector3(4, 2.8, 3) * scale_value, rng.randf() * TAU)
		else:
			_append("trunk", position + Vector3.UP * 2.2 * scale_value, Vector3(0.65, 4.4, 0.65) * scale_value)
			_append("pine" if index % 3 == 0 else "leaf", position + Vector3.UP * 4.6 * scale_value, Vector3(4.2, 5.6, 4.2) * scale_value, rng.randf() * TAU)
	var occupied: Dictionary = {}
	for block: Dictionary in blocks:
		occupied[block.grid] = true
	for block: Dictionary in blocks:
		var grid: Vector2i = block.grid
		var center: Vector3 = block.position
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if not occupied.has(grid + direction):
				continue
			var along := Vector3(direction.x, 0, direction.y)
			var across := Vector3(-direction.y, 0, direction.x)
			var road_center := center + along * block_step * 0.5
			for stripe: int in 6:
				var position := road_center + along * (float(stripe) - 2.5) * 1.15 + across * block_step * 0.33
				position.y = generator.height_at(position.x, position.z) + 0.34
				_append("paint", position, Vector3(0.55, 0.035, road_width * 0.64), -atan2(along.z, along.x))
			if rng.randf() < 0.65:
				var position := road_center + along * 2.0 + across * rng.randf_range(-0.2, 0.2) * block_step
				position.y = generator.height_at(position.x, position.z) + 1.0
				var yaw := -atan2(across.z, across.x)
				_append("car" if grid.x % 2 == 0 else "car_warm", position, Vector3(3.8, 1.2, 1.7), yaw)
				_append("glass", position + Vector3.UP * 0.75, Vector3(2.0, 0.65, 1.5), yaw)
	# Street-level entrances give each facade a ground floor, within its footprint.
	for building: Transform3D in buildings:
		var size := building.basis.get_scale()
		var entrance := building.origin + Vector3(0, -size.y * 0.5 + 1.7, size.z * 0.5 + 0.14)
		_append("glass", entrance, Vector3(2.4, 3.4, 0.16))
		_append("metal", entrance + Vector3(0, 2, -0.3), Vector3(4.4, 0.25, 0.9))
	for key: String in _batches:
		_flush(key)
	_batches.clear()

func _near_blocks(position: Vector2, blocks: Array[Dictionary], spacing: float) -> bool:
	for block: Dictionary in blocks:
		var center: Vector3 = block.position
		if position.distance_squared_to(Vector2(center.x, center.z)) < spacing * spacing:
			return true
	return false

func _append(key: String, position: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append(Transform3D(Basis(Vector3.UP, yaw).scaled(size), position))

func _flush(key: String) -> void:
	var mesh: Mesh
	if key in ["leaf", "rock"]:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 5
		sphere.rings = 3
		mesh = sphere
	elif key == "pine":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 0.5
		cone.height = 1.0
		cone.radial_segments = 6
		mesh = cone
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = _colors[key]
	material.roughness = 0.88
	mesh.surface_set_material(0, material)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = _batches[key].size()
	for index: int in batch.instance_count:
		batch.set_instance_transform(index, _batches[key][index])
	var visual := MultiMeshInstance3D.new()
	visual.name = key.capitalize()
	visual.multimesh = batch
	add_child(visual)
