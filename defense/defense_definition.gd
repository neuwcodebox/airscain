class_name DefenseDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var price: int = 200
@export var placement_profile: PlacementProfile
@export var preview_range: float = 300.0

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene == null or placement_profile == null:
		return "방어 수단 Definition의 필수 참조가 없습니다"
	if price < 0 or preview_range <= 0.0:
		return "방어 수단 가격 또는 범위가 올바르지 않습니다"
	return placement_profile.validation_error()
