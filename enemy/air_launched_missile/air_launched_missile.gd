extends ThreatUnit

@onready var flight: Node3D = $Flight

func _ready() -> void:
	flight.set_process(false)
	flight.set("managed", true)
	flight.connect("flight_finished", _on_impact)

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	health = float(definition_value.get("maximum_health"))

func launch(target: Vector3, objective: ProtectedObjective, battlefield: Battlefield, damage: int, asset: DefenseUnit, city: bool, velocity: Vector3) -> void:
	flight.call("setup", target, objective, damage, asset, city)
	flight.call("configure_flight", 2, velocity, battlefield)

func gameplay_tick(delta: float) -> void:
	if not is_targetable():
		return
	flight.call("_process", delta)
	var position_after: Vector3 = flight.global_position
	global_position = position_after
	flight.position = Vector3.ZERO

func presentation_velocity() -> Vector3:
	return flight.get("velocity") as Vector3

func get_urgency() -> float:
	return 1.0 / maxf(1.0, global_position.distance_to(flight.get("target_position")))

func _on_impact() -> void:
	global_position = flight.global_position
	flight.position = Vector3.ZERO
	resolve_once(false)

func resolve_once(neutralized: bool) -> bool:
	if resolved_state:
		return false
	flight.set("impacted", true)
	flight.call("release_trail", get_parent())
	return super.resolve_once(neutralized)

func capture_content_state() -> Dictionary:
	return flight.call("capture_state")

func restore_content_state(state: Dictionary, objective: ProtectedObjective, battlefield: Battlefield, defenses: Dictionary[int, DefenseUnit] = {}) -> void:
	flight.set("battlefield", battlefield)
	flight.call("restore_state", state, objective, defenses)
