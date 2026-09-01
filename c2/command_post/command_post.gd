class_name CommandPost
extends DefenseUnit

var _definition: CommandPostDefinition

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as CommandPostDefinition

func c2_roles() -> int:
	return C2Role.COMMAND

func c2_link_range() -> float:
	return _definition.link_range * operational_efficiency()
