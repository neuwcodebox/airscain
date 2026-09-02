class_name HighPowerMicrowave
extends ArmedDefenseUnit

var registry: ThreatRegistry
var power_manager: PowerManager
var energy_state := EnergyWeaponState.new()
var cooldown: float = 0.0
var _definition: HighPowerMicrowaveDefinition

@onready var turret: Node3D = $Turret
@onready var pulse_visual: MeshInstance3D = $PulseVisual

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

func gameplay_tick(delta: float) -> void:
	if not active:
		return
	var supplied: float = power_manager.request_power(_definition.power_demand) if power_manager != null else 0.0
	energy_state.gameplay_tick(delta, supplied / _definition.power_demand)
	cooldown = maxf(0.0, cooldown - delta)
	if registry == null or engagement_coordinator == null:
		return
	var track := _select_track()
	if track != null and cooldown <= 0.0 and energy_state.can_fire(_definition.energy_per_pulse) and engagement_coordinator.try_reserve(track.track_id, runtime_id, _definition.pulse_interval):
		energy_state.consume(_definition.energy_per_pulse)
		_fire_pulse(track)
		cooldown = _definition.pulse_interval

func _select_track() -> PlayerTrack:
	for track: PlayerTrack in available_tracks():
		if doctrine.allows(track) and global_position.distance_to(track.estimated_position) <= _definition.attack_range * operational_efficiency():
			return track
	return null

func _fire_pulse(track: PlayerTrack) -> int:
	weapon_fired.emit(self, false)
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"hpm")
	var flat_target := Vector3(track.estimated_position.x, turret.global_position.y, track.estimated_position.z)
	if turret.global_position.distance_squared_to(flat_target) > 0.01:
		turret.look_at(flat_target, Vector3.UP)
	var affected := 0
	for threat: ThreatUnit in registry.get_active():
		if threat.get_aim_position().distance_to(track.estimated_position) <= _definition.effect_radius and threat.receive_electronic_damage(_definition.electronic_damage):
			affected += 1
	pulse_visual.global_position = track.estimated_position
	pulse_visual.scale = Vector3.ONE * (_definition.effect_radius / 10.0)
	pulse_visual.visible = true
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(pulse_visual):
			pulse_visual.visible = false
	)
	return affected

func resource_status_text() -> String:
	return "%s\nHPM 충전 %d%%" % [operational_status_text(), roundi(energy_state.energy / energy_state.capacity * 100.0)]

func capture_content_state() -> Dictionary:
	return {"cooldown": cooldown, "energy": energy_state.capture_state(), "doctrine": capture_doctrine_state()}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	energy_state.restore_state(state.get("energy", {}))
	restore_doctrine_state(state.get("doctrine", {}))
