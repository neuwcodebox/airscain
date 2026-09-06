extends Node3D

signal flight_finished

const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")

@export var speed: float = 420.0

var target_position: Vector3
var objective: ProtectedObjective
var damage: int
var target_asset: DefenseUnit
var target_defense_id: int = 0
var targets_city: bool = true
var impacted: bool = false
var flight_mode: int = 0 # Legacy direct flight, unpowered bomb, powered missile.
var velocity: Vector3
var elapsed: float = 0.0
var battlefield: Battlefield
var managed: bool = false

func configure_flight(mode: int, initial_velocity: Vector3, world: Battlefield) -> void:
	flight_mode = mode
	velocity = initial_velocity
	battlefield = world
	if flight_mode == 1 and battlefield != null:
		add_to_group("unpowered_strike_munitions")
		set_process(false)
	_update_flight_visuals()

func _update_flight_visuals() -> void:
	var powered := flight_mode == 0 or flight_mode == 2 and elapsed >= 0.18
	$Flame.visible = powered
	$FlameLight.visible = powered
	if velocity.length_squared() > 0.01:
		var direction := velocity.normalized()
		look_at(global_position + direction, Vector3.FORWARD if absf(direction.y) > 0.98 else Vector3.UP)

static func state_validation_error(state: Dictionary) -> String:
	for field: String in ["position", "target_position"]:
		var value: Variant = state.get(field)
		if not value is Array or value.size() != 3:
			return "공대지 탄 비행 위치가 올바르지 않습니다"
	if not is_finite(float(state.get("speed", 0.0))) or float(state.get("speed", 0.0)) <= 0.0 or int(state.get("damage", 0)) <= 0:
		return "공대지 탄 비행 상태가 올바르지 않습니다"
	if not state.get("targets_city", true) is bool or bool(state.get("targets_city", true)) and int(state.get("target_defense_id", 0)) != 0:
		return "공대지 탄의 타격 종류가 올바르지 않습니다"
	if int(state.get("flight_mode", 0)) not in [0, 1, 2] or not is_finite(float(state.get("elapsed", 0.0))) or float(state.get("elapsed", 0.0)) < 0.0:
		return "투발 무장 비행 단계가 올바르지 않습니다"
	if int(state.get("flight_mode", 0)) != 0:
		var data: Variant = state.get("velocity")
		if not data is Array or data.size() != 3:
			return "투발 무장 속도가 올바르지 않습니다"
		for component: Variant in data:
			if not (component is float or component is int) or not is_finite(float(component)):
				return "투발 무장 속도가 올바르지 않습니다"
	return ""

func setup(target: Vector3, objective_value: ProtectedObjective, damage_value: int, asset: DefenseUnit = null, city: bool = true) -> void:
	target_position = target
	objective = objective_value
	damage = maxi(1, damage_value)
	target_asset = asset
	target_defense_id = asset.runtime_id if is_instance_valid(asset) else 0
	targets_city = city
	if global_position.distance_squared_to(target_position) > 0.001:
		_orient_to_target()

func capture_state() -> Dictionary:
	return {
		"type": "air_strike_munition",
		"position": SaveDocument.vector3_to_data(global_position),
		"target_position": SaveDocument.vector3_to_data(target_position),
		"speed": speed,
		"damage": damage,
		"target_defense_id": target_defense_id,
		"targets_city": targets_city,
		"flight_mode": flight_mode,
		"velocity": SaveDocument.vector3_to_data(velocity),
		"elapsed": elapsed,
	}

func restore_state(state: Dictionary, objective_value: ProtectedObjective, defense_by_id: Dictionary[int, DefenseUnit] = {}) -> void:
	global_position = SaveDocument.vector3_from_data(state.position)
	speed = float(state.speed)
	setup(SaveDocument.vector3_from_data(state.target_position), objective_value, int(state.damage), defense_by_id.get(int(state.get("target_defense_id", 0))), bool(state.get("targets_city", true)))
	elapsed = float(state.get("elapsed", 0.0))
	configure_flight(int(state.get("flight_mode", 0)), SaveDocument.vector3_from_data(state.get("velocity", [0, 0, 0])), battlefield)

