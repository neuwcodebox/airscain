class_name ObjectiveDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var maximum_integrity: int = 100
@export var restoration_cost: int = 200
@export var restoration_amount: int = 10
@export var required_for_survival: bool = true

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene == null:
		return "보호 목표 Definition의 필수 참조가 없습니다"
	if maximum_integrity <= 0:
		return "보호 목표 상태는 0보다 커야 합니다"
	if restoration_cost <= 0 or restoration_amount <= 0:
		return "보호 목표 복구 비용과 회복량은 0보다 커야 합니다"
	return ""
