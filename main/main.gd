class_name AirscainMain
extends Node3D

enum GameMode { SUSTAINED, TRAINING, SANDBOX }

const BASE_SCENARIO := preload("res://main/first_scenario.tres")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")
const HOMING_INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")
const INTERCEPTOR_DRONE_SCENE := preload("res://defense/interceptor_drone/interceptor_drone.tscn")
const FALLING_WRECK_SCENE := preload("res://effects/falling_wreck/falling_wreck.tscn")

static var requested_seed: int = -1
static var requested_mode: GameMode = GameMode.SUSTAINED

var scenario: ScenarioDefinition
var registry := ThreatRegistry.new()
var objective: ProtectedObjective
var defenses: Array[DefenseUnit] = []
var selected_asset: DefenseUnit
var selected_track: PlayerTrack
var save_path: String = SaveStore.DEFAULT_PATH
var tactical_ui_refresh_remaining: float = 0.0
var game_mode: GameMode = GameMode.SUSTAINED
var training_step: int = 0

@onready var battlefield: Battlefield = $Battlefield
@onready var session: GameSession = $GameSession
@onready var player_knowledge: Node = $PlayerKnowledge
@onready var c2_network: Node = $C2Network
@onready var engagement_coordinator: EngagementCoordinator = $EngagementCoordinator
@onready var support_manager: SupportManager = $SupportManager
@onready var power_manager: PowerManager = $PowerManager
@onready var relocation_manager: RelocationManager = $RelocationManager
@onready var enemy_knowledge: EnemyKnowledge = $EnemyKnowledge
@onready var combat_audio: Node = $CombatAudio
@onready var track_display: TrackDisplay = $WorldObjects/TacticalTracks
@onready var c2_overlay: C2Overlay = $WorldObjects/C2Overlay
@onready var tactical_range_overlay: Node = $WorldObjects/TacticalRangeOverlay
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
@onready var tactical_screen_overlay: Node = $UI/TacticalScreenOverlay

func _ready() -> void:
	scenario = BASE_SCENARIO.duplicate(true) as ScenarioDefinition
	game_mode = requested_mode
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
	session.reset(scenario.starting_budget + scenario.battlefield_layout().starting_budget_bonus, scenario.support_interval, scenario.support_amount)
	if game_mode == GameMode.TRAINING:
		session.budget = 1000
	elif game_mode == GameMode.SANDBOX:
		session.unlimited_budget = true
		session.update_pressure(999)
	support_manager.configure(session)
	relocation_manager.configure(battlefield)
	enemy_knowledge.reset()
	player_knowledge.call("reset")
	c2_network.call("reset")
	c2_network.call("configure", registry)
	track_display.configure(player_knowledge, defense_parent, engagement_coordinator)
	c2_overlay.configure(c2_network)
	tactical_range_overlay.call("configure", defense_parent, registry, support_manager)
	director.configure(scenario, battlefield, objective, registry, threat_parent, defense_parent, enemy_knowledge)
	placement.configure(session, battlefield, camera_rig.camera, defense_parent, projectile_parent, registry, relocation_manager)
	hud.configure(session, objective, scenario.available_defenses, _sandbox_threat_definitions(), game_mode)
	tactical_screen_overlay.configure(camera_rig.camera, player_knowledge)
	_connect_flow()
	if game_mode == GameMode.TRAINING:
		training_step = 1
		hud.set_feedback("훈련 1/5 · 탐색 레이더를 배치하세요")
	elif game_mode == GameMode.SANDBOX:
		hud.set_feedback("샌드박스 · 자산은 무제한이며 목록에서 위협을 골라 지도에 투입할 수 있습니다")
	else:
		hud.set_feedback("포대를 배치한 뒤 방어를 시작하세요 · %s · Seed %d" % [scenario.battlefield_layout().display_name, scenario.world_seed])

