class_name InterceptorDroneDefense
extends ArmedDefenseUnit

const DRONE_SCENE := preload("res://defense/interceptor_drone/interceptor_drone.tscn")

var registry: ThreatRegistry
var projectile_parent: Node3D
var available_drones: int
var recharge_queue: Array[float] = []
var active_drones: Array[InterceptorDrone] = []
var cooldown: float = 0.0
var _definition: InterceptorDroneDefenseDefinition

@onready var launch_point: Marker3D = $LaunchPoint

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as InterceptorDroneDefenseDefinition
	available_drones = _definition.drone_count

func configure_combat(registry_value: ThreatRegistry, projectile_parent_value: Node3D) -> void:
	registry = registry_value
	projectile_parent = projectile_parent_value

func c2_link_range() -> float:
	return _definition.c2_range * operational_efficiency()

func drone_definition() -> InterceptorDroneDefenseDefinition:
	return _definition

func gameplay_tick(delta: float) -> void:
	for index: int in range(active_drones.size() - 1, -1, -1):
		var drone := active_drones[index]
		if not is_instance_valid(drone) or drone.is_queued_for_deletion():
			active_drones.remove_at(index)
		else:
			drone.gameplay_tick(delta)
	for index: int in range(recharge_queue.size() - 1, -1, -1):
		recharge_queue[index] -= delta
		if recharge_queue[index] <= 0.0:
			recharge_queue.remove_at(index)
			available_drones = mini(_definition.drone_count, available_drones + 1)
	cooldown = maxf(0.0, cooldown - delta)
	if not active or available_drones <= 0 or active_drones.size() >= _definition.engagement_channels:
		return
	var track := _select_track()
	if track != null and cooldown <= 0.0 and engagement_coordinator != null and engagement_coordinator.try_reserve(track.track_id, runtime_id, _definition.drone_endurance):
		_launch(track)
		cooldown = _definition.launch_interval

func _select_track() -> PlayerTrack:
	for track: PlayerTrack in available_tracks():
		if doctrine.allows(track) and is_track_available_for_engagement(track) and global_position.distance_to(track.estimated_position) <= _definition.attack_range * operational_efficiency():
			return track
	return null

func _launch(track: PlayerTrack) -> InterceptorDrone:
	weapon_fired.emit(self, false)
	var drone := DRONE_SCENE.instantiate() as InterceptorDrone
	projectile_parent.add_child(drone)
	drone.global_position = launch_point.global_position
	drone.configure(self, track, registry, _definition)
	active_drones.append(drone)
	available_drones -= 1
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"interceptor_drone")
	return drone

func recover_drone(_drone: InterceptorDrone) -> void:
	recharge_queue.append(_definition.recharge_duration)

func release_engagement(track_id: int) -> void:
	if engagement_coordinator != null:
		engagement_coordinator.release(track_id, runtime_id)

func resource_status_text() -> String:
	return "%s\n드론 대기 %d · 출격 %d · 충전 %d" % [operational_status_text(), available_drones, active_drones.size(), recharge_queue.size()]

func capture_content_state() -> Dictionary:
	return {"available_drones": available_drones, "recharge_queue": recharge_queue.duplicate(), "cooldown": cooldown, "doctrine": capture_doctrine_state()}

func restore_content_state(state_data: Dictionary) -> void:
	available_drones = int(state_data.get("available_drones", _definition.drone_count))
	recharge_queue.clear()
	for remaining: Variant in state_data.get("recharge_queue", []):
		recharge_queue.append(float(remaining))
	cooldown = float(state_data.get("cooldown", 0.0))
	restore_doctrine_state(state_data.get("doctrine", {}))
