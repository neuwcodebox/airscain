class_name AirscainMain
extends Node3D

const BASE_SCENARIO := preload("res://main/first_scenario.tres")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")
const HOMING_INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")

static var requested_seed: int = -1

var scenario: ScenarioDefinition
var registry := ThreatRegistry.new()
var objective: ProtectedObjective
var defenses: Array[DefenseUnit] = []
var selected_asset: DefenseUnit
var selected_track: PlayerTrack
var save_path: String = SaveStore.DEFAULT_PATH

@onready var battlefield: Battlefield = $Battlefield
@onready var session: GameSession = $GameSession
@onready var player_knowledge: Node = $PlayerKnowledge
@onready var c2_network: Node = $C2Network
@onready var engagement_coordinator: EngagementCoordinator = $EngagementCoordinator
@onready var support_manager: SupportManager = $SupportManager
@onready var track_display: Node = $WorldObjects/TacticalTracks
@onready var c2_overlay: Node = $WorldObjects/C2Overlay
@onready var director: ThreatDirector = $ThreatDirector
@onready var camera_rig: CameraRig = $CameraRig
@onready var world_objects: Node3D = $WorldObjects
@onready var objectives: Node3D = $WorldObjects/Objectives
@onready var defense_parent: Node3D = $WorldObjects/Defenses
@onready var threat_parent: Node3D = $WorldObjects/Threats
@onready var projectile_parent: Node3D = $WorldObjects/Projectiles
@onready var effects_parent: Node3D = $WorldObjects/Effects
@onready var placement: PlacementController = $PlacementController
@onready var hud: Hud = $UI/HUD

func _ready() -> void:
	scenario = BASE_SCENARIO.duplicate(true) as ScenarioDefinition
	if requested_seed >= 0:
		scenario.world_seed = requested_seed
	requested_seed = scenario.world_seed
	var scenario_error := scenario.validation_error()
	if not scenario_error.is_empty():
		push_error("시나리오를 시작할 수 없습니다: %s" % scenario_error)
		get_tree().quit(1)
		return
	battlefield.build(scenario)
	camera_rig.configure_for_battlefield(scenario.battlefield_size)
	_spawn_objective()
	_spawn_ambient_contacts()
	session.reset(scenario.starting_budget)
	support_manager.configure(session)
	player_knowledge.call("reset")
	c2_network.call("reset")
	track_display.call("configure", player_knowledge)
	c2_overlay.call("configure", c2_network)
	director.configure(scenario, battlefield, objective, registry, threat_parent)
	placement.configure(session, battlefield, camera_rig.camera, defense_parent, projectile_parent, registry)
	hud.configure(session, objective, scenario.available_defenses)
	_connect_flow()
	hud.set_feedback("포대를 배치한 뒤 방어를 시작하세요 · Seed %d" % scenario.world_seed)

func _process(delta: float) -> void:
	var simulation_delta := session.gameplay_delta(delta)
	if simulation_delta <= 0.0:
		return
	director.gameplay_tick(simulation_delta)
	player_knowledge.call("gameplay_tick", simulation_delta)
	engagement_coordinator.gameplay_tick(simulation_delta)
	support_manager.gameplay_tick(simulation_delta)
	for defense: DefenseUnit in defenses:
		if is_instance_valid(defense):
			defense.gameplay_tick(simulation_delta)
	for threat: ThreatUnit in registry.get_active():
		threat.gameplay_tick(simulation_delta)

func _spawn_objective() -> void:
	objective = scenario.objective_definition.scene.instantiate() as ProtectedObjective
	objectives.add_child(objective)
	objective.global_position = Vector3(0.0, battlefield.terrain_height(0.0, 0.0), 0.0)
	objective.exclusion_radius = scenario.city_size * 0.5
	objective.setup(1, scenario.objective_definition)
	battlefield.set_objective(objective)

func _spawn_ambient_contacts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = scenario.world_seed ^ 0x42B17D2
	var next_ambient_id := -1
	for contact_definition: ThreatDefinition in scenario.ambient_contacts:
		for index: int in scenario.ambient_contacts_per_type:
			var contact := contact_definition.scene.instantiate() as ThreatUnit
			threat_parent.add_child(contact)
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(230.0, scenario.battlefield_size * 0.32)
			contact.global_position = Vector3(cos(angle) * radius, 50.0, sin(angle) * radius)
			contact.setup(next_ambient_id, contact_definition)
			next_ambient_id -= 1
			var heading := rng.randf_range(0.0, TAU)
			contact.configure_patrol(battlefield, Vector3(cos(heading), 0.0, sin(heading)) * rng.randf_range(12.0, 18.0))
			registry.add(contact)
			_on_threat_spawned(contact)

