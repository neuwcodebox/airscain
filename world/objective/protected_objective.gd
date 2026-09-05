class_name ProtectedObjective
extends Node3D

signal integrity_changed(current: int, maximum: int)
signal damage_received(amount: int)
signal depleted(objective: ProtectedObjective)

const DAMAGE_SMOKE_SCENE := preload("res://effects/damage_smoke/damage_smoke.tscn")
const MAX_DAMAGE_SMOKE_SITES := 4
const SURFACE_IMPACT_PLUME_REFERENCE_HEIGHT := 18.0

var runtime_id: int
var definition: ObjectiveDefinition
var current_integrity: int
var exclusion_radius: float = 165.0
var damage_smoke_effects: Array[DamageSmokeEffect] = []
var damage_smoke_sites: Array[Dictionary] = []
var prepared_smoke_effects: Array[DamageSmokeEffect] = []

func setup(id_value: int, definition_value: ObjectiveDefinition) -> void:
	runtime_id = id_value
	definition = definition_value
	current_integrity = definition.maximum_integrity
	if prepared_smoke_effects.is_empty() and damage_smoke_effects.is_empty():
		for index: int in MAX_DAMAGE_SMOKE_SITES:
			var effect := DAMAGE_SMOKE_SCENE.instantiate() as DamageSmokeEffect
			add_child(effect)
			effect.deactivate()
			prepared_smoke_effects.append(effect)
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)

func apply_mission_damage(amount: int) -> bool:
	if current_integrity <= 0 or amount <= 0:
		return false
	var previous_integrity := current_integrity
	current_integrity = maxi(0, current_integrity - amount)
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)
	damage_received.emit(previous_integrity - current_integrity)
	if current_integrity == 0:
		depleted.emit(self)
	return true

func apply_building_impact(amount: int, global_impact_position: Vector3, building_height: float) -> bool:
	if current_integrity <= 0 or amount <= 0:
		return false
	_append_damage_smoke_site(global_impact_position, building_height)
	return apply_mission_damage(amount)

func apply_surface_impact(amount: int, global_impact_position: Vector3) -> bool:
	if current_integrity <= 0 or amount <= 0:
		return false
	_append_damage_smoke_site(global_impact_position, SURFACE_IMPACT_PLUME_REFERENCE_HEIGHT)
	return apply_mission_damage(amount)

func capture_damage_smoke_state() -> Array[Dictionary]:
	return damage_smoke_sites.duplicate(true)

func restore_damage_smoke_state(states: Array) -> void:
	for effect: DamageSmokeEffect in damage_smoke_effects:
		if is_instance_valid(effect):
			_recycle_smoke(effect)
	damage_smoke_effects.clear()
	damage_smoke_sites.clear()
	for state: Variant in states:
		var site := state as Dictionary
		damage_smoke_sites.append({
			"offset": site.offset,
			"building_height": float(site.building_height),
		})

func _append_damage_smoke_site(global_impact_position: Vector3, building_height: float) -> void:
	if damage_smoke_sites.size() >= MAX_DAMAGE_SMOKE_SITES:
		damage_smoke_sites.pop_front()
		if not damage_smoke_effects.is_empty():
			var oldest: DamageSmokeEffect = damage_smoke_effects.pop_front()
			_recycle_smoke(oldest)
	damage_smoke_sites.append({
		"offset": SaveDocument.vector3_to_data(to_local(global_impact_position)),
		"building_height": maxf(1.0, building_height),
	})

func get_target_point(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var radius := sqrt(rng.randf()) * exclusion_radius * 0.72
	return global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

func excludes_placement(world_position: Vector3, radius: float) -> bool:
	var flat_delta := Vector2(world_position.x - global_position.x, world_position.z - global_position.z)
	return flat_delta.length() < exclusion_radius + radius

func restore_integrity(value: int) -> void:
	current_integrity = clampi(value, 0, definition.maximum_integrity)
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)

func _sync_damage_visuals() -> void:
	for index: int in range(damage_smoke_effects.size() - 1, -1, -1):
		if not is_instance_valid(damage_smoke_effects[index]):
			damage_smoke_effects.remove_at(index)
	var desired_count := damage_smoke_sites.size() if current_integrity < definition.maximum_integrity else 0
	while damage_smoke_effects.size() < desired_count:
		var index := damage_smoke_effects.size()
		var effect: DamageSmokeEffect = prepared_smoke_effects.pop_back()
		effect.position = SaveDocument.vector3_from_data(damage_smoke_sites[index].offset)
		effect.set_city_scale(1.5, float(damage_smoke_sites[index].building_height))
		effect.restart_at_source()
		damage_smoke_effects.append(effect)
	while damage_smoke_effects.size() > desired_count:
		var effect: DamageSmokeEffect = damage_smoke_effects.pop_back()
		_recycle_smoke(effect)
	for index: int in damage_smoke_effects.size():
		damage_smoke_effects[index].position = SaveDocument.vector3_from_data(damage_smoke_sites[index].offset)

func _recycle_smoke(effect: DamageSmokeEffect) -> void:
	effect.deactivate()
	prepared_smoke_effects.append(effect)
