class_name DefenseDeployment
extends RefCounted

static func deploy(
	definition: DefenseDefinition,
	runtime_id: int,
	position: Vector3,
	battlefield: Battlefield,
	defense_parent: Node3D,
	registry: ThreatRegistry,
	projectile_parent: Node3D
) -> DefenseUnit:
	var unit := _create(definition, runtime_id, position, defense_parent, registry, projectile_parent)
	if unit != null:
		_register_occupancy(unit, definition, battlefield)
	return unit

static func restore(
	definition: DefenseDefinition,
	state: Dictionary,
	position: Vector3,
	battlefield: Battlefield,
	defense_parent: Node3D,
	registry: ThreatRegistry,
	projectile_parent: Node3D
) -> DefenseUnit:
	var unit := _create(definition, int(state.runtime_id), position, defense_parent, registry, projectile_parent)
	if unit == null:
		return null
	unit.restore_state(state)
	_register_occupancy(unit, definition, battlefield)
	return unit

static func _create(
	definition: DefenseDefinition,
	runtime_id: int,
	position: Vector3,
	defense_parent: Node3D,
	registry: ThreatRegistry,
	projectile_parent: Node3D
) -> DefenseUnit:
	if definition == null or definition.scene == null:
		return null
	var unit := definition.scene.instantiate() as DefenseUnit
	if unit == null:
		return null
	defense_parent.add_child(unit)
	unit.global_position = position
	unit.setup(runtime_id, definition)
	unit.configure_combat(registry, projectile_parent)
	return unit

static func _register_occupancy(unit: DefenseUnit, definition: DefenseDefinition, battlefield: Battlefield) -> void:
	battlefield.register_occupancy(unit.global_position, definition.placement_profile.footprint_radius)
