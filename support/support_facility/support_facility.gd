class_name SupportFacility
extends DefenseUnit

var _definition: SupportFacilityDefinition

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as SupportFacilityDefinition

func support_capacity() -> float:
	return _definition.work_capacity * operational_efficiency()

func support_slots() -> int:
	return _definition.concurrent_tasks if active else 0

func service_range() -> float:
	return _definition.service_range

func supports_position(position: Vector3) -> bool:
	var offset := Vector2(position.x - global_position.x, position.z - global_position.z)
	return active and support_capacity() > 0.0 and offset.length() <= service_range()

func power_capacity() -> float:
	return _definition.power_capacity * operational_efficiency()

func resource_status_text() -> String:
	var status := "%s\n지원 %.1f · 동시 %d · 전력 %.1f" % [operational_status_text(), support_capacity(), support_slots(), power_capacity()]
	if support_manager != null and not support_manager.task_status(self).is_empty():
		status += " · %s" % support_manager.task_status(self)
	return status

func configure_support(manager: SupportManager) -> void:
	super.configure_support(manager)
