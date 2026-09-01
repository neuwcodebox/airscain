class_name AttackUav
extends ThreatUnit

var objective: ProtectedObjective
var battlefield: Battlefield
var target_point: Vector3
var speed_multiplier: float = 1.0
var mover := ThreatMover.new()
var mission_runtime := ThreatMissionRuntime.new()
var _definition: AttackUavDefinition

@onready var body: Node3D = $Body

func configure_mission(objective_value: ProtectedObjective, battlefield_value: Battlefield, target_value: Vector3, pressure_multiplier: float, target_asset_value: DefenseUnit = null, exit_point_value: Vector3 = Vector3.ZERO) -> void:
	objective = objective_value
	battlefield = battlefield_value
	target_point = target_value
	speed_multiplier = pressure_multiplier
	mover.setup(_definition.movement, battlefield, global_position.direction_to(target_point))
	mission_runtime.setup(_definition.mission, objective, target_point, target_asset_value, exit_point_value)

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as AttackUavDefinition
	health = _definition.maximum_health
	_apply_visual_color()

func gameplay_tick(delta: float) -> void:
	if not active or resolved_state:
		return
	target_point = mission_runtime.navigation_target()
	var holding_for_recon := _definition.mission.type == ThreatMissionDefinition.Type.RECONNAISSANCE and mission_runtime.phase == ThreatMissionRuntime.Phase.ACTING
	if not holding_for_recon:
		mover.advance(self, body, target_point, speed_multiplier, delta)
	var had_applied_effect := mission_runtime.effect_applied
	if mission_runtime.gameplay_tick(global_position, delta):
		resolve_once(false)
	if not had_applied_effect and mission_runtime.effect_applied and enemy_knowledge != null and _definition.mission.type == ThreatMissionDefinition.Type.RECONNAISSANCE:
		enemy_knowledge.record_recon(mission_runtime.target_asset)

func get_urgency() -> float:
	if objective == null:
		return 0.0
	return 1.0 / maxf(1.0, global_position.distance_to(target_point))

func capture_content_state() -> Dictionary:
	return {
		"target_point": SaveDocument.vector3_to_data(target_point),
		"speed_multiplier": speed_multiplier,
		"movement": mover.capture_state(),
		"mission": mission_runtime.capture_state(),
	}

func restore_content_state(state: Dictionary, objective_value: ProtectedObjective, battlefield_value: Battlefield, defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	objective = objective_value
	battlefield = battlefield_value
	target_point = SaveDocument.vector3_from_data(state.get("target_point", []))
	speed_multiplier = float(state.get("speed_multiplier", 1.0))
	mover.restore_state(state.get("movement", {}), _definition.movement, battlefield)
	mission_runtime.restore_state(state.get("mission", {}), _definition.mission, objective, defense_by_id)

func _apply_visual_color() -> void:
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
			material.albedo_color = _definition.visual_color
			mesh_instance.material_override = material
