class_name DefenseUnit
extends Node3D

enum C2Role { SENSOR = 1, COMMAND = 2, DEFENSE = 4, RELAY = 8 }

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

func configure_player_knowledge(_battlefield: Battlefield, _player_knowledge: Node) -> void:
	pass

func configure_c2(_network: Node) -> void:
	pass

func configure_engagements(_coordinator: EngagementCoordinator) -> void:
	pass

func configure_support(_manager: SupportManager) -> void:
	pass

func c2_roles() -> int:
	return 0

func c2_link_range() -> float:
	return 0.0

func local_sensor_ids() -> Array[int]:
	return []

func resource_status_text() -> String:
	return ""

func capture_state() -> Dictionary:
	return {
		"definition_id": String(definition.id),
		"runtime_id": runtime_id,
		"position": SaveDocument.vector3_to_data(global_position),
		"active": active,
		"content_state": capture_content_state(),
	}

func capture_content_state() -> Dictionary:
	return {}

func restore_state(state: Dictionary) -> void:
	active = bool(state.active)
	restore_content_state(state.get("content_state", {}))

func restore_content_state(_state: Dictionary) -> void:
	pass
