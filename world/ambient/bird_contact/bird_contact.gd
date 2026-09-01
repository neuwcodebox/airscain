class_name BirdContact
extends ThreatUnit

var battlefield: Battlefield
var patrol_velocity: Vector3
var patrol_bounds: float = 700.0

@onready var body: Node3D = $Body

func setup(id_value: int, definition_value: ThreatDefinition) -> void:
	super.setup(id_value, definition_value)
	health = 20.0

func configure_patrol(battlefield_value: Battlefield, initial_velocity: Vector3) -> void:
	battlefield = battlefield_value
	patrol_bounds = battlefield.battlefield_size * 0.4
	patrol_velocity = initial_velocity

func gameplay_tick(delta: float) -> void:
	if not active or resolved_state or battlefield == null:
		return
	global_position += patrol_velocity * delta
	if absf(global_position.x) > patrol_bounds:
		patrol_velocity.x *= -1.0
	if absf(global_position.z) > patrol_bounds:
		patrol_velocity.z *= -1.0
	var desired_altitude := battlefield.terrain_height(global_position.x, global_position.z) + 45.0
	global_position.y = move_toward(global_position.y, desired_altitude, delta * 8.0)
	if patrol_velocity.length_squared() > 0.001:
		body.look_at(global_position + patrol_velocity, Vector3.UP)

func get_urgency() -> float:
	return 0.0

func capture_content_state() -> Dictionary:
	return {"patrol_velocity": SaveDocument.vector3_to_data(patrol_velocity)}

func restore_content_state(state: Dictionary, _objective: ProtectedObjective, battlefield_value: Battlefield) -> void:
	battlefield = battlefield_value
	patrol_bounds = battlefield.battlefield_size * 0.4
	patrol_velocity = SaveDocument.vector3_from_data(state.get("patrol_velocity", []))
