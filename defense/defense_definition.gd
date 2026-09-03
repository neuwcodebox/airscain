class_name DefenseDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var purchase_tooltip: String
@export var scene: PackedScene
@export var price: int = 200
@export var unlock_pressure_level: int = 1
@export var placement_profile: PlacementProfile
@export var preview_range: float = 300.0
@export var maximum_integrity: float = 100.0
@export var repair_cost: int = 10
@export var repair_work: float = 16.0
@export var mobile: bool = false
@export var relocation_duration: float = 0.0

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene == null or placement_profile == null:
		return "방어 수단 Definition의 필수 참조가 없습니다"
	if price < 0 or unlock_pressure_level < 1 or preview_range <= 0.0 or maximum_integrity <= 0.0 or repair_cost < 0 or repair_work <= 0.0:
		return "방어 수단 가격 또는 범위가 올바르지 않습니다"
	if mobile and relocation_duration <= 0.0:
		return "이동형 자산의 재배치 시간이 올바르지 않습니다"
	return placement_profile.validation_error()
