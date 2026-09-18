class_name CityDistrict
extends RefCounted

var definition: CityDistrictDefinition
var blocks: Array[Dictionary]
var buildings: Array[Transform3D]

var id: StringName:
	get: return definition.id

var center: Vector2:
	get: return definition.center

func _init(definition_value: CityDistrictDefinition, blocks_value: Array[Dictionary], buildings_value: Array[Transform3D]) -> void:
	definition = definition_value
	blocks = blocks_value.duplicate(true)
	buildings = buildings_value.duplicate()

func has_buildings() -> bool:
	return not buildings.is_empty()

func random_building(rng: RandomNumberGenerator) -> Transform3D:
	if buildings.is_empty():
		return Transform3D.IDENTITY
	return buildings[rng.randi_range(0, buildings.size() - 1)]
