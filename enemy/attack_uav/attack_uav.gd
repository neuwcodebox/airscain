class_name AttackUav
extends ThreatUnit

const STRIKE_MUNITION_SCENE := preload("res://effects/air_strike_munition/air_strike_munition.tscn")

var objective: ProtectedObjective
var battlefield: Battlefield
var target_point: Vector3
var speed_multiplier: float = 1.0
var orbit_angle: float = 0.0
var mover := ThreatMover.new()
var mission_runtime := ThreatMissionRuntime.new()
var _definition: AttackUavDefinition
var terminal_committed: bool = false

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
	var mission_target := mission_runtime.navigation_target()
	target_point = mission_target
	var previous_position := global_position
	if _definition.mission.type == ThreatMissionDefinition.Type.IMPACT and Vector2(target_point.x - global_position.x, target_point.z - global_position.z).length() <= _definition.movement.terminal_distance:
		terminal_committed = true
	var holding_for_recon := _definition.mission.type == ThreatMissionDefinition.Type.RECONNAISSANCE and mission_runtime.phase == ThreatMissionRuntime.Phase.ACTING
	if holding_for_recon:
		orbit_angle = fposmod(orbit_angle + delta * 0.45, TAU)
		var orbit_radius := clampf(_definition.mission.action_distance * 0.82, 45.0, 320.0)
		var orbit_target := mission_target + Vector3(cos(orbit_angle) * orbit_radius, _definition.movement.cruise_altitude, sin(orbit_angle) * orbit_radius)
		mover.advance(self, body, orbit_target, speed_multiplier, delta, true)
	else:
		mover.advance(self, body, target_point, speed_multiplier, delta, false, terminal_committed)
	if _definition.mission.type == ThreatMissionDefinition.Type.IMPACT:
		var impact_point := mission_target + Vector3.UP * 2.0
		var nearest_impact := Geometry3D.get_closest_point_to_segment(impact_point, previous_position, global_position)
		if nearest_impact.distance_to(impact_point) <= _definition.mission.action_distance:
			global_position = nearest_impact
	_sample_exhaust(previous_position, global_position)
	var had_applied_effect := mission_runtime.effect_applied
	if mission_runtime.gameplay_tick(global_position, delta):
		resolve_once(false)
	if not had_applied_effect and mission_runtime.effect_applied and _definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
		_spawn_strike_munition(mission_target)
	if not had_applied_effect and mission_runtime.effect_applied and enemy_knowledge != null and _definition.mission.type == ThreatMissionDefinition.Type.RECONNAISSANCE:
		enemy_knowledge.record_recon(mission_runtime.target_asset)

func resolve_once(neutralized: bool) -> bool:
	if resolved_state:
		return false
	_release_exhaust_trail()
	return super.resolve_once(neutralized)

func get_urgency() -> float:
	if objective == null:
		return 0.0
	return 1.0 / maxf(1.0, global_position.distance_to(target_point))

func presentation_velocity() -> Vector3:
	return mover.velocity

func capture_content_state() -> Dictionary:
	return {
		"target_point": SaveDocument.vector3_to_data(target_point),
		"speed_multiplier": speed_multiplier,
		"orbit_angle": orbit_angle,
		"movement": mover.capture_state(),
		"mission": mission_runtime.capture_state(),
		"terminal_committed": terminal_committed,
	}

func restore_content_state(state: Dictionary, objective_value: ProtectedObjective, battlefield_value: Battlefield, defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	objective = objective_value
	battlefield = battlefield_value
	target_point = SaveDocument.vector3_from_data(state.get("target_point", []))
	speed_multiplier = float(state.get("speed_multiplier", 1.0))
	orbit_angle = float(state.get("orbit_angle", 0.0))
	mover.restore_state(state.get("movement", {}), _definition.movement, battlefield)
	mission_runtime.restore_state(state.get("mission", {}), _definition.mission, objective, defense_by_id)
	terminal_committed = bool(state.get("terminal_committed", false))

func _apply_visual_color() -> void:
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
			material.albedo_color = _definition.visual_color
			mesh_instance.material_override = material

func _sample_exhaust(from_position: Vector3, to_position: Vector3) -> void:
	for child: Node in body.get_children():
		if child is GPUParticles3D and child.has_method("sample_world_segment"):
			child.call("sample_world_segment", from_position, to_position)

func _release_exhaust_trail() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child: Node in body.get_children():
		if child is GPUParticles3D and child.has_method("release_to"):
			child.call("release_to", parent)

func _spawn_strike_munition(strike_target: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var munition := STRIKE_MUNITION_SCENE.instantiate() as Node3D
	parent.add_child(munition)
	munition.global_position = global_position
	munition.call("setup", strike_target)
