class_name SupportFacility
extends DefenseUnit

var _definition: SupportFacilityDefinition

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as SupportFacilityDefinition

func support_capacity() -> float:
	return _definition.work_capacity if active else 0.0

func support_slots() -> int:
	return _definition.concurrent_tasks if active else 0

func resource_status_text() -> String:
	return "지원 처리량 %.1f · 동시 작업 %d" % [support_capacity(), support_slots()]
