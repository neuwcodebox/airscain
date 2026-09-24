class_name LandscapeDetails
extends Node3D
## Cosmetic street details use their own RNG and batched geometry, never gameplay state.

var _batches: Dictionary[String, Array] = {}
var _colors: Dictionary[String, Color] = {
	"paint": Color("d6d3bb"), "car": Color("69858c"),
	"car_warm": Color("aa795b"), "glass": Color("283c42"), "metal": Color("4d5655"),
}

func build(generator: WorldGenerator, blocks: Array[Dictionary], buildings: Array[Transform3D], road_width: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = generator.seed_value ^ 0x45B7
	var occupied: Dictionary = {}
	for block: Dictionary in blocks:
		occupied[_block_key(block.district_id, block.grid)] = true
	for block: Dictionary in blocks:
		var grid: Vector2i = block.grid
		var center: Vector3 = block.position
		var block_step: float = block.block_step
		var rotation := Basis(Vector3.UP, float(block.rotation))
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if not occupied.has(_block_key(block.district_id, grid + direction)):
				continue
			var along := rotation * Vector3(direction.x, 0, direction.y)
			var across := rotation * Vector3(-direction.y, 0, direction.x)
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
		var yaw := building.basis.orthonormalized().get_euler().y
		var rotation := Basis(Vector3.UP, yaw)
		var entrance := building.origin + rotation * Vector3(0, -size.y * 0.5 + 1.7, size.z * 0.5 + 0.14)
		_append("glass", entrance, Vector3(2.4, 3.4, 0.16), yaw)
		_append("metal", entrance + Vector3.UP * 2.0 + rotation * Vector3(0, 0, -0.3), Vector3(4.4, 0.25, 0.9), yaw)
	for key: String in _batches:
		_flush(key)
	_batches.clear()

func _block_key(district_id: StringName, grid: Vector2i) -> String:
	return "%s:%d:%d" % [String(district_id), grid.x, grid.y]

func _append(key: String, position: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), position))

func _flush(key: String) -> void:
	var mesh: Mesh
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
