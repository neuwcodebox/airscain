class_name ProtectedObjective
extends Node3D

signal integrity_changed(current: int, maximum: int)
signal damage_received(amount: int)
signal depleted(objective: ProtectedObjective)

const DAMAGE_SMOKE_SCENE := preload("res://effects/damage_smoke/damage_smoke.tscn")
const MAX_DAMAGE_SMOKE_SITES_PER_DISTRICT := 4
const MAX_DAMAGE_SMOKE_SITES := 8
const DAMAGE_SMOKE_MERGE_RADIUS := 28.0
const SURFACE_IMPACT_PLUME_REFERENCE_HEIGHT := 18.0
const FALLBACK_DISTRICT_ID := &"central"

var runtime_id: int
var definition: ObjectiveDefinition
var current_integrity: int
var exclusion_radius: float = 165.0
var damage_smoke_effects: Array[DamageSmokeEffect] = []
var damage_smoke_sites: Array[Dictionary] = []
var prepared_smoke_effects: Array[DamageSmokeEffect] = []
var damage_district_centers: Dictionary[StringName, Vector2] = {}
var restored_smoke_needs_repair_reordering: bool = false

func initial_defense_mounts() -> Array[Dictionary]:
	return []

func fit_to_city_block(_block_size: float) -> void:
	pass

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
	_assign_smoke_repair_thresholds()
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
	restored_smoke_needs_repair_reordering = false
	for state: Variant in states:
		var site := state as Dictionary
		var offset := SaveDocument.vector3_from_data(site.offset)
		var district_id := StringName(String(site.get("district_id", "")))
		if district_id.is_empty() or not damage_district_centers.has(district_id):
			restored_smoke_needs_repair_reordering = true
			district_id = _district_id_for_position(to_global(offset))
		damage_smoke_sites.append({
			"offset": site.offset,
			"building_height": float(site.building_height),
			"repair_at": int(site.get("repair_at", definition.maximum_integrity)),
			"district_id": String(district_id),
		})

func _append_damage_smoke_site(global_impact_position: Vector3, building_height: float) -> void:
	var district_id := _district_id_for_position(global_impact_position)
	var local_impact_position := to_local(global_impact_position)
	var merge_index := _nearby_smoke_site_index(district_id, global_impact_position)
	if merge_index >= 0:
		damage_smoke_sites[merge_index].building_height = maxf(float(damage_smoke_sites[merge_index].building_height), building_height)
		if merge_index < damage_smoke_effects.size():
			damage_smoke_effects[merge_index].set_city_scale(1.5, float(damage_smoke_sites[merge_index].building_height))
		return
	var district_count := _district_smoke_count(district_id)
	if district_count >= MAX_DAMAGE_SMOKE_SITES_PER_DISTRICT:
		_remove_smoke_site(_oldest_smoke_site_index(district_id))
	elif damage_smoke_sites.size() >= MAX_DAMAGE_SMOKE_SITES:
		_remove_smoke_site(_global_eviction_index())
	damage_smoke_sites.append({
		"offset": SaveDocument.vector3_to_data(local_impact_position),
		"building_height": maxf(1.0, building_height),
		"district_id": String(district_id),
	})

func configure_damage_districts(districts: Array[CityDistrict]) -> void:
	damage_district_centers.clear()
	for district: CityDistrict in districts:
		damage_district_centers[district.id] = district.center
	for site: Dictionary in damage_smoke_sites:
		var district_id := StringName(String(site.get("district_id", "")))
		if district_id.is_empty() or not damage_district_centers.has(district_id):
			var impact := to_global(SaveDocument.vector3_from_data(site.offset))
			site.district_id = String(_district_id_for_position(impact))

func _district_id_for_position(global_impact_position: Vector3) -> StringName:
	if damage_district_centers.is_empty():
		return FALLBACK_DISTRICT_ID
	var impact := Vector2(global_impact_position.x, global_impact_position.z)
	var nearest_id := StringName()
	var nearest_distance := INF
	for district_id: StringName in damage_district_centers:
		var distance := impact.distance_squared_to(damage_district_centers[district_id])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = district_id
	return nearest_id

