class_name CityBoxBatch
extends RefCounted
## Static opaque city boxes, grouped locally with identical surface materials.
## Animated lamps and selectable rooftop markers remain independent.

const CELL_SIZE := 128.0

class Batch:
	extends RefCounted
	var material: StandardMaterial3D
	var transforms: Array[Transform3D] = []
	var bounds := AABB()

var _batches: Dictionary[Array, Batch] = {}

func add_box(pose: Transform3D, material: StandardMaterial3D) -> void:
	var cell := Vector2i(floori(pose.origin.x / CELL_SIZE), floori(pose.origin.z / CELL_SIZE))
	# These static surfaces vary only by albedo and roughness. Retaining the
	# original material avoids changing color space, lighting or shadow shading.
	var key: Array = [cell, material.albedo_color, material.roughness]
	if not _batches.has(key):
		var batch := Batch.new()
		batch.material = material
		_batches[key] = batch
	var batch := _batches[key]
	var bounds := pose * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
	batch.bounds = bounds if batch.transforms.is_empty() else batch.bounds.merge(bounds)
	batch.transforms.append(pose)

func build(parent: Node3D) -> void:
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	for batch: Batch in _batches.values():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = unit_box
		instances.instance_count = batch.transforms.size()
		instances.custom_aabb = batch.bounds
		for index: int in batch.transforms.size():
			instances.set_instance_transform(index, batch.transforms[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = "CityBoxes%d" % parent.get_child_count()
		visual.multimesh = instances
		visual.material_override = batch.material
		parent.add_child(visual)
	_batches.clear()
