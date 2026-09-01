class_name MissileBattery
extends ArmedDefenseUnit

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")

var registry: ThreatRegistry
var projectile_parent: Node3D
var cooldown: float = 0.0
var _definition: MissileBatteryDefinition
var interceptors: Array[HomingInterceptor] = []

@onready var turret: Node3D = $Turret
@onready var launch_point: Marker3D = $Turret/LaunchPoint

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as MissileBatteryDefinition
	magazine.setup(_definition.magazine_capacity, _definition.reserve_ammunition, _definition.reload_duration)

func configure_combat(registry_value: ThreatRegistry, projectile_parent_value: Node3D) -> void:
	registry = registry_value
	projectile_parent = projectile_parent_value

func c2_link_range() -> float:
	return _definition.c2_range

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
	magazine.gameplay_tick(delta)
	cooldown = maxf(0.0, cooldown - delta)
	var track := select_track(available_tracks(), battlefield.objective.global_position)
	if track == null:
		return
	var flat_target := Vector3(track.estimated_position.x, turret.global_position.y, track.estimated_position.z)
	if turret.global_position.distance_squared_to(flat_target) > 0.01:
		turret.look_at(flat_target, Vector3.UP)
	if cooldown <= 0.0 and magazine.can_fire() and engagement_coordinator != null and engagement_coordinator.try_reserve(track.track_id, runtime_id, _definition.interceptor_lifetime):
		magazine.consume()
		_launch(track)
		cooldown = _definition.fire_interval

func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
	var selected: PlayerTrack
	var selected_urgency := -INF
	var selected_distance := INF
	for track: PlayerTrack in tracks:
		if not doctrine.allows(track) or not is_track_available_for_engagement(track):
			continue
		var distance := global_position.distance_to(track.estimated_position)
		if distance > _definition.attack_range:
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
	return _definition.small_target_match if track.classification == &"small_uav" else 1.0

func resupply_cost() -> int:
	return _definition.resupply_cost

func resupply_work() -> float:
	return _definition.resupply_work

func _launch(track: PlayerTrack) -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	projectile_parent.add_child(interceptor)
	interceptor.global_position = launch_point.global_position
	var initial_direction := launch_point.global_position.direction_to(track.estimated_position)
	interceptor.configure(track, registry, _definition, initial_direction, runtime_id)
	interceptors.append(interceptor)
	$MuzzleFlash.global_position = launch_point.global_position
	$MuzzleFlash.visible = true
	get_tree().create_timer(0.08).timeout.connect(func() -> void: $MuzzleFlash.visible = false)

func capture_content_state() -> Dictionary:
	return {
		"cooldown": cooldown,
		"magazine": magazine.capture_state(),
		"doctrine": capture_doctrine_state(),
	}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	magazine.restore_state(state.get("magazine", {}))
	restore_doctrine_state(state.get("doctrine", {}))