func _connect_flow() -> void:
	objective.depleted.connect(_on_objective_depleted)
	director.threat_spawned.connect(_on_threat_spawned)
	director.pressure_changed.connect(_on_pressure_changed)
	session.defense_placed.connect(_on_defense_placed)
	hud.defense_selected.connect(placement.select)
	hud.start_requested.connect(_on_start_requested)
	hud.speed_requested.connect(session.set_simulation_speed)
	hud.restart_requested.connect(_on_restart_requested)
	placement.feedback_changed.connect(hud.set_feedback)
	placement.asset_selected.connect(_on_asset_selected)
	placement.world_selected.connect(_on_world_selected)
	hud.c2_overlay_requested.connect(_on_c2_overlay_requested)
	hud.hold_fire_requested.connect(_on_hold_fire_requested)
	hud.engage_unknown_requested.connect(_on_engage_unknown_requested)
	hud.priority_target_requested.connect(_on_priority_target_requested)
	hud.resupply_requested.connect(_on_resupply_requested)
	hud.repair_requested.connect(_on_repair_requested)
	hud.save_requested.connect(_on_save_requested)
	hud.load_requested.connect(_on_load_requested)

func _on_start_requested() -> void:
	if session.start_defense():
		director.enabled = true
		hud.set_feedback("방어 진행 중 · 포대를 추가 배치할 수 있습니다")

func _on_defense_placed(unit: DefenseUnit) -> void:
	defenses.append(unit)
	unit.configure_player_knowledge(battlefield, player_knowledge)
	c2_network.call("register_asset", unit)
	unit.configure_c2(c2_network)
	unit.configure_engagements(engagement_coordinator)
	unit.configure_support(support_manager)
	support_manager.register_asset(unit)

func _on_threat_spawned(threat: ThreatUnit) -> void:
	threat.resolved.connect(_on_threat_resolved)

