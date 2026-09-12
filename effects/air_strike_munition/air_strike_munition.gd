class_name AirStrikeMunition
extends Node3D
## Scene adapter: composes flight and impact rules with the existing visual nodes.

signal flight_finished

const SIMULATION_GROUP := &"unpowered_strike_munitions"

var motion := StrikeFlight.new()
var payload := StrikePayload.new()
var target_position: Vector3
var battlefield: Battlefield
var impacted: bool = false
var managed: bool = false

func setup(target: Vector3, objective: ProtectedObjective, damage: int, asset: DefenseUnit = null, city: bool = true) -> void:
	target_position = target
	payload.setup(objective, damage, asset, city)
	_update_flight_visuals()

func configure_flight(mode: StrikeFlight.Mode, initial_velocity: Vector3, world: Battlefield) -> void:
	motion.mode = mode
	motion.velocity = initial_velocity
	battlefield = world
	if mode == StrikeFlight.Mode.BOMB and battlefield != null:
		add_to_group(SIMULATION_GROUP)
		set_process(false)
	_update_flight_visuals()

func _process(delta: float) -> void:
	gameplay_tick(delta)

func gameplay_tick(delta: float) -> void:
	if impacted or delta <= 0.0:
		return
	var remaining := minf(delta, 30.0) if motion.mode != StrikeFlight.Mode.DIRECT else delta
	while remaining > 0.00001 and not impacted:
		var step := minf(remaining, StrikeFlight.MAXIMUM_STEP) if motion.mode != StrikeFlight.Mode.DIRECT else remaining
		var previous := global_position
		global_position = motion.advance(previous, target_position, battlefield, step)
		_update_flight_visuals()
		if motion.powered():
			$SmokeTrail.sample_world_segment(previous, global_position)
		match motion.result:
			StrikeFlight.Result.IMPACT:
				target_position = global_position
				payload.apply_impact(global_position)
				if not managed and get_parent() != null:
					ExplosionEffect.spawn(get_parent() as Node3D, global_position, Color("ffb02e"), 8.0)
				_finish()
			StrikeFlight.Result.EXPIRED:
				_finish()
		remaining -= step

func _update_flight_visuals() -> void:
	$Flame.visible = motion.powered()
	$FlameLight.visible = motion.powered()
	var direction := motion.velocity.normalized()
	if motion.mode == StrikeFlight.Mode.DIRECT:
		direction = global_position.direction_to(target_position)
	if direction.length_squared() > 0.01:
		look_at(global_position + direction, Vector3.FORWARD if absf(direction.y) > 0.98 else Vector3.UP)

func stop() -> void:
	impacted = true

func _finish() -> void:
	stop()
	if not managed:
		release_trail(get_parent())
		queue_free()
	flight_finished.emit()

func release_trail(parent: Node) -> void:
	var smoke := get_node_or_null("SmokeTrail") as LingeringSmokeTrail
	if smoke != null and parent != null:
		if motion.mode == StrikeFlight.Mode.BOMB:
			smoke.queue_free()
		else:
			smoke.release_to(parent)

func capture_state() -> Dictionary:
	var state := {
		"type": "air_strike_munition",
		"position": SaveDocument.vector3_to_data(global_position),
		"target_position": SaveDocument.vector3_to_data(target_position),
	}
	state.merge(motion.capture_state())
	state.merge(payload.capture_state())
	return state

func restore_state(state: Dictionary, objective: ProtectedObjective, defenses: Dictionary[int, DefenseUnit] = {}) -> void:
	global_position = SaveDocument.vector3_from_data(state.position)
	target_position = SaveDocument.vector3_from_data(state.target_position)
	payload.restore_state(state, objective, defenses)
	motion.restore_state(state)
	configure_flight(motion.mode, motion.velocity, battlefield)

static func state_validation_error(state: Dictionary) -> String:
	for field: String in ["position", "target_position"]:
		var value: Variant = state.get(field)
		if not SaveDocument.is_valid_vector3_data(value):
			return "공대지 탄 비행 위치가 올바르지 않습니다"
	var flight_error := StrikeFlight.state_validation_error(state)
	return flight_error if not flight_error.is_empty() else StrikePayload.state_validation_error(state)
