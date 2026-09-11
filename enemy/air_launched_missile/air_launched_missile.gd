class_name AirLaunchedMissile
extends ThreatUnit

@onready var flight: AirStrikeMunition = $Flight

func _ready() -> void:
	flight.set_process(false)
	flight.managed = true
	flight.flight_finished.connect(_on_impact)

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	health = (definition_value as AirLaunchedMissileDefinition).maximum_health

func launch(target: Vector3, objective: ProtectedObjective, battlefield: Battlefield, damage: int, asset: DefenseUnit, city: bool, velocity: Vector3) -> void:
	flight.setup(target, objective, damage, asset, city)
	flight.configure_flight(StrikeFlight.Mode.MISSILE, velocity, battlefield)

func gameplay_tick(delta: float) -> void:
	super.gameplay_tick(delta)
	if not is_targetable():
		return
	flight.gameplay_tick(delta)
	var position_after: Vector3 = flight.global_position
	global_position = position_after
	flight.position = Vector3.ZERO

func presentation_velocity() -> Vector3:
	return flight.motion.velocity

func get_urgency() -> float:
	return 1.0 / maxf(1.0, global_position.distance_to(flight.target_position))

func _on_impact() -> void:
	global_position = flight.global_position
	flight.position = Vector3.ZERO
	resolve_once(false)

func resolve_once(neutralized: bool) -> bool:
	if resolved_state:
		return false
	flight.stop()
	flight.release_trail(get_parent())
	return super.resolve_once(neutralized)

func capture_content_state() -> Dictionary:
	return flight.capture_state()

func restore_content_state(state: Dictionary, objective: ProtectedObjective, battlefield: Battlefield, defenses: Dictionary[int, DefenseUnit] = {}) -> void:
	flight.battlefield = battlefield
	flight.restore_state(state, objective, defenses)
