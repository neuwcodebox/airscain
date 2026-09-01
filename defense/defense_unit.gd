class_name DefenseUnit
extends Node3D

enum C2Role { SENSOR = 1, COMMAND = 2, DEFENSE = 4, RELAY = 8 }

var runtime_id: int
var definition: DefenseDefinition
var active: bool = true
var integrity: float
var support_manager: SupportManager
var relocation_manager: RelocationManager
var enemy_knowledge: EnemyKnowledge

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	runtime_id = id_value
	definition = definition_value
	integrity = definition.maximum_integrity
	active = true

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

func configure_support(manager: SupportManager) -> void:
	support_manager = manager

func configure_power(_manager: PowerManager) -> void:
	pass

func configure_relocation(manager: RelocationManager) -> void:
	relocation_manager = manager

func configure_enemy_knowledge(knowledge: EnemyKnowledge) -> void:
	enemy_knowledge = knowledge

func c2_roles() -> int:
	return 0

func c2_link_range() -> float:
	return 0.0

func local_sensor_ids() -> Array[int]:
	return []

func resource_status_text() -> String:
	var status := operational_status_text()
	if support_manager != null and not support_manager.task_status(self).is_empty():
		status += " · %s" % support_manager.task_status(self)
	if relocation_manager != null and not relocation_manager.task_status(self).is_empty():
		status += " · %s" % relocation_manager.task_status(self)
	return status

func receive_damage(amount: float) -> bool:
	if amount <= 0.0 or integrity <= 0.0:
		return false
	integrity = maxf(0.0, integrity - amount)
	active = operational_ratio() >= 0.35
	return true

func operational_ratio() -> float:
	return clampf(integrity / definition.maximum_integrity, 0.0, 1.0)

func operational_efficiency() -> float:
	return operational_ratio() if active else 0.0

func operational_status_text() -> String:
	var ratio := operational_ratio()
	if ratio >= 0.75:
		return "상태 정상 · 내구도 %d%%" % roundi(ratio * 100.0)
	if active:
		return "상태 성능저하 · 내구도 %d%%" % roundi(ratio * 100.0)
	if integrity > 0.0:
		return "상태 기능정지 · 내구도 %d%%" % roundi(ratio * 100.0)
	return "상태 파괴"

func repair_cost() -> int:
	return definition.repair_cost

func repair_work() -> float:
	return definition.repair_work * (1.0 - operational_ratio())

func can_request_repair() -> bool:
	return support_manager != null and integrity > 0.0 and integrity < definition.maximum_integrity and support_manager.task_status(self).is_empty()

func request_repair() -> bool:
	return support_manager != null and support_manager.request_repair(self)

func can_request_relocation() -> bool:
	return definition.mobile and active and relocation_manager != null and relocation_manager.task_status(self).is_empty() and (support_manager == null or support_manager.task_status(self).is_empty())

func complete_repair() -> void:
	integrity = definition.maximum_integrity
	active = true

func capture_state() -> Dictionary:
	return {
		"definition_id": String(definition.id),
		"runtime_id": runtime_id,
		"position": SaveDocument.vector3_to_data(global_position),
		"active": active,
		"integrity": integrity,
		"content_state": capture_content_state(),
	}

func capture_content_state() -> Dictionary:
	return {}

func restore_state(state: Dictionary) -> void:
	integrity = float(state.integrity)
	active = bool(state.active) and operational_ratio() >= 0.35
	restore_content_state(state.get("content_state", {}))

func restore_content_state(_state: Dictionary) -> void:
	pass
