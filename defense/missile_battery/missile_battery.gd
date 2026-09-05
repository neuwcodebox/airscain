class_name MissileBattery
extends ArmedDefenseUnit

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")
const TURRET_AIMER := preload("res://defense/turret_aimer.gd")

@export var turret_turn_speed_degrees: float = 75.0
@export var launcher_elevation_speed_degrees: float = 55.0
@export var launch_sector_degrees: float = 30.0

var registry: ThreatRegistry
var projectile_parent: Node3D
var launch_cooldown: float = 0.0
var _definition: MissileBatteryDefinition
var interceptors: Array[HomingInterceptor] = []
var magazines: Dictionary[StringName, WeaponMagazine] = {}
var munition_mode: StringName = &"auto"
var next_launch_sequence: int = 0

@onready var turret: Node3D = $Turret
@onready var elevation: Node3D = $Turret/Elevation
@onready var launch_point: Marker3D = $Turret/Elevation/Launcher/LaunchPoint

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as MissileBatteryDefinition
	next_launch_sequence = 0
	magazines.clear()
	for munition: MissileMunitionDefinition in _definition.munitions:
		var munition_magazine := WeaponMagazine.new()
		munition_magazine.setup(munition.magazine_capacity, munition.reserve_ammunition, munition.reload_duration)
		magazines[munition.id] = munition_magazine
	magazine = magazines[_definition.munitions[0].id]
	_refresh_launcher_cells()

func configure_combat(registry_value: ThreatRegistry, projectile_parent_value: Node3D) -> void:
	registry = registry_value
	projectile_parent = projectile_parent_value

func c2_link_range() -> float:
	return _definition.c2_range * operational_efficiency()

func gameplay_tick(delta: float) -> void:
	if not active or registry == null or player_knowledge == null or c2_network == null:
		return
	for index: int in range(interceptors.size() - 1, -1, -1):
		var interceptor := interceptors[index]
		if not is_instance_valid(interceptor) or interceptor.is_queued_for_deletion():
			if engagement_coordinator != null and is_instance_valid(interceptor) and interceptor.target_track != null:
				engagement_coordinator.release_one(interceptor.target_track.track_id, runtime_id)
			interceptors.remove_at(index)
		else:
			interceptor.gameplay_tick(delta)
	for munition_magazine: WeaponMagazine in magazines.values():
		munition_magazine.gameplay_tick(delta)
	_refresh_launcher_cells()
	launch_cooldown = maxf(0.0, launch_cooldown - delta)
	var track := select_track(available_tracks(), battlefield.objective.global_position)
	if track == null:
		return
	var is_aimed := _aim_turret(track.estimated_position, delta)
	var munition := munition_for_track(track)
	if is_aimed and munition != null and launch_cooldown <= 0.0 and _active_interceptor_count() < _definition.engagement_channels and engagement_coordinator != null and engagement_coordinator.try_reserve(track.track_id, runtime_id, munition.interceptor_lifetime, engagement_limit()):
		if _fire_round(track, munition):
			launch_cooldown = _definition.launch_interval
		else:
			engagement_coordinator.release_one(track.track_id, runtime_id)

func _aim_turret(target_position: Vector3, delta: float) -> bool:
	var target_direction := launch_point.global_position.direction_to(target_position)
	if target_direction.length_squared() <= 0.001 or launcher_forward().angle_to(target_direction) <= deg_to_rad(launch_sector_degrees):
		return true
	return TURRET_AIMER.aim(turret, elevation, target_position, turret_turn_speed_degrees, launcher_elevation_speed_degrees, launch_sector_degrees, delta, 4.0, 75.0)

func launcher_forward() -> Vector3:
	return -launch_point.global_basis.z.normalized()

func _active_interceptor_count() -> int:
	var result := 0
	for interceptor: HomingInterceptor in interceptors:
		if is_instance_valid(interceptor) and not interceptor.is_queued_for_deletion():
			result += 1
	return result

func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
	var selected: PlayerTrack
	var selected_urgency := -INF
	var selected_distance := INF
	for track: PlayerTrack in tracks:
		if not doctrine.allows(track):
			continue
		var munition := munition_for_track(track)
		if munition == null or not is_track_available_for_engagement(track, engagement_limit()):
			continue
		var distance := global_position.distance_to(track.estimated_position)
		if distance > _definition.attack_range * operational_efficiency():
			continue
		var altitude := track.estimated_position.y - battlefield.terrain_height(track.estimated_position.x, track.estimated_position.z) if battlefield != null else track.estimated_position.y
		if altitude < _definition.minimum_engagement_altitude or altitude > _definition.maximum_engagement_altitude:
			continue
		if track.track_id == doctrine.priority_track_id:
			return track
		var urgency := track.track_quality * weapon_match(track) / maxf(1.0, track.estimated_position.distance_to(protected_position))
		if urgency > selected_urgency or (is_equal_approx(urgency, selected_urgency) and distance < selected_distance):
			selected = track
			selected_urgency = urgency
			selected_distance = distance
	return selected

