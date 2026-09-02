class_name MissileBattery
extends ArmedDefenseUnit

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")

@export var turret_turn_speed_degrees: float = 75.0
@export var firing_alignment_degrees: float = 4.0

var registry: ThreatRegistry
var projectile_parent: Node3D
var cooldown: float = 0.0
var _definition: MissileBatteryDefinition
var interceptors: Array[HomingInterceptor] = []
var magazines: Dictionary[StringName, WeaponMagazine] = {}
var munition_mode: StringName = &"auto"

@onready var turret: Node3D = $Turret
@onready var launch_point: Marker3D = $Turret/Launcher/LaunchPoint

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as MissileBatteryDefinition
	magazines.clear()
	for munition: MissileMunitionDefinition in _definition.munitions:
		var munition_magazine := WeaponMagazine.new()
		munition_magazine.setup(munition.magazine_capacity, munition.reserve_ammunition, munition.reload_duration)
		magazines[munition.id] = munition_magazine
	magazine = magazines[_definition.munitions[0].id]

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
				engagement_coordinator.release(interceptor.target_track.track_id, runtime_id)
			interceptors.remove_at(index)
		else:
			interceptor.gameplay_tick(delta)
	for munition_magazine: WeaponMagazine in magazines.values():
		munition_magazine.gameplay_tick(delta)
	cooldown = maxf(0.0, cooldown - delta)
	var track := select_track(available_tracks(), battlefield.objective.global_position)
	if track == null:
		return
	var is_aimed := _aim_turret(track.estimated_position, delta)
	var munition := munition_for_track(track)
	if is_aimed and munition != null and cooldown <= 0.0 and _active_interceptor_count() < _definition.engagement_channels and engagement_coordinator != null and engagement_coordinator.try_reserve(track.track_id, runtime_id, munition.interceptor_lifetime, munition.salvo_size):
		magazines[munition.id].consume()
		_launch(track, munition)
		cooldown = _definition.fire_interval

func _aim_turret(target_position: Vector3, delta: float) -> bool:
	var direction := target_position - turret.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.01:
		return true
	var desired_yaw := atan2(-direction.x, -direction.z)
	turret.rotation.y = rotate_toward(turret.rotation.y, desired_yaw, deg_to_rad(turret_turn_speed_degrees) * delta)
	return absf(angle_difference(turret.rotation.y, desired_yaw)) <= deg_to_rad(firing_alignment_degrees)

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
		if munition == null or not is_track_available_for_engagement(track, munition.salvo_size):
			continue
		var distance := global_position.distance_to(track.estimated_position)
		if distance > _definition.attack_range * operational_efficiency():
			continue
		if track.track_id == doctrine.priority_track_id:
			return track
		var urgency := track.track_quality * weapon_match(track) / maxf(1.0, track.estimated_position.distance_to(protected_position))
		if urgency > selected_urgency or (is_equal_approx(urgency, selected_urgency) and distance < selected_distance):
			selected = track
			selected_urgency = urgency
			selected_distance = distance
	return selected

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
		if munition.high_cost and munition_magazine.rounds + munition_magazine.reserve <= 1 and track.track_id != doctrine.priority_track_id:
			continue
		var selection_score := match + (0.25 if munition.is_preferred(track.classification, estimated_speed) else 0.0)
		if selection_score > selected_match:
			selected = munition
			selected_match = selection_score
	return selected

func set_munition_mode(mode: StringName) -> void:
	if mode == &"auto" or magazines.has(mode):
		munition_mode = mode

func cycle_munition_mode() -> void:
	var modes: Array[StringName] = [&"auto"]
	for munition: MissileMunitionDefinition in _definition.munitions:
		modes.append(munition.id)
	var index := modes.find(munition_mode)
	munition_mode = modes[(index + 1) % modes.size()]

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
	var lines: Array[String] = [operational_status_text(), "탄종 %s" % munition_mode_text()]
	for munition: MissileMunitionDefinition in _definition.munitions:
		var munition_magazine: WeaponMagazine = magazines[munition.id]
		lines.append("탄약 %s %d + %d" % [munition.display_name, munition_magazine.rounds, munition_magazine.reserve])
	return _with_support_status("\n".join(lines))

func _launch(track: PlayerTrack, munition: MissileMunitionDefinition = null) -> void:
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"missile")
	if munition == null:
		munition = _definition.munitions[0]
	weapon_fired.emit(self, combat_resource_low())
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	projectile_parent.add_child(interceptor)
	interceptor.global_position = launch_point.global_position
	var initial_direction := launch_point.global_position.direction_to(track.estimated_position)
	interceptor.configure(track, registry, munition, initial_direction, runtime_id)
	interceptors.append(interceptor)
	$MuzzleFlash.global_position = launch_point.global_position
	$MuzzleFlash.visible = true
	get_tree().create_timer(0.08).timeout.connect(func() -> void: $MuzzleFlash.visible = false)

func capture_content_state() -> Dictionary:
	var magazine_states: Dictionary = {}
	for munition_id: StringName in magazines:
		magazine_states[String(munition_id)] = magazines[munition_id].capture_state()
	return {
		"cooldown": cooldown,
		"munition_mode": String(munition_mode),
		"munition_magazines": magazine_states,
		"doctrine": capture_doctrine_state(),
	}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	munition_mode = StringName(String(state.get("munition_mode", "auto")))
	var magazine_states: Dictionary = state.get("munition_magazines", {})
	for munition_id: StringName in magazines:
		magazines[munition_id].restore_state(magazine_states.get(String(munition_id), {}))
	restore_doctrine_state(state.get("doctrine", {}))
