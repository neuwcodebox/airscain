class_name AttackUav
extends ThreatUnit

# Runtime paint is immutable. Keep the rendered material alive between spawns,
# including periods with no aircraft of this type on the battlefield.
static var _paint_materials: Dictionary[StandardMaterial3D, Dictionary] = {}

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
	if _definition.mission.acquisition_range > 0.0 and target_asset_value == null and _definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
		mission_runtime.phase = ThreatMissionRuntime.Phase.EGRESS
	elif _definition.mission.acquisition_range > 0.0 and target_asset_value == null:
		_ground_missed_target()

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as AttackUavDefinition
	health = _definition.maximum_health
	_apply_visual_color()

func gameplay_tick(delta: float) -> void:
	if not active or resolved_state:
		return
	var observed_id := mission_runtime.target_defense_id
	if mission_runtime.observe_target(global_position):
		if enemy_knowledge != null:
			enemy_knowledge.discard_estimate_at(observed_id, mission_runtime.fixed_target, _definition.mission.acquisition_range)
		if _definition.mission.type == ThreatMissionDefinition.Type.IMPACT:
			_ground_missed_target()
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
		var preserving_egress_altitude := mission_runtime.phase == ThreatMissionRuntime.Phase.EGRESS
		mover.advance(self, body, target_point, speed_multiplier, delta, preserving_egress_altitude, terminal_committed)
	if _definition.mission.type == ThreatMissionDefinition.Type.IMPACT:
		var building_impact := battlefield.building_segment_impact(previous_position, global_position)
		if _definition.mission.target_role != ThreatMissionDefinition.TargetRole.CITY:
			var terrain_impact := battlefield.terrain_segment_impact(previous_position, global_position)
			if not terrain_impact.is_empty() and (building_impact.is_empty() or previous_position.distance_squared_to(terrain_impact.position) < previous_position.distance_squared_to(building_impact.position)):
				building_impact = terrain_impact
		if not building_impact.is_empty():
			global_position = building_impact.position
			_sample_exhaust(previous_position, global_position)
			if _definition.mission.target_role == ThreatMissionDefinition.TargetRole.CITY:
				objective.apply_building_impact(roundi(_definition.mission.damage), global_position, float(building_impact.building_height))
			else:
				mission_runtime.gameplay_tick(global_position, delta)
			resolve_once(false)
			return
		var impact_point := mission_target + Vector3.UP * 2.0
		var nearest_impact := Geometry3D.get_closest_point_to_segment(impact_point, previous_position, global_position)
		if nearest_impact.distance_to(impact_point) <= _definition.mission.action_distance:
			global_position = nearest_impact
	_sample_exhaust(previous_position, global_position)
	var had_applied_effect := mission_runtime.effect_applied
	var release_decision := ThreatMissionRuntime.ReleaseDecision.USE_DISTANCE
	if _definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
		release_decision = ThreatMissionRuntime.ReleaseDecision.READY if AircraftStrikeRelease.ready(_definition.mission, body.global_transform, mission_target, mover.velocity, delta) else ThreatMissionRuntime.ReleaseDecision.WAIT
	if mission_runtime.gameplay_tick(global_position, delta, release_decision):
		resolve_once(false)
	if not had_applied_effect and mission_runtime.effect_applied and _definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT:
		_update_weapon_store()
		var released := AircraftStrikeRelease.release(get_parent(), body.global_transform, mission_runtime, mission_target, mover.velocity, battlefield, objective)
		if released is ThreatUnit:
			threat_released.emit(released as ThreatUnit)
	if not had_applied_effect and mission_runtime.effect_applied and enemy_knowledge != null and _definition.mission.type == ThreatMissionDefinition.Type.RECONNAISSANCE:
		_record_local_recon()

func _ground_missed_target() -> void:
	var point := mission_runtime.fixed_target
	point.y = battlefield.flight_surface_height(point.x, point.z)
	mission_runtime.fixed_target = point

func _record_local_recon() -> void:
	var anchor := mission_runtime.target_asset
	if not is_instance_valid(anchor):
		return
	for child: Node in anchor.get_parent().get_children():
		var asset := child as DefenseUnit
		if asset != null and asset.active and Vector2(asset.global_position.x - global_position.x, asset.global_position.z - global_position.z).length() <= _definition.mission.action_distance:
			enemy_knowledge.record_recon(asset)

func resolve_once(neutralized: bool) -> bool:
	if resolved_state:
		return false
	_release_exhaust_trail()
	return super.resolve_once(neutralized)

func get_urgency() -> float:
	if objective == null:
		return 0.0
	return 1.0 / maxf(1.0, global_position.distance_to(target_point))

func presentation_action_seconds() -> float:
	if not is_targetable() or mission_runtime.phase == ThreatMissionRuntime.Phase.EGRESS or _definition.mission.released_missile == null:
		return INF
	var offset := mission_runtime.navigation_target() - body.global_transform * AircraftStrikeRelease.HARDPOINT
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	var forward := Vector3(mover.velocity.x, 0.0, mover.velocity.z)
	if forward.length_squared() < 1.0 or forward.normalized().dot(horizontal.normalized()) < cos(deg_to_rad(_definition.mission.launch_cone_degrees)):
		return INF
	var closing_speed := forward.dot(horizontal.normalized())
	return maxf(0.0, horizontal.length() - _definition.mission.action_distance) / closing_speed

func presentation_action_completed() -> bool:
	return mission_runtime.effect_applied

func presentation_velocity() -> Vector3:
	return mover.velocity

func exits_without_impact() -> bool:
	return mission_runtime.phase == ThreatMissionRuntime.Phase.EGRESS

func impact_uses_objective_audio() -> bool:
	return _definition.mission.type == ThreatMissionDefinition.Type.IMPACT and _definition.mission.target_role == ThreatMissionDefinition.TargetRole.CITY

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
	_update_weapon_store()

func _apply_visual_color() -> void:
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var source := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
			if source == null:
				source = mesh_instance.material_override as StandardMaterial3D
			if not _paint_materials.has(source):
				_paint_materials[source] = {}
			var paints: Dictionary = _paint_materials[source]
			if not paints.has(_definition.visual_color):
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color = _definition.visual_color
				material.vertex_color_use_as_albedo = false
				paints[_definition.visual_color] = material
			mesh_instance.material_override = paints[_definition.visual_color]

func _sample_exhaust(from_position: Vector3, to_position: Vector3) -> void:
	for child: Node in body.get_children():
		if child is LingeringSmokeTrail:
			(child as LingeringSmokeTrail).sample_world_segment(from_position, to_position)

func _release_exhaust_trail() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child: Node in body.get_children():
		if child is LingeringSmokeTrail:
			(child as LingeringSmokeTrail).release_to(parent)


func _update_weapon_store() -> void:
	if body.has_method("set_weapon_released"):
		body.call("set_weapon_released", _definition.mission.type == ThreatMissionDefinition.Type.STRIKE_AND_EXIT and mission_runtime.effect_applied)