func _nearby_smoke_site_index(district_id: StringName, global_impact_position: Vector3) -> int:
	for index: int in damage_smoke_sites.size():
		var site := damage_smoke_sites[index]
		if StringName(String(site.get("district_id", ""))) != district_id:
			continue
		var site_position := to_global(SaveDocument.vector3_from_data(site.offset))
		if Vector2(site_position.x, site_position.z).distance_to(Vector2(global_impact_position.x, global_impact_position.z)) <= DAMAGE_SMOKE_MERGE_RADIUS:
			return index
	return -1

func _district_smoke_count(district_id: StringName) -> int:
	var count := 0
	for site: Dictionary in damage_smoke_sites:
		if StringName(String(site.get("district_id", ""))) == district_id:
			count += 1
	return count

func _oldest_smoke_site_index(district_id: StringName) -> int:
	for index: int in damage_smoke_sites.size():
		if StringName(String(damage_smoke_sites[index].get("district_id", ""))) == district_id:
			return index
	return 0

func _global_eviction_index() -> int:
	var counts := _damage_smoke_counts_by_district()
	var selected_id := StringName()
	var selected_count := 0
	for site: Dictionary in damage_smoke_sites:
		var district_id := StringName(String(site.get("district_id", "")))
		var count: int = counts.get(district_id, 0)
		if count > selected_count:
			selected_id = district_id
			selected_count = count
	return _oldest_smoke_site_index(selected_id)

func _remove_smoke_site(index: int) -> void:
	if index < 0 or index >= damage_smoke_sites.size():
		return
	damage_smoke_sites.remove_at(index)
	if index < damage_smoke_effects.size():
		var effect := damage_smoke_effects[index]
		damage_smoke_effects.remove_at(index)
		_recycle_smoke(effect)

func _damage_smoke_counts_by_district() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for site: Dictionary in damage_smoke_sites:
		var district_id := StringName(String(site.get("district_id", "")))
		counts[district_id] = counts.get(district_id, 0) + 1
	return counts

func _assign_smoke_repair_thresholds() -> void:
	var removal_order := _smoke_repair_removal_order()
	for rank: int in removal_order.size():
		var site_index: int = removal_order[rank]
		damage_smoke_sites[site_index].repair_at = smoke_repair_threshold(current_integrity, definition.maximum_integrity, rank, removal_order.size())

func _smoke_repair_removal_order() -> Array[int]:
	var result: Array[int] = []
	var remaining: Array[int] = []
	for index: int in damage_smoke_sites.size():
		remaining.append(index)
	while not remaining.is_empty():
		var counts: Dictionary[StringName, int] = {}
		for index: int in remaining:
			var district_id := StringName(String(damage_smoke_sites[index].get("district_id", "")))
			counts[district_id] = counts.get(district_id, 0) + 1
		var selected_id := StringName()
		var selected_count := 0
		for index: int in remaining:
			var district_id := StringName(String(damage_smoke_sites[index].get("district_id", "")))
			var count: int = counts.get(district_id, 0)
			if count > selected_count:
				selected_id = district_id
				selected_count = count
		for remaining_index: int in remaining.size():
			var site_index := remaining[remaining_index]
			if StringName(String(damage_smoke_sites[site_index].get("district_id", ""))) == selected_id:
				result.append(site_index)
				remaining.remove_at(remaining_index)
				break
	return result

func get_target_point(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var radius := sqrt(rng.randf()) * exclusion_radius * 0.72
	return global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

func excludes_placement(world_position: Vector3, radius: float) -> bool:
	var flat_delta := Vector2(world_position.x - global_position.x, world_position.z - global_position.z)
	return flat_delta.length() < exclusion_radius + radius

func restore_integrity(value: int) -> void:
	current_integrity = clampi(value, 0, definition.maximum_integrity)
	if restored_smoke_needs_repair_reordering:
		_assign_smoke_repair_thresholds()
		restored_smoke_needs_repair_reordering = false
	for index: int in range(damage_smoke_sites.size() - 1, -1, -1):
		if current_integrity >= int(damage_smoke_sites[index].get("repair_at", definition.maximum_integrity)):
			damage_smoke_sites.remove_at(index)
			if index < damage_smoke_effects.size():
				var effect := damage_smoke_effects[index]
				damage_smoke_effects.remove_at(index)
				_recycle_smoke(effect)
	_sync_damage_visuals()
	integrity_changed.emit(current_integrity, definition.maximum_integrity)

static func smoke_repair_threshold(integrity: int, maximum: int, index: int, count: int) -> int:
	return integrity + ceili(float(maximum - integrity) * float(index + 1) / float(count))

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
