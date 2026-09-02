class_name DefenseUnit
extends Node3D

signal damage_received(unit: DefenseUnit, amount: float, integrity_ratio: float)
signal weapon_fired(unit: DefenseUnit, low_resources: bool)

const DAMAGE_SMOKE_SCENE := preload("res://effects/damage_smoke/damage_smoke.tscn")
const STATUS_MARKER_SCENE := preload("res://effects/unit_status_marker/unit_status_marker.tscn")
const IDENTITY_MARKER_SCENE := preload("res://effects/unit_identity_marker/unit_identity_marker.tscn")
const PRESENTATION_SCALE := 0.9

enum C2Role { SENSOR = 1, COMMAND = 2, DEFENSE = 4, RELAY = 8 }

var runtime_id: int
var definition: DefenseDefinition
var active: bool = true
var integrity: float
var support_manager: SupportManager
var relocation_manager: RelocationManager
var enemy_knowledge: EnemyKnowledge
var damage_smoke: Node
var status_marker: Node3D
var identity_marker: Node3D

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	scale = Vector3.ONE * PRESENTATION_SCALE
	runtime_id = id_value
	definition = definition_value
	integrity = definition.maximum_integrity
	active = true
	_ensure_identity_marker()
	_ensure_status_marker()
	_refresh_damage_visual()
	_refresh_status_marker()

func _process(_delta: float) -> void:
	_refresh_status_marker()

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

func combat_resource_low() -> bool:
	return false

func critical_status_text() -> String:
	if not active:
		return "×"
	if operational_ratio() < 0.75:
		return "손상"
	return ""

func receive_damage(amount: float) -> bool:
	if amount <= 0.0 or integrity <= 0.0:
		return false
	integrity = maxf(0.0, integrity - amount)
	active = operational_ratio() >= 0.35
	_refresh_damage_visual()
	damage_received.emit(self, amount, operational_ratio())
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
	_refresh_damage_visual()

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
	_refresh_damage_visual()
	restore_content_state(state.get("content_state", {}))

func restore_content_state(_state: Dictionary) -> void:
	pass

func _refresh_damage_visual() -> void:
	if definition == null:
		return
	var damage_ratio := 1.0 - operational_ratio()
	if damage_ratio < 0.25:
		if damage_smoke != null and is_instance_valid(damage_smoke):
			damage_smoke.free()
		damage_smoke = null
		return
	if damage_smoke == null or not is_instance_valid(damage_smoke):
		damage_smoke = DAMAGE_SMOKE_SCENE.instantiate()
		add_child(damage_smoke)
	damage_smoke.call("set_damage_ratio", damage_ratio)

func _ensure_status_marker() -> void:
	if status_marker != null and is_instance_valid(status_marker):
		return
	status_marker = STATUS_MARKER_SCENE.instantiate() as Node3D
	add_child(status_marker)
	status_marker.position = Vector3(0.0, 20.0, 0.0)

func _ensure_identity_marker() -> void:
	if identity_marker != null and is_instance_valid(identity_marker):
		return
	identity_marker = IDENTITY_MARKER_SCENE.instantiate() as Node3D
	add_child(identity_marker)
	identity_marker.position = Vector3(0.0, 14.0, 0.0)
	identity_marker.call("set_role", c2_roles())

func _refresh_status_marker() -> void:
	if definition == null:
		return
	_ensure_status_marker()
	var message := critical_status_text()
	var color := Color("ff4b32") if not active else Color("ffb02e")
	status_marker.call("set_status", message, color)
