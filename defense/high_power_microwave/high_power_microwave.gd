class_name HighPowerMicrowave
extends ArmedDefenseUnit

const TURRET_AIMER := preload("res://defense/turret_aimer.gd")

@export var turret_turn_speed_degrees: float = 70.0
@export var dish_elevation_speed_degrees: float = 55.0
@export var firing_alignment_degrees: float = 4.0

var registry: ThreatRegistry
var power_manager: PowerManager
var energy_state := EnergyWeaponState.new()
var cooldown: float = 0.0
var _definition: HighPowerMicrowaveDefinition

@onready var turret: Node3D = $Turret
@onready var elevation: Node3D = $Turret/Elevation
@onready var pulse_visual: FieldPulse = $PulseVisual

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as HighPowerMicrowaveDefinition
	energy_state.setup(_definition.energy_capacity, _definition.recharge_rate, 100.0, 0.1, 100.0)

func configure_combat(registry_value: ThreatRegistry, _projectile_parent: Node3D) -> void:
	registry = registry_value

func configure_power(manager: PowerManager) -> void:
	power_manager = manager

func c2_link_range() -> float:
	return _definition.c2_range * operational_efficiency()

func power_demand() -> float:
	return _definition.power_demand if _definition != null else 0.0

func gameplay_tick(delta: float) -> void:
	if not active:
		maintain_fire_support(null, false)
		return
	var supplied: float = power_manager.request_power(_definition.power_demand) if power_manager != null else 0.0
	energy_state.gameplay_tick(delta, supplied / _definition.power_demand)
	cooldown = maxf(0.0, cooldown - delta)
	if registry == null or engagement_coordinator == null:
		maintain_fire_support(null, false)
		return
	var track := _select_track()
	var has_assignment := maintain_fire_support(track, energy_state.can_fire(_definition.energy_per_pulse))
	var is_aimed := track != null and _aim_turret(track.estimated_position, delta)
	if track != null and is_aimed and cooldown <= 0.0 and energy_state.can_fire(_definition.energy_per_pulse) and has_assignment:
		energy_state.consume(_definition.energy_per_pulse)
		_fire_pulse(track)
		cooldown = _definition.pulse_interval

func _aim_turret(target_position: Vector3, delta: float) -> bool:
	return TURRET_AIMER.aim(turret, elevation, target_position, turret_turn_speed_degrees, dish_elevation_speed_degrees, firing_alignment_degrees, delta, -5.0, 80.0)

func _select_track() -> PlayerTrack:
	var selected: PlayerTrack
	var best_score := -INF
	for track: PlayerTrack in available_tracks():
		if doctrine.allows(track) and global_position.distance_to(track.estimated_position) <= _definition.attack_range * operational_efficiency():
			if track.track_id == doctrine.priority_track_id:
				return track
			var score := cooperative_target_score(track, battlefield.objective.global_position, 1.0)
			if score > best_score:
				selected = track
				best_score = score
	return selected

func _fire_pulse(track: PlayerTrack) -> int:
	weapon_fired.emit(self, false)
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"hpm")
	var affected := 0
	for threat: ThreatUnit in registry.get_active():
		if threat.get_aim_position().distance_to(track.estimated_position) <= _definition.effect_radius and threat.receive_electronic_damage(_definition.electronic_damage):
			affected += 1
	pulse_visual.global_position = track.estimated_position
	pulse_visual.play(_definition.effect_radius)
	return affected

func resource_status_text() -> String:
	var status := "%s\nHPM 충전 %d%%" % [operational_status_text(), roundi(energy_state.energy / energy_state.capacity * 100.0)]
	status += "\n%s" % (power_manager.consumer_status(power_demand()) if power_manager != null else "전력 공급 없음")
	if support_manager != null and not support_manager.task_status(self).is_empty():
		status += "\n%s" % support_manager.task_status(self)
	if relocation_manager != null and not relocation_manager.task_status(self).is_empty():
		status += "\n%s" % relocation_manager.task_status(self)
	return status

func selection_status_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"label": "HPM 충전", "value": "%d%%" % roundi(energy_state.energy / energy_state.capacity * 100.0)},
	]
	if power_manager == null:
		rows.append({"label": "전력", "value": "공급 없음", "warning": true})
	else:
		var capacity := power_manager.generation_capacity()
		var shortage := power_manager.total_demand() > capacity
		rows.append({"label": "전력 수요 / 공급", "value": "%d / %d" % [roundi(power_demand()), roundi(capacity)]})
		rows.append({"label": "전력 상태", "value": "부족" if shortage else "정상", "warning": shortage})
	rows.append_array(_selection_task_rows())
	return rows

func capture_content_state() -> Dictionary:
	return {"cooldown": cooldown, "energy": energy_state.capture_state(), "doctrine": capture_doctrine_state()}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	energy_state.restore_state(state.get("energy", {}))
	restore_doctrine_state(state.get("doctrine", {}))