func _process(delta: float) -> void:
	tactical_ui_refresh_remaining -= delta
	if tactical_ui_refresh_remaining <= 0.0:
		tactical_ui_refresh_remaining += 0.2
		_refresh_tactical_ui()
	var simulation_delta := session.gameplay_delta(delta)
	if simulation_delta <= 0.0:
		return
	director.gameplay_tick(simulation_delta)
	player_knowledge.call("gameplay_tick", simulation_delta)
	c2_network.call("gameplay_tick", simulation_delta)
	engagement_coordinator.gameplay_tick(simulation_delta)
	support_manager.gameplay_tick(simulation_delta)
	relocation_manager.gameplay_tick(simulation_delta)
	enemy_knowledge.gameplay_tick(simulation_delta)
	power_manager.begin_tick()
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
	director.recovery_started.connect(_on_recovery_started)
	session.defense_placed.connect(_on_defense_placed)
	session.support_received.connect(_on_support_received)
	hud.defense_selected.connect(placement.select)
	hud.start_requested.connect(_on_start_requested)
	hud.speed_requested.connect(session.set_simulation_speed)
	hud.restart_requested.connect(_on_restart_requested)
	placement.feedback_changed.connect(hud.set_feedback)
	placement.asset_selected.connect(_on_asset_selected)
	placement.world_selected.connect(_on_world_selected)
	hud.overlay_requested.connect(_on_overlay_requested)
	hud.hold_fire_requested.connect(_on_hold_fire_requested)
	hud.engage_unknown_requested.connect(_on_engage_unknown_requested)
	hud.priority_target_requested.connect(_on_priority_target_requested)
	hud.munition_mode_requested.connect(_on_munition_mode_requested)
	hud.resupply_requested.connect(_on_resupply_requested)
	hud.repair_requested.connect(_on_repair_requested)
	hud.relocation_requested.connect(_on_relocation_requested)
	hud.save_requested.connect(_on_save_requested)
	hud.load_requested.connect(_on_load_requested)
	hud.focus_requested.connect(_on_focus_requested)
	hud.mode_requested.connect(_on_mode_requested)
	hud.sandbox_threat_selected.connect(placement.select_sandbox_threat)
	placement.sandbox_threat_placement_requested.connect(_on_sandbox_threat_placement_requested)
	player_knowledge.connect("track_removed", _on_track_removed)
	player_knowledge.connect("track_created", _on_track_contact_audio)
	objective.integrity_changed.connect(_on_objective_integrity_audio)

func _on_start_requested() -> void:
	if session.start_defense():
		director.enabled = game_mode != GameMode.SANDBOX
		if game_mode == GameMode.TRAINING:
			training_step = maxi(training_step, 4)
			hud.set_feedback("훈련 4/5 · 센서가 만든 항적을 지도에서 선택하세요")
		elif game_mode == GameMode.SANDBOX:
			hud.set_feedback("샌드박스 교전 진행 중 · 위협을 원하는 위치에 계속 투입할 수 있습니다")
		else:
			hud.set_feedback("방어 진행 중 · 포대를 추가 배치할 수 있습니다")

func _on_defense_placed(unit: DefenseUnit) -> void:
	defenses.append(unit)
	unit.configure_player_knowledge(battlefield, player_knowledge)
	c2_network.call("register_asset", unit)
	unit.configure_c2(c2_network)
	unit.configure_engagements(engagement_coordinator)
	unit.configure_support(support_manager)
	unit.configure_power(power_manager)
	unit.configure_relocation(relocation_manager)
	unit.configure_enemy_knowledge(enemy_knowledge)
	support_manager.register_asset(unit)
	power_manager.register_asset(unit)
	relocation_manager.register_asset(unit)
	unit.weapon_fired.connect(_on_weapon_fired_audio)
	unit.damage_received.connect(_on_defense_damage_audio)
	_advance_training_after_placement(unit)

func _on_threat_spawned(threat: ThreatUnit) -> void:
	threat.configure_enemy_knowledge(enemy_knowledge)
	threat.resolved.connect(_on_threat_resolved)