func _process(delta: float) -> void:
	if impacted:
		return
	if flight_mode != 0:
		var remaining := minf(delta, 30.0)
		while remaining > 0.00001 and not impacted:
			var step := minf(remaining, 1.0 / 120.0)
			_advance_flight(step)
			remaining -= step
		return
	var previous := global_position
	var distance := global_position.distance_to(target_position)
	var travel := speed * delta
	if distance <= travel:
		global_position = target_position
		_sample_trail(previous, global_position)
		_impact()
		return
	global_position += global_position.direction_to(target_position) * travel
	_orient_to_target()
	_sample_trail(previous, global_position)

func _orient_to_target() -> void:
	var direction := global_position.direction_to(target_position)
	var up_direction := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	look_at(target_position, up_direction)

func _advance_flight(delta: float) -> void:
	var previous := global_position
	var previous_velocity := velocity
	elapsed += delta
	if flight_mode == 1 or elapsed < 0.18:
		velocity.y -= 9.8 * delta
	else:
		var guidance_point := target_position
		var horizontal_distance := Vector2(target_position.x - global_position.x, target_position.z - global_position.z).length()
		if horizontal_distance > 200.0:
			guidance_point.y += 65.0
			if battlefield != null:
				var ahead := global_position + velocity.normalized() * 80.0
				guidance_point.y = maxf(guidance_point.y, battlefield.flight_surface_height(ahead.x, ahead.z) + 30.0)
		var desired := global_position.direction_to(guidance_point)
		var direction := velocity.normalized()
		var angle := direction.angle_to(desired)
		if angle > 0.0001:
			direction = direction.slerp(desired, minf(1.0, deg_to_rad(100.0) * delta / angle))
		velocity = direction * move_toward(velocity.length(), speed, 260.0 * delta)
	global_position += (previous_velocity + velocity) * (0.5 * delta)
	_update_flight_visuals()
	var impact: Dictionary = {}
	if battlefield != null:
		impact = battlefield.building_segment_impact(previous, global_position)
		var terrain := battlefield.terrain_segment_impact(previous, global_position)
		if not terrain.is_empty() and (impact.is_empty() or previous.distance_squared_to(terrain.position) < previous.distance_squared_to(impact.position)):
			impact = terrain
	var nearest := Geometry3D.get_closest_point_to_segment(target_position, previous, global_position)
	if not impact.is_empty():
		global_position = impact.position
	elif flight_mode == 2 and nearest.distance_to(target_position) <= 4.0:
		global_position = target_position
	elif flight_mode == 1 and battlefield == null and global_position.y <= target_position.y and velocity.y < 0.0:
		global_position = previous.lerp(global_position, clampf((previous.y - target_position.y) / maxf(0.0001, previous.y - global_position.y), 0.0, 1.0))
	else:
		if flight_mode == 2 and elapsed >= 0.18:
			_sample_trail(previous, global_position)
		if elapsed >= 20.0:
			_finish()
		return
	if flight_mode == 2 and elapsed >= 0.18:
		_sample_trail(previous, global_position)
	target_position = global_position
	_impact()

func _sample_trail(from_position: Vector3, to_position: Vector3) -> void:
	var smoke := $SmokeTrail as LingeringSmokeTrail
	smoke.sample_world_segment(from_position, to_position)

func _impact() -> void:
	if impacted:
		return
	impacted = true
	if not targets_city:
		if is_instance_valid(target_asset) and target_asset.active and target_asset.global_position.distance_to(target_position) <= maxf(8.0, target_asset.definition.placement_profile.footprint_radius):
			target_asset.receive_damage(damage)
	elif objective != null and is_instance_valid(objective):
		objective.apply_surface_impact(damage, target_position)
	if not managed and get_parent() != null:
		ExplosionEffect.spawn(get_parent() as Node3D, target_position, Color("ffb02e"), 8.0)
	_finish()

func _finish() -> void:
	impacted = true
	if not managed:
		release_trail(get_parent())
		queue_free()
	flight_finished.emit()

func release_trail(parent: Node) -> void:
	var smoke := get_node_or_null("SmokeTrail") as LingeringSmokeTrail
	if smoke != null and parent != null:
		if flight_mode == 1:
			smoke.queue_free()
		else:
			smoke.release_to(parent)