func _on_threat_resolved(threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	registry.remove(threat)
	session.register_threat_resolution(threat, neutralized, reward)
	_spawn_explosion(threat.global_position, Color("ff8c35") if neutralized else Color("ff3b24"), 10.0 if neutralized else 15.0)
	threat.queue_free()

func _on_objective_depleted(_objective: ProtectedObjective) -> void:
	if not _objective.definition.required_for_survival:
		return
	director.enabled = false
	session.end_game()
	placement.cancel()

func _on_pressure_changed(level: int) -> void:
	session.update_pressure(level)
	hud.set_pressure(level)

func _spawn_explosion(position: Vector3, color: Color, radius: float) -> void:
	var effect := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	effects_parent.add_child(effect)
	effect.global_position = position
	effect.setup(color, radius)

func _on_restart_requested(same_seed: bool) -> void:
	if same_seed:
		requested_seed = scenario.world_seed
	else:
		requested_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	get_tree().reload_current_scene()

func _on_asset_selected(unit: DefenseUnit) -> void:
	selected_asset = unit
	selected_track = null
	c2_overlay.call("select_asset", unit)
	hud.set_selected_asset(unit, int(c2_overlay.get("visible_link_count")))

func _on_c2_overlay_requested() -> void:
	c2_overlay.call("toggle_all_links")

func _on_world_selected(position: Vector3) -> void:
	var nearest_distance := 32.0
	selected_track = null
	var tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	for track: PlayerTrack in tracks:
		var flat_distance := Vector2(track.estimated_position.x - position.x, track.estimated_position.z - position.z).length()
		if flat_distance < nearest_distance:
			nearest_distance = flat_distance
			selected_track = track
	hud.set_selected_track(selected_track, selected_asset != null and selected_asset.has_method("set_priority_track"))

func _on_hold_fire_requested(enabled: bool) -> void:
	if selected_asset != null and selected_asset.has_method("set_hold_fire"):
		selected_asset.call("set_hold_fire", enabled)

func _on_engage_unknown_requested(enabled: bool) -> void:
	if selected_asset != null and selected_asset.has_method("set_engage_unknown"):
		selected_asset.call("set_engage_unknown", enabled)

func _on_priority_target_requested() -> void:
	if selected_asset != null and selected_track != null and selected_asset.has_method("set_priority_track"):
		selected_asset.call("set_priority_track", selected_track.track_id)
		hud.set_feedback("항적을 우선표적으로 지정했습니다")

func _on_resupply_requested() -> void:
	if selected_asset is ArmedDefenseUnit and (selected_asset as ArmedDefenseUnit).request_resupply():
		hud.set_feedback("재보급 작업을 요청했습니다")
	else:
		hud.set_feedback("현재 재보급을 요청할 수 없습니다")

func _on_repair_requested() -> void:
	if selected_asset != null and selected_asset.request_repair():
		hud.set_feedback("수리 작업을 요청했습니다")
	else:
		hud.set_feedback("현재 수리를 요청할 수 없습니다")

func _on_save_requested() -> void:
	var error := SaveStore.write(capture_save_document(), save_path)
	hud.set_feedback("저장 완료" if error.is_empty() else "저장 실패 · %s" % error)

func _on_load_requested() -> void:
	var result := SaveStore.read(save_path)
	var error: String = result.error
	if error.is_empty():
		error = restore_from_document(result.document)
	hud.set_feedback("불러오기 완료" if error.is_empty() else "불러오기 실패 · %s" % error)

func capture_save_document() -> Dictionary:
	return SaveDocument.create(SessionSnapshot.capture_payload(self))

func restore_from_document(document: Dictionary) -> String:
	var document_error := SaveDocument.validation_error(document)
	if not document_error.is_empty():
		return document_error
	var payload: Dictionary = document.payload
	var snapshot_error := SessionSnapshot.validation_error(payload, scenario)
	if not snapshot_error.is_empty():
		return snapshot_error
	_apply_runtime_snapshot(payload)
	return ""

func _apply_runtime_snapshot(payload: Dictionary) -> void:
	_clear_runtime_objects()
	var restored_seed := int(payload.scenario.world_seed)
	if scenario.world_seed != restored_seed:
		scenario.world_seed = restored_seed
		requested_seed = restored_seed
		battlefield.build(scenario)
	var world_state: Dictionary = payload.world
	objective.restore_integrity(int(world_state.objective_integrity))
	var defense_definitions := SessionSnapshot.defense_definition_map(scenario)
	for state: Dictionary in world_state.defenses:
		var definition: DefenseDefinition = defense_definitions[StringName(String(state.definition_id))]
		var unit := definition.scene.instantiate() as DefenseUnit
		defense_parent.add_child(unit)
		unit.global_position = SaveDocument.vector3_from_data(state.position)
		unit.setup(int(state.runtime_id), definition)
		unit.configure_combat(registry, projectile_parent)
		unit.restore_state(state)
		battlefield.register_occupancy(unit.global_position, definition.placement_profile.footprint_radius)
		_on_defense_placed(unit)
	var contact_definitions := SessionSnapshot.contact_definition_map(scenario)
	for state: Dictionary in world_state.contacts:
		var definition: ThreatDefinition = contact_definitions[StringName(String(state.definition_id))]
		var contact := definition.scene.instantiate() as ThreatUnit
		threat_parent.add_child(contact)
		contact.global_position = SaveDocument.vector3_from_data(state.position)
		contact.setup(int(state.runtime_id), definition)
		contact.restore_state(state, objective, battlefield)
		registry.add(contact)
		_on_threat_spawned(contact)
	player_knowledge.call("restore_state", payload.player_knowledge)
	engagement_coordinator.restore_state(world_state.engagements)
	support_manager.restore_state(world_state.support)
	for state: Dictionary in world_state.projectiles:
		var owner := _find_defense(int(state.owner_defense_id)) as MissileBattery
		var target_track: PlayerTrack = player_knowledge.call("find_track", int(state.target_track_id))
		var interceptor := HOMING_INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
		projectile_parent.add_child(interceptor)
		interceptor.restore_state(state, target_track, registry)
		owner.interceptors.append(interceptor)
	director.restore_state(payload.director)
	session.restore_state(payload.session)

func _find_defense(runtime_id: int) -> DefenseUnit:
	for unit: DefenseUnit in defenses:
		if unit.runtime_id == runtime_id:
			return unit
	return null

func _clear_runtime_objects() -> void:
	for parent: Node in [defense_parent, threat_parent, projectile_parent, effects_parent]:
		for child: Node in parent.get_children():
			child.free()
	defenses.clear()
	registry.clear()
	battlefield.clear_occupancy()
	player_knowledge.call("reset")
	track_display.call("reset")
	c2_network.call("reset")
	engagement_coordinator.reset()
	support_manager.reset()
	selected_asset = null
	selected_track = null
	c2_overlay.call("select_asset", null)
	hud.set_selected_asset(null, 0)
