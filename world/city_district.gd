class_name CityDistrict
extends RefCounted

var id: StringName
var center: Vector2
var blocks: Array[Dictionary]
var buildings: Array[Transform3D]

func _init(id_value: StringName, center_value: Vector2, blocks_value: Array[Dictionary], buildings_value: Array[Transform3D]) -> void:
	id = id_value
	center = center_value
	blocks = blocks_value.duplicate(true)
	buildings = buildings_value.duplicate()

func has_buildings() -> bool:
	return not buildings.is_empty()

func random_building(rng: RandomNumberGenerator) -> Transform3D:
	if buildings.is_empty():
		return Transform3D.IDENTITY
	return buildings[rng.randi_range(0, buildings.size() - 1)]