func _on_threat_resolved(threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	enemy_knowledge.record_outcome(neutralized, threat.global_position, threat.definition.id)
	registry.remove(threat)
	session.register_threat_resolution(threat, neutralized, reward)
	if neutralized and _leaves_falling_wreck(threat):
		_spawn_falling_wreck(threat)
	combat_audio.call("play_event", &"explosion", 0.8 if neutralized else 1.0)
	_spawn_explosion(threat.global_position, Color("ff8c35") if neutralized else Color("ff3b24"), 10.0 if neutralized else 15.0)
	threat.queue_free()

func _leaves_falling_wreck(threat: ThreatUnit) -> bool:
	return threat.definition.signature_class in [&"uav", &"small_uav", &"aircraft", &"air_contact"]

func _spawn_falling_wreck(threat: ThreatUnit) -> void:
	var effect := FALLING_WRECK_SCENE.instantiate() as Node3D
	effects_parent.add_child(effect)
	effect.global_position = threat.global_position
	var color := Color(0.45, 0.16, 0.1)
	if threat.definition is AttackUavDefinition:
		color = (threat.definition as AttackUavDefinition).visual_color
	var ground_height := battlefield.terrain_height(threat.global_position.x, threat.global_position.z)
	effect.call("setup", color, threat.presentation_velocity(), ground_height)

func _on_objective_depleted(_objective: ProtectedObjective) -> void:
	if not _objective.definition.required_for_survival:
		return
	director.enabled = false
	session.end_game()
	placement.cancel()

func _on_pressure_changed(level: int) -> void:
	session.update_pressure(level)
	hud.set_pressure(level)
	combat_audio.call("play_event", &"pressure", clampf(0.45 + float(level) * 0.04, 0.45, 1.0))

func _on_recovery_started(_completed_window: int) -> void:
	session.grant_attack_window_reward(scenario.attack_window_reward)

func _on_support_received(amount: int, reason: String) -> void:
	hud.set_feedback("%s +$%d · 다음 공격 전 방공망을 정비하세요" % [reason, amount])

func _on_track_contact_audio(_track: PlayerTrack) -> void:
	combat_audio.call("play_event", &"contact", 0.55)

func _on_weapon_fired_audio(_unit: DefenseUnit, low_resources: bool) -> void:
	combat_audio.call("play_event", &"launch", 0.52)
	if low_resources:
		combat_audio.call("play_event", &"low_ammo", 0.7)

func _on_defense_damage_audio(_unit: DefenseUnit, _amount: float, integrity_ratio: float) -> void:
	combat_audio.call("play_event", &"damage", clampf(1.1 - integrity_ratio, 0.45, 1.0))

func _on_objective_integrity_audio(current: int, maximum: int) -> void:
	var damage_ratio := 1.0 - float(current) / maxf(1.0, float(maximum))
	combat_audio.call("play_event", &"damage", clampf(0.55 + damage_ratio, 0.55, 1.0))

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
	track_display.select_track(null)
	tactical_screen_overlay.select_track(null)
	c2_overlay.select_asset(unit)
	hud.set_selected_asset(unit, int(c2_overlay.get("visible_link_count")))
	hud.set_selected_track(null, false)

func _on_overlay_requested(mode: StringName) -> void:
	c2_overlay.set_all_links(mode == &"c2")
	tactical_range_overlay.call("set_mode", &"none" if mode == &"c2" else mode)

func _on_world_selected(position: Vector3) -> void:
	var nearest_distance := 32.0
	selected_track = null
	var tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	for track: PlayerTrack in tracks:
		var flat_distance := Vector2(track.estimated_position.x - position.x, track.estimated_position.z - position.z).length()
		if flat_distance < nearest_distance:
			nearest_distance = flat_distance
			selected_track = track
	track_display.select_track(selected_track)
	tactical_screen_overlay.select_track(selected_track)
	_refresh_selected_track_panel()
	if game_mode == GameMode.TRAINING and training_step == 4 and selected_track != null:
		training_step = 5
		hud.set_feedback("훈련 5/5 · 방어자산을 선택해 사격중지를 켰다가 해제해 보세요")

func _refresh_selected_track_panel() -> void:
	var details := track_display.selection_details()
	hud.set_selected_track(selected_track, selected_asset != null and selected_asset.has_method("set_priority_track"), int(details.sensor_count), int(details.engagement_count))

func _refresh_tactical_ui() -> void:
	var hostile_count := 0
	for track: PlayerTrack in player_knowledge.call("get_active_tracks"):
		if track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3:
			hostile_count += 1
	var warnings: Array[String] = []
	var depleted_count := 0
	var disabled_count := 0
	for defense: DefenseUnit in defenses:
		if not is_instance_valid(defense):
			continue
		if not defense.active:
			disabled_count += 1
		if defense is ArmedDefenseUnit and (defense as ArmedDefenseUnit).uses_ammunition() and (defense as ArmedDefenseUnit).magazine.is_depleted():
			depleted_count += 1
	if depleted_count > 0:
		warnings.append("탄약 고갈 %d" % depleted_count)
	if disabled_count > 0:
		warnings.append("기능 정지 %d" % disabled_count)
	if objective != null and objective.current_integrity <= objective.definition.maximum_integrity * 0.3:
		warnings.append("도시 기능 위험")
	hud.set_tactical_alert(hostile_count, engagement_coordinator.reservations.size(), warnings)
	if selected_track != null:
		_refresh_selected_track_panel()

func _on_track_removed(track_id: int) -> void:
	if selected_track == null or selected_track.track_id != track_id:
		return
	selected_track = null
	track_display.select_track(null)
	tactical_screen_overlay.select_track(null)
	_refresh_selected_track_panel()

func _on_focus_requested() -> void:
	if selected_track != null:
		camera_rig.focus_on(selected_track.estimated_position)
	elif selected_asset != null and is_instance_valid(selected_asset):
		camera_rig.focus_on(selected_asset.global_position)

func _on_hold_fire_requested(enabled: bool) -> void:
	if selected_asset != null and selected_asset.has_method("set_hold_fire"):
		selected_asset.call("set_hold_fire", enabled)
		if game_mode == GameMode.TRAINING and training_step >= 5:
			hud.set_feedback("훈련 완료 · 배치, 항적, 자동교전과 국소 명령을 자유롭게 연습하세요")

func _on_engage_unknown_requested(enabled: bool) -> void:
	if selected_asset != null and selected_asset.has_method("set_engage_unknown"):
		selected_asset.call("set_engage_unknown", enabled)

func _on_priority_target_requested() -> void:
	if selected_asset != null and selected_track != null and selected_asset.has_method("set_priority_track"):
		selected_asset.call("set_priority_track", selected_track.track_id)
		hud.set_feedback("항적을 우선표적으로 지정했습니다")

func _on_munition_mode_requested() -> void:
	if selected_asset is MissileBattery:
		(selected_asset as MissileBattery).cycle_munition_mode()
		hud.set_feedback("탄종 운용 모드를 변경했습니다")

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

func _on_relocation_requested() -> void:
	if selected_asset != null and selected_asset.can_request_relocation():
		placement.select_relocation(selected_asset)
	else:
		hud.set_feedback("현재 재배치할 수 없습니다")

func _on_save_requested() -> void:
	if game_mode != GameMode.SUSTAINED:
		hud.set_feedback("저장은 지속 작전에서만 사용할 수 있습니다")
		return
	var error := SaveStore.write(capture_save_document(), save_path)
	hud.set_feedback("저장 완료" if error.is_empty() else "저장 실패 · %s" % error)

func _on_load_requested() -> void:
	if game_mode != GameMode.SUSTAINED:
		hud.set_feedback("불러오기는 지속 작전에서만 사용할 수 있습니다")
		return
	var result := SaveStore.read(save_path)
	var error: String = result.error
	if error.is_empty():
		error = restore_from_document(result.document)
	hud.set_feedback("불러오기 완료" if error.is_empty() else "불러오기 실패 · %s" % error)

func capture_save_document() -> Dictionary:
	return SaveDocument.create(SessionSnapshot.capture_payload(self))

func _on_mode_requested(mode: int) -> void:
	if mode < GameMode.SUSTAINED or mode > GameMode.SANDBOX or mode == game_mode:
		return
	requested_mode = mode as GameMode
	get_tree().reload_current_scene()

func _sandbox_threat_definitions() -> Array[ThreatDefinition]:
	var result: Array[ThreatDefinition] = []
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		result.append(entry.threat_definition)
	return result

func _on_sandbox_threat_placement_requested(definition: ThreatDefinition, position: Vector3) -> void:
	if game_mode != GameMode.SANDBOX:
		return
	var entry: ThreatSpawnEntry
	for candidate: ThreatSpawnEntry in scenario.threat_entries:
		if candidate.threat_definition == definition:
			entry = candidate
			break
	if entry == null:
		return
	var threat := director._spawn_entry(entry, 0.0, 0.0)
	if threat != null:
		var altitude := 55.0
		if definition is AttackUavDefinition:
			altitude = (definition as AttackUavDefinition).movement.cruise_altitude
		threat.global_position = Vector3(position.x, battlefield.terrain_height(position.x, position.z) + altitude, position.z)

func _advance_training_after_placement(unit: DefenseUnit) -> void:
	if game_mode != GameMode.TRAINING:
		return
	if training_step == 1 and unit.definition.id == &"search_radar":
		training_step = 2
		hud.set_feedback("훈련 2/5 · 지휘통제소를 배치해 센서 정보를 공유하세요")
	elif training_step == 2 and unit.definition.id == &"command_post":
		training_step = 3
		hud.set_feedback("훈련 3/5 · 미사일 포대를 배치한 뒤 방어를 시작하세요")
	elif training_step == 3 and unit is MissileBattery:
		hud.set_feedback("훈련 3/5 · 준비 완료, 방어 시작을 누르세요")

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
	var defense_by_id: Dictionary[int, DefenseUnit] = {}
	for defense: DefenseUnit in defenses:
		defense_by_id[defense.runtime_id] = defense
	for state: Dictionary in world_state.contacts:
		var definition: ThreatDefinition = contact_definitions[StringName(String(state.definition_id))]
		var contact := definition.scene.instantiate() as ThreatUnit
		threat_parent.add_child(contact)
		contact.global_position = SaveDocument.vector3_from_data(state.position)
		contact.setup(int(state.runtime_id), definition)
		contact.restore_state(state, objective, battlefield, defense_by_id)
		registry.add(contact)
		_on_threat_spawned(contact)
	player_knowledge.call("restore_state", payload.player_knowledge)
	engagement_coordinator.restore_state(world_state.engagements)
	support_manager.restore_state(world_state.support)
	relocation_manager.restore_state(world_state.relocations)
	enemy_knowledge.restore_state(world_state.enemy_knowledge)
	for state: Dictionary in world_state.projectiles:
		var target_track: PlayerTrack = player_knowledge.call("find_track", int(state.target_track_id))
		if String(state.type) == "homing_interceptor":
			var owner := _find_defense(int(state.owner_defense_id)) as MissileBattery
			var interceptor := HOMING_INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
			projectile_parent.add_child(interceptor)
			interceptor.restore_state(state, target_track, registry)
			owner.interceptors.append(interceptor)
		else:
			var drone_owner := _find_defense(int(state.owner_defense_id)) as InterceptorDroneDefense
			var drone := INTERCEPTOR_DRONE_SCENE.instantiate() as InterceptorDrone
			projectile_parent.add_child(drone)
			drone.restore_state(state, drone_owner, target_track, registry)
			drone_owner.active_drones.append(drone)
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
	power_manager.reset()
	relocation_manager.reset()
	enemy_knowledge.reset()
	selected_asset = null
	selected_track = null
	track_display.select_track(null)
	tactical_screen_overlay.select_track(null)
	c2_overlay.select_asset(null)
	hud.set_selected_asset(null, 0)
	hud.set_selected_track(null, false)