func engagement_limit() -> int:
	return _definition.maximum_interceptors_per_track

func weapon_match(track: PlayerTrack) -> float:
	var munition := munition_for_track(track)
	return munition.match_for(track.classification, track.estimated_velocity.length()) if munition != null else 0.0

func munition_for_track(track: PlayerTrack) -> MissileMunitionDefinition:
	var selected: MissileMunitionDefinition
	var selected_match := -1.0
	var estimated_speed := track.estimated_velocity.length()
	for munition: MissileMunitionDefinition in _definition.munitions:
		if munition_mode != &"auto" and munition.id != munition_mode:
			continue
		var munition_magazine: WeaponMagazine = magazines[munition.id]
		if not munition_magazine.can_fire():
			continue
		var match := munition.match_for(track.classification, estimated_speed)
		if match <= 0.0:
			continue
		if _preserves_last_round(munition) and not munition.is_preferred(track.classification, estimated_speed) and track.track_id != doctrine.priority_track_id:
			continue
		var selection_score := match + (0.25 if munition.is_preferred(track.classification, estimated_speed) else 0.0)
		if selection_score > selected_match:
			selected = munition
			selected_match = selection_score
	return selected

func _preserves_last_round(munition: MissileMunitionDefinition) -> bool:
	var stock: WeaponMagazine = magazines[munition.id]
	return munition_mode == &"auto" and munition.high_cost and stock.rounds + stock.reserve == 1

func combat_resource_depleted() -> bool:
	if magazines.is_empty():
		return false
	for stock: WeaponMagazine in magazines.values():
		if not stock.is_depleted():
			return false
	return true

func critical_status_text() -> String:
	var status := super.critical_status_text()
	if not status.is_empty():
		return status
	for stock: WeaponMagazine in magazines.values():
		if stock.is_depleted():
			return "일부 탄종 고갈"
	return ""

func set_munition_mode(mode: StringName) -> void:
	if mode == &"auto" or magazines.has(mode):
		munition_mode = mode

func cycle_munition_mode() -> void:
	var modes: Array[StringName] = [&"auto"]
	for munition: MissileMunitionDefinition in _definition.munitions:
		modes.append(munition.id)
	var index := modes.find(munition_mode)
	munition_mode = modes[(index + 1) % modes.size()]

func supports_munition_selection() -> bool:
	return _definition != null and _definition.munitions.size() > 1

func munition_mode_text() -> String:
	if munition_mode == &"auto":
		return "자동"
	for munition: MissileMunitionDefinition in _definition.munitions:
		if munition.id == munition_mode:
			return munition.display_name
	return "자동"

func resupply_cost() -> int:
	var result := 0
	for munition: MissileMunitionDefinition in _definition.munitions:
		if magazines[munition.id].reserve < magazines[munition.id].reserve_capacity:
			result += munition.resupply_cost
	return result

func uses_ammunition() -> bool:
	return true

func resupply_work() -> float:
	var result := 0.0
	for munition: MissileMunitionDefinition in _definition.munitions:
		if magazines[munition.id].reserve < magazines[munition.id].reserve_capacity:
			result += munition.resupply_work
	return maxf(1.0, result)

func ammunition_needs_resupply() -> bool:
	for munition_magazine: WeaponMagazine in magazines.values():
		if munition_magazine.reserve < munition_magazine.reserve_capacity:
			return true
	return false

func ammunition_reserve_ratio() -> float:
	var result := 1.0
	for munition_magazine: WeaponMagazine in magazines.values():
		result = minf(result, float(munition_magazine.reserve) / maxf(1.0, float(munition_magazine.reserve_capacity)))
	return result

func complete_resupply() -> void:
	for munition_magazine: WeaponMagazine in magazines.values():
		munition_magazine.refill_reserve()

func resource_status_text() -> String:
	var lines: Array[String] = [operational_status_text(), "교전 고도 %d–%dm" % [roundi(_definition.minimum_engagement_altitude), roundi(_definition.maximum_engagement_altitude)], "탄종 %s" % munition_mode_text()]
	for munition: MissileMunitionDefinition in _definition.munitions:
		var munition_magazine: WeaponMagazine = magazines[munition.id]
		var reload_text := " · 재장전 %.1f초" % munition_magazine.reload_remaining if munition_magazine.is_reloading() else ""
		lines.append("탄약 %s %d + %d%s" % [munition.display_name, munition_magazine.rounds, munition_magazine.reserve, reload_text])
	return _with_support_status("\n".join(lines))

