class_name HighEnergyLaser
extends ArmedDefenseUnit

const LASER_PULSE_SCENE := preload("res://effects/laser_pulse/laser_pulse.tscn")
const TURRET_AIMER := preload("res://defense/turret_aimer.gd")

@export var turret_turn_speed_degrees: float = 95.0
@export var emitter_elevation_speed_degrees: float = 80.0
@export var firing_alignment_degrees: float = 2.0

var registry: ThreatRegistry
var projectile_parent: Node3D
var power_manager: PowerManager
var energy_state := EnergyWeaponState.new()
var cooldown: float = 0.0
var _definition: HighEnergyLaserDefinition

@onready var turret: Node3D = $Turret
@onready var elevation: Node3D = $Turret/Elevation
@onready var emitter: Marker3D = $Turret/Elevation/Emitter

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as HighEnergyLaserDefinition
	energy_state.setup(_definition.energy_capacity, _definition.recharge_rate, _definition.heat_capacity, _definition.heat_per_pulse, _definition.cooling_rate)

func configure_combat(registry_value: ThreatRegistry, projectile_parent_value: Node3D) -> void:
	registry = registry_value
	projectile_parent = projectile_parent_value

func configure_power(manager: PowerManager) -> void:
	power_manager = manager

func c2_link_range() -> float:
	return _definition.c2_range * operational_efficiency()

func power_demand() -> float:
	return _definition.power_demand if _definition != null else 0.0

func gameplay_tick(delta: float) -> void:
	if not active:
		return
	var supplied_power := power_manager.request_power(_definition.power_demand) if power_manager != null else 0.0
	energy_state.gameplay_tick(delta, supplied_power / _definition.power_demand)
	cooldown = maxf(0.0, cooldown - delta)
	if registry == null or player_knowledge == null or c2_network == null:
		return
	var track := select_track(available_tracks(), battlefield.objective.global_position)
	if track == null:
		return
	var is_aimed := _aim_turret(track.estimated_position, delta)
	if is_aimed and cooldown <= 0.0 and energy_state.can_fire(_definition.energy_per_pulse) and engagement_coordinator != null and engagement_coordinator.try_reserve(track.track_id, runtime_id, _definition.pulse_interval):
		energy_state.consume(_definition.energy_per_pulse)
		_fire_pulse(track)
		cooldown = _definition.pulse_interval

func _aim_turret(target_position: Vector3, delta: float) -> bool:
	return TURRET_AIMER.aim(turret, elevation, target_position, turret_turn_speed_degrees, emitter_elevation_speed_degrees, firing_alignment_degrees, delta, -10.0, 85.0)

func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
	var selected: PlayerTrack
	var selected_score := -INF
	for track: PlayerTrack in tracks:
		if not doctrine.allows(track) or not is_track_available_for_engagement(track):
			continue
		if global_position.distance_to(track.estimated_position) > _definition.attack_range * operational_efficiency():
			continue
		if track.track_id == doctrine.priority_track_id:
			return track
		var urgency := 1.0 / maxf(1.0, track.estimated_position.distance_to(protected_position))
		var target_match := 1.0 if track.classification == &"small_uav" else 0.65
		var score := urgency * track.track_quality * target_match
		if score > selected_score:
			selected = track
			selected_score = score
	return selected

func resource_status_text() -> String:
	var thermal_status := "과열" if energy_state.overheated else "열 %d%%" % roundi(energy_state.heat / energy_state.heat_capacity * 100.0)
	var status := "%s\n충전 %d%% · %s" % [operational_status_text(), roundi(energy_state.energy / energy_state.capacity * 100.0), thermal_status]
	status += "\n%s" % (power_manager.consumer_status(power_demand()) if power_manager != null else "전력 공급 없음")
	if support_manager != null and not support_manager.task_status(self).is_empty():
		status += " · %s" % support_manager.task_status(self)
	if relocation_manager != null and not relocation_manager.task_status(self).is_empty():
		status += " · %s" % relocation_manager.task_status(self)
	return status

func selection_status_rows() -> Array[Dictionary]:
	var heat_ratio := roundi(energy_state.heat / energy_state.heat_capacity * 100.0)
	var rows: Array[Dictionary] = [
		{"label": "충전", "value": "%d%%" % roundi(energy_state.energy / energy_state.capacity * 100.0)},
		{"label": "열", "value": "과열" if energy_state.overheated else "%d%%" % heat_ratio, "warning": energy_state.overheated},
	]
	rows.append_array(_power_status_rows())
	rows.append_array(_selection_task_rows())
	return rows

func _power_status_rows() -> Array[Dictionary]:
	if power_manager == null:
		return [{"label": "전력", "value": "공급 없음", "warning": true}]
	var capacity := power_manager.generation_capacity()
	var shortage := power_manager.total_demand() > capacity
	return [
		{"label": "전력 수요 / 공급", "value": "%d / %d" % [roundi(power_demand()), roundi(capacity)]},
		{"label": "전력 상태", "value": "부족" if shortage else "정상", "warning": shortage},
	]

func _fire_pulse(track: PlayerTrack) -> void:
	weapon_fired.emit(self, false)
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"laser")
	var pulse := LASER_PULSE_SCENE.instantiate() as LaserPulse
	projectile_parent.add_child(pulse)
	pulse.setup(emitter.global_position, track.estimated_position)
	var target := _physical_target_near(track.estimated_position)
	if target != null:
		target.receive_damage(_definition.pulse_damage)

func _physical_target_near(estimated_position: Vector3) -> ThreatUnit:
	var selected: ThreatUnit
	var nearest_distance := _definition.hit_tolerance
	for threat: ThreatUnit in registry.get_active():
		var distance := threat.get_aim_position().distance_to(estimated_position)
		if distance < nearest_distance:
			selected = threat
			nearest_distance = distance
	return selected

func capture_content_state() -> Dictionary:
	return {"cooldown": cooldown, "energy": energy_state.capture_state(), "doctrine": capture_doctrine_state()}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	energy_state.restore_state(state.get("energy", {}))
	restore_doctrine_state(state.get("doctrine", {}))
