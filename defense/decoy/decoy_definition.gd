class_name DecoyDefinition
extends DefenseDefinition

@export_enum("sensor", "weapon") var spoof_role: String = "sensor"

func validation_error() -> String:
	var error := super.validation_error()
	if not error.is_empty():
		return error
	if spoof_role != "sensor" and spoof_role != "weapon":
		return "디코이의 모방 역할이 올바르지 않습니다"
	return ""

func enemy_knowledge_role() -> StringName:
	return StringName(spoof_role)

func catalog_group() -> StringName:
	return &"decoy"

func is_consumable_decoy() -> bool:
	return true
