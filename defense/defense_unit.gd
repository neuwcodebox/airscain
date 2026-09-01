class_name DefenseUnit
extends Node3D

var runtime_id: int
var definition: DefenseDefinition
var active: bool = true

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	runtime_id = id_value
	definition = definition_value

func gameplay_tick(_delta: float) -> void:
	pass

func configure_combat(_registry: ThreatRegistry, _projectile_parent: Node3D) -> void:
	pass
