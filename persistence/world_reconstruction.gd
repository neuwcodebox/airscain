class_name WorldReconstruction
extends RefCounted

signal defense_restored(unit: DefenseUnit)
signal contact_restored(contact: ThreatUnit)

const STRIKE_SCENE := preload("res://effects/air_strike_munition/air_strike_munition.tscn")

var battlefield: Battlefield
var objective: ProtectedObjective
var registry: ThreatRegistry
var defense_parent: Node3D
var threat_parent: Node3D
var projectile_parent: Node3D
var defenses_by_id: Dictionary[int, DefenseUnit] = {}

func _init(world: Battlefield, target: ProtectedObjective, contacts: ThreatRegistry, assets: Node3D, threats: Node3D, projectiles: Node3D) -> void:
	battlefield = world
	objective = target
	registry = contacts
	defense_parent = assets
	threat_parent = threats
	projectile_parent = projectiles

# Consumes validated data after the previous world has been cleared.
# Signals synchronously attach each restored object to gameplay services.
func restore_objects(state: Dictionary, scenario: ScenarioDefinition) -> void:
	defenses_by_id.clear()
	battlefield.align_primary_city_objective(objective)
	objective.restore_damage_smoke_state(state.get("objective_damage_smoke", []))
	objective.restore_integrity(int(state.objective_integrity))
	var defense_definitions := SessionSnapshot.defense_definition_map(scenario)
	for saved: Dictionary in state.defenses:
		var definition: DefenseDefinition = defense_definitions[StringName(String(saved.definition_id))]
		var position := SaveDocument.vector3_from_data(saved.position)
		var rotation_y := float(saved.get("rotation_y", _initial_mount_rotation(saved, position)))
		var unit := DefenseDeployment.restore(definition, saved, position, rotation_y, battlefield, defense_parent, registry, projectile_parent)
		defenses_by_id[unit.runtime_id] = unit
		defense_restored.emit(unit)
	var contact_definitions := SessionSnapshot.contact_definition_map(scenario)
	for saved: Dictionary in state.contacts:
		var definition: ThreatDefinition = contact_definitions[StringName(String(saved.definition_id))]
		var contact := definition.scene.instantiate() as ThreatUnit
		threat_parent.add_child(contact)
		contact.global_position = SaveDocument.vector3_from_data(saved.position)
		contact.setup(int(saved.runtime_id), definition)
		contact.restore_state(saved, objective, battlefield, defenses_by_id)
		registry.add(contact)
		contact_restored.emit(contact)

func _initial_mount_rotation(saved: Dictionary, position: Vector3) -> float:
	for mount: Dictionary in objective.initial_defense_mounts():
		if StringName(String(mount.get("definition_id", ""))) != StringName(String(saved.definition_id)):
			continue
		if (mount.position as Vector3).distance_squared_to(position) <= 0.01:
			return float(mount.get("rotation_y", 0.0))
	return 0.0

# Tracks and engagement reservations must exist before weapons are reattached.
func restore_projectiles(states: Array, knowledge: PlayerKnowledge) -> void:
	var tracks := knowledge.get_active_tracks()
	for state: Dictionary in states:
		if String(state.type) == "air_strike_munition":
			var strike := STRIKE_SCENE.instantiate() as AirStrikeMunition
			threat_parent.add_child(strike)
			strike.battlefield = battlefield
			strike.restore_state(state, objective, defenses_by_id)
		else:
			var owner: DefenseUnit = defenses_by_id[int(state.owner_defense_id)]
			owner.restore_projectile(state, knowledge.find_track(int(state.target_track_id)), tracks)