func selection_status_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"label": "교전 고도", "value": "%d–%dm" % [roundi(_definition.minimum_engagement_altitude), roundi(_definition.maximum_engagement_altitude)]},
		{"label": "탄종", "value": munition_mode_text()},
	]
	for munition: MissileMunitionDefinition in _definition.munitions:
		var munition_magazine: WeaponMagazine = magazines[munition.id]
		var ammunition := "%d + %d" % [munition_magazine.rounds, munition_magazine.reserve]
		if munition_magazine.is_depleted():
			ammunition = "고갈"
		rows.append({"label": munition.display_name, "value": ammunition, "warning": munition_magazine.is_depleted()})
		if _preserves_last_round(munition):
			rows.append({"label": "최후 1발", "value": "우선 위협·우선표적용", "warning": true})
		if munition_magazine.is_reloading():
			rows.append({"label": "재장전", "value": "%.1f초" % munition_magazine.reload_remaining})
	rows.append_array(_selection_task_rows())
	return rows

func _spawn_interceptor(track: PlayerTrack, munition: MissileMunitionDefinition, launch_sequence: int, lateral_offset: float) -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	projectile_parent.add_child(interceptor)
	interceptor.global_position = launch_point.global_position + launch_point.global_basis.x * lateral_offset
	var initial_direction := launcher_forward()
	interceptor.configure(track, registry, munition, initial_direction, runtime_id, launch_sequence, available_tracks(), battlefield)
	interceptor.target_changed.connect(_on_interceptor_target_changed)
	interceptors.append(interceptor)
	projectile_launched.emit(self, interceptor)

func _on_interceptor_target_changed(previous_track_id: int, new_track_id: int, remaining_lifetime: float) -> void:
	if engagement_coordinator == null:
		return
	engagement_coordinator.release_one(previous_track_id, runtime_id)
	engagement_coordinator.try_reserve(new_track_id, runtime_id, remaining_lifetime, 99)

func _show_muzzle_flash() -> void:
	$MuzzleFlash.global_position = launch_point.global_position
	$MuzzleFlash.visible = true
	get_tree().create_timer(0.08).timeout.connect(func() -> void: $MuzzleFlash.visible = false)

func _fire_round(track: PlayerTrack, munition: MissileMunitionDefinition) -> bool:
	if track == null or munition == null:
		return false
	var cell_index := maxi(0, _launcher_caps().size() - mini(_ready_round_count(), _launcher_caps().size()))
	if not magazines[munition.id].consume():
		return false
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"missile")
	weapon_fired.emit(self, combat_resource_low())
	var lateral_offset := _cell_lateral_offset(cell_index) if not _launcher_caps().is_empty() else 0.0
	_spawn_interceptor(track, munition, next_launch_sequence, lateral_offset)
	next_launch_sequence += 1
	_show_muzzle_flash()
	_refresh_launcher_cells()
	return true

func _launcher_caps() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var caps_parent := find_child("MuzzleCaps", true, false)
	if caps_parent == null:
		return result
	for child: Node in caps_parent.get_children():
		if child is Node3D:
			result.append(child as Node3D)
	return result

func _cell_lateral_offset(cell_index: int) -> float:
	var caps := _launcher_caps()
	if caps.is_empty():
		return 0.0
	var cap := caps[cell_index % caps.size()]
	return launch_point.global_basis.x.dot(cap.global_position - launch_point.global_position)

func _refresh_launcher_cells() -> void:
	var caps := _launcher_caps()
	var visible_cells := mini(_ready_round_count(), caps.size())
	for index: int in caps.size():
		caps[index].visible = index < visible_cells

func _ready_round_count() -> int:
	var result := 0
	for munition_magazine: WeaponMagazine in magazines.values():
		result += munition_magazine.rounds
	return result

func capture_content_state() -> Dictionary:
	var magazine_states: Dictionary = {}
	for munition_id: StringName in magazines:
		magazine_states[String(munition_id)] = magazines[munition_id].capture_state()
	return {
		"launch_cooldown": launch_cooldown,
		"next_launch_sequence": next_launch_sequence,
		"munition_mode": String(munition_mode),
		"munition_magazines": magazine_states,
		"doctrine": capture_doctrine_state(),
	}

func restore_content_state(state: Dictionary) -> void:
	var saved_cooldown := float(state.get("launch_cooldown", state.get("cooldown", 0.0)))
	launch_cooldown = clampf(saved_cooldown, 0.0, _definition.launch_interval)
	next_launch_sequence = int(state.get("next_launch_sequence", 0))
	munition_mode = StringName(String(state.get("munition_mode", "auto")))
	var magazine_states: Dictionary = state.get("munition_magazines", {})
	for munition_id: StringName in magazines:
		magazines[munition_id].restore_state(magazine_states.get(String(munition_id), {}))
	_refresh_launcher_cells()
	restore_doctrine_state(state.get("doctrine", {}))
