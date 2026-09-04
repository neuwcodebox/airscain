class_name AirscainMain
extends Node3D

enum GameMode { SUSTAINED, TRAINING, SANDBOX }

signal restart_game_requested(mode: GameMode, world_seed: int)
signal main_menu_requested

const BASE_SCENARIO := preload("res://main/first_scenario.tres")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")
const HOMING_INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")
const INTERCEPTOR_DRONE_SCENE := preload("res://defense/interceptor_drone/interceptor_drone.tscn")
const AIR_STRIKE_MUNITION_SCENE := preload("res://effects/air_strike_munition/air_strike_munition.tscn")
const FALLING_WRECK_SCENE := preload("res://effects/falling_wreck/falling_wreck.tscn")

static var requested_seed: int = -1
static var requested_mode: GameMode = GameMode.SUSTAINED
static var last_generated_seed: int = -1

static func generate_world_seed() -> int:
	var generated := (int(Time.get_unix_time_from_system() * 1000.0) ^ int(Time.get_ticks_usec())) & 0x7fffffff
	if generated == last_generated_seed:
		generated = (generated + 1) & 0x7fffffff
	last_generated_seed = generated
	return generated

var scenario: ScenarioDefinition
var registry := ThreatRegistry.new()
var objective: ProtectedObjective
var defenses: Array[DefenseUnit] = []
var selected_asset: DefenseUnit
var selected_track: PlayerTrack
var save_path: String = SaveStore.DEFAULT_PATH
var tactical_ui_refresh_remaining: float = 0.0
var game_mode: GameMode = GameMode.SUSTAINED

@onready var battlefield: Battlefield = $Battlefield
@onready var session: GameSession = $GameSession
@onready var player_knowledge: Node = $PlayerKnowledge
@onready var c2_network: Node = $C2Network
@onready var engagement_coordinator: EngagementCoordinator = $EngagementCoordinator
@onready var support_manager: SupportManager = $SupportManager
@onready var power_manager: PowerManager = $PowerManager
@onready var relocation_manager: RelocationManager = $RelocationManager
@onready var enemy_knowledge: EnemyKnowledge = $EnemyKnowledge
@onready var combat_audio: CombatAudio = $CombatAudio
@onready var ui_audio: UiAudio = $UiAudio
@onready var track_display: TrackDisplay = $WorldObjects/TacticalTracks
@onready var c2_overlay: C2Overlay = $WorldObjects/C2Overlay
@onready var tactical_range_overlay: Node = $WorldObjects/TacticalRangeOverlay
@onready var director: ThreatDirector = $ThreatDirector
@onready var training_controller: TrainingController = $TrainingController
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
@onready var altitude_profile: Control = $UI/AltitudeProfile

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
	c2_overlay.configure(c2_network, support_manager)
	tactical_range_overlay.call("configure", defense_parent, registry, support_manager)
	director.configure(scenario, battlefield, objective, registry, threat_parent, defense_parent, enemy_knowledge)
	placement.configure(session, battlefield, camera_rig.camera, defense_parent, projectile_parent, registry, relocation_manager)
	hud.configure(session, objective, scenario.available_defenses, _sandbox_threat_definitions(), game_mode)
	ui_audio.connect_buttons(hud)
	camera_rig.exclude_wheel_input_over(hud.get_node("Catalog") as Control)
	tactical_screen_overlay.configure(camera_rig.camera, player_knowledge, hud.training_panel)
	altitude_profile.call("configure", camera_rig.camera, player_knowledge, objective, scenario.battlefield_size)
	training_controller.configure(scenario, battlefield, objective, defenses, registry, director, session, hud, tactical_screen_overlay)
	_connect_flow()
	if game_mode == GameMode.TRAINING:
		training_controller.begin()
	elif game_mode == GameMode.SANDBOX:
		hud.set_feedback("방공 자산을 배치하거나 위협 투입 메뉴에서 공격을 구성하세요.", false)
	else:
		hud.set_feedback("방공 자산을 배치한 뒤 방어를 시작하세요.", false)

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
	support_manager.task_completed.connect(_on_support_task_completed)
	hud.defense_selected.connect(placement.select)
	hud.start_requested.connect(_on_start_requested)
	hud.speed_requested.connect(session.set_simulation_speed)
	hud.restart_requested.connect(_on_restart_requested)
	hud.main_menu_requested.connect(_on_main_menu_requested)
	placement.feedback_changed.connect(hud.set_feedback)
	placement.asset_selected.connect(_on_asset_selected)
	placement.world_selected.connect(_on_world_selected)
	placement.placement_preview_changed.connect(_on_placement_preview_changed)
	placement.placement_succeeded.connect(_on_placement_succeeded)
	placement.placement_rejected.connect(_on_placement_rejected)
	hud.overlay_requested.connect(_on_overlay_requested)
	hud.hold_fire_requested.connect(_on_hold_fire_requested)
	hud.engage_unknown_requested.connect(_on_engage_unknown_requested)
	hud.priority_target_requested.connect(_on_priority_target_requested)
	hud.munition_mode_requested.connect(_on_munition_mode_requested)
	hud.resupply_requested.connect(_on_resupply_requested)
	hud.repair_requested.connect(_on_repair_requested)
	hud.city_restoration_requested.connect(_on_city_restoration_requested)
	hud.relocation_requested.connect(_on_relocation_requested)
	hud.focus_requested.connect(_on_focus_requested)
	hud.training_next_requested.connect(_on_training_next_requested)
	hud.sandbox_threat_selected.connect(placement.select_sandbox_threat)
	placement.sandbox_threat_placement_requested.connect(_on_sandbox_threat_placement_requested)
	training_controller.selection_clear_requested.connect(_clear_selection)
	player_knowledge.connect("track_removed", _on_track_removed)
	objective.damage_received.connect(_on_objective_damage_audio)

func _on_start_requested() -> void:
	if game_mode == GameMode.TRAINING and not training_controller.can_start_defense():
		hud.set_feedback("현재 훈련 단계를 먼저 완료하세요")
		ui_audio.play_event(UiAudio.ACTION_REJECTED)
		return
	if session.start_defense():
		director.enabled = game_mode == GameMode.SUSTAINED
		if game_mode == GameMode.TRAINING:
			training_controller.defense_started()
		elif game_mode == GameMode.SANDBOX:
			hud.set_feedback("위협 투입 메뉴에서 공격을 추가할 수 있습니다.", false)
		else:
			hud.set_feedback("", false)

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
	unit.weapon_fired.connect(_on_weapon_fired)
	unit.projectile_launched.connect(_on_projectile_launched_audio)
	if game_mode == GameMode.TRAINING:
		training_controller.defense_placed(unit)

func _on_threat_spawned(threat: ThreatUnit) -> void:
	threat.configure_enemy_knowledge(enemy_knowledge)
	threat.resolved.connect(_on_threat_resolved)

func _on_threat_resolved(threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	enemy_knowledge.record_outcome(neutralized, threat.global_position, threat.definition.id)
	registry.remove(threat)
	session.register_threat_resolution(threat, neutralized, reward)
	if not neutralized and threat is AttackUav:
		var aircraft := threat as AttackUav
		if aircraft.mission_runtime.phase == ThreatMissionRuntime.Phase.EGRESS and aircraft.mission_runtime.effect_applied:
			threat.queue_free()
			return
	if neutralized and _leaves_falling_wreck(threat):
		_spawn_falling_wreck(threat)
	if _resolves_without_explosion(threat):
		threat.queue_free()
		return
	if not _is_city_impact(threat, neutralized):
		combat_audio.play_event(CombatAudio.EXPLOSION, 0.8 if neutralized else 1.0)
	_spawn_explosion(threat.global_position, Color("ff8c35") if neutralized else Color("ff3b24"), 10.0 if neutralized else 15.0)
	if game_mode == GameMode.TRAINING:
		training_controller.threat_resolved(threat)
	threat.queue_free()

func _leaves_falling_wreck(threat: ThreatUnit) -> bool:
	return threat.definition.signature_class in [&"uav", &"small_uav", &"aircraft", &"air_contact", &"bird"]

func _resolves_without_explosion(threat: ThreatUnit) -> bool:
	return threat.definition.signature_class == &"bird"

func _is_city_impact(threat: ThreatUnit, neutralized: bool) -> bool:
	if neutralized or not threat is AttackUav:
		return false
	var mission := (threat as AttackUav).mission_runtime.profile
	return mission != null and mission.type == ThreatMissionDefinition.Type.IMPACT

func _spawn_falling_wreck(threat: ThreatUnit) -> void:
	var effect := FALLING_WRECK_SCENE.instantiate() as Node3D
	effects_parent.add_child(effect)
	effect.global_position = threat.global_position
	var color := Color(0.45, 0.16, 0.1)
	var wreck_scale := 1.0
	var smoke_enabled := true
	var flash_enabled := true
	if threat.definition is AttackUavDefinition:
		color = (threat.definition as AttackUavDefinition).visual_color
	elif threat.definition.signature_class == &"bird":
		color = Color(0.23, 0.27, 0.29)
		wreck_scale = 0.42
		smoke_enabled = false
		flash_enabled = false
	var ground_height := battlefield.terrain_height(threat.global_position.x, threat.global_position.z)
	effect.call("setup", color, threat.presentation_velocity(), ground_height, wreck_scale, smoke_enabled, flash_enabled)

func _on_objective_depleted(_objective: ProtectedObjective) -> void:
	if not _objective.definition.required_for_survival:
		return
	director.enabled = false
	session.end_game()
	hud.set_final_stats(_final_statistics())
	placement.cancel()

func _on_pressure_changed(level: int) -> void:
	session.update_pressure(level)
	hud.set_pressure(level)

func _on_recovery_started(_completed_window: int) -> void:
	session.grant_attack_window_reward(scenario.attack_window_reward)

func _on_support_received(amount: int, reason: String) -> void:
	hud.set_feedback("예산 +$%d (%s)" % [amount, reason])

func _on_support_task_completed(_kind: StringName, _unit: DefenseUnit) -> void:
	ui_audio.play_event(UiAudio.ACTION_COMPLETE)

func _on_placement_succeeded() -> void:
	ui_audio.play_event(UiAudio.PLACEMENT_SUCCESS)

func _on_placement_rejected() -> void:
	ui_audio.play_event(UiAudio.ACTION_REJECTED)

func _on_weapon_fired(_unit: DefenseUnit, _low_resources: bool) -> void:
	session.register_weapon_fire()

func _on_projectile_launched_audio(unit: DefenseUnit, projectile: Node) -> void:
	var event_id := unit.definition.weapon_audio_event()
	if not event_id.is_empty():
		combat_audio.play_missile_event(event_id, projectile)

func _on_objective_damage_audio(_amount: int) -> void:
	combat_audio.play_event(CombatAudio.BIG_EXPLOSION)

func _spawn_explosion(position: Vector3, color: Color, radius: float) -> void:
	var effect := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	effects_parent.add_child(effect)
	effect.global_position = position
	effect.setup(color, radius)

func _final_statistics() -> Dictionary:
	var neutralized_parts: Array[String] = []
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		var count := int(session.neutralized_by_type.get(String(entry.threat_definition.id), 0))
		if count > 0:
			neutralized_parts.append("%s %d" % [entry.threat_definition.display_name, count])
	var operational_count := 0
	var asset_damage := 0
	for defense: DefenseUnit in defenses:
		if not is_instance_valid(defense):
			continue
		if defense.active:
			operational_count += 1
		asset_damage += roundi(defense.definition.maximum_integrity - defense.integrity)
	var neutralized_text := " · ".join(neutralized_parts.slice(0, mini(3, neutralized_parts.size()))) if not neutralized_parts.is_empty() else "없음"
	return {
		"summary": "생존  %02d:%02d\n방어 구간  %d\n최고 강도  %d\n도시 피해  %d" % [int(session.survival_time) / 60, int(session.survival_time) % 60, session.completed_attack_windows, session.highest_pressure, objective.definition.maximum_integrity - objective.current_integrity],
		"combat": "무력화  %d\n무기 운용  %d회\n\n주요 격추\n%s" % [session.neutralized_count, session.weapon_fire_count, neutralized_text],
		"network": "가동 자산  %d / %d\n자산 피해  %d\n\n방공망  $%d\n지원  $%d\n회수 보상  $%d" % [operational_count, session.defense_count, asset_damage, session.defense_spending, session.support_spending, session.neutralized_reward_total],
	}

func _on_restart_requested(same_seed: bool) -> void:
	var next_seed := scenario.world_seed if same_seed else generate_world_seed()
	requested_seed = next_seed
	if restart_game_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
		return
	restart_game_requested.emit(game_mode, next_seed)

func _on_main_menu_requested() -> void:
	main_menu_requested.emit()

func _on_asset_selected(unit: DefenseUnit) -> void:
	_set_selected_asset(unit)
	selected_track = null
	track_display.select_track(null)
	tactical_screen_overlay.select_track(null)
	c2_overlay.select_asset(unit)
	hud.set_selected_asset(unit, c2_overlay.visible_c2_link_count, c2_overlay.visible_support_link_count)
	hud.set_selected_track(null, false)
	if game_mode == GameMode.TRAINING:
		training_controller.asset_selected(unit)

func _on_placement_preview_changed(definition: DefenseDefinition, position: Vector3, active: bool) -> void:
	c2_overlay.preview_placement(definition, position, active)
	var added_demand := definition.placement_power_demand() if definition != null else 0.0
	var added_capacity := definition.placement_power_capacity() if definition != null else 0.0
	var screen_position := camera_rig.camera.unproject_position(position) if active and definition != null else Vector2.ZERO
	hud.set_placement_power_preview(power_manager.total_demand(), added_demand, power_manager.generation_capacity(), added_capacity, screen_position, active)

func _on_overlay_requested(mode: StringName) -> void:
	c2_overlay.set_all_links(mode == &"c2")
	tactical_range_overlay.call("set_mode", &"none" if mode == &"c2" else mode)
	if game_mode == GameMode.TRAINING:
		training_controller.overlay_selected(mode)

func _on_world_selected(position: Vector3, screen_position: Vector2 = Vector2.INF) -> void:
	var nearest_distance := 32.0
	selected_track = null
	var tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	if screen_position.is_finite():
		var nearest_screen_distance := 34.0
		for track: PlayerTrack in tracks:
			var track_screen_position: Vector2 = tactical_screen_overlay.call("track_marker_screen_position", track)
			if not track_screen_position.is_finite():
				continue
			var screen_distance := track_screen_position.distance_to(screen_position)
			if screen_distance < nearest_screen_distance:
				nearest_screen_distance = screen_distance
				selected_track = track
	if position.is_finite():
		for track: PlayerTrack in tracks:
			if selected_track != null:
				break
			var flat_distance := Vector2(track.estimated_position.x - position.x, track.estimated_position.z - position.z).length()
			if flat_distance < nearest_distance:
				nearest_distance = flat_distance
				selected_track = track
	if selected_track == null:
		_set_selected_asset(null)
		c2_overlay.select_asset(null)
		hud.set_selected_asset(null, 0)
	elif selected_asset != null and not selected_asset.supports_engagement_controls():
		_set_selected_asset(null)
		c2_overlay.select_asset(null)
		hud.set_selected_asset(null, 0)
	track_display.select_track(selected_track)
	track_display.select_engagement_source(selected_asset)
	tactical_screen_overlay.select_track(selected_track)
	_refresh_selected_track_panel()
	if game_mode == GameMode.TRAINING:
		training_controller.track_selected(selected_track)

func _refresh_selected_track_panel() -> void:
	var details := track_display.selection_details()
	hud.set_selected_track(selected_track, selected_asset != null and selected_asset.supports_engagement_controls(), int(details.sensor_count), int(details.engagement_count))

func _refresh_tactical_ui() -> void:
	var hostile_count := 0
	var selectable_hostile_count := 0
	for track: PlayerTrack in player_knowledge.call("get_active_tracks"):
		if track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3:
			hostile_count += 1
			if track.state != PlayerTrack.State.TENTATIVE:
				selectable_hostile_count += 1
	var warnings: Array[String] = []
	var depleted_count := 0
	var disabled_count := 0
	for defense: DefenseUnit in defenses:
		if not is_instance_valid(defense):
			continue
		if not defense.active:
			disabled_count += 1
		if defense.combat_resource_depleted():
			depleted_count += 1
	if depleted_count > 0:
		warnings.append("탄약 고갈 %d" % depleted_count)
	if disabled_count > 0:
		warnings.append("기능 정지 %d" % disabled_count)
	if objective != null and objective.current_integrity <= objective.definition.maximum_integrity * 0.3:
		warnings.append("도시 기능 위험")
	hud.set_tactical_alert(hostile_count, engagement_coordinator.reservations.size(), warnings)
	if game_mode == GameMode.TRAINING:
		training_controller.tracks_refreshed(selectable_hostile_count)
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
	if selected_asset != null and selected_asset.supports_engagement_controls():
		selected_asset.set_hold_fire(enabled)
		if game_mode == GameMode.TRAINING:
			training_controller.hold_fire_changed(enabled)

func _on_engage_unknown_requested(enabled: bool) -> void:
	if selected_asset != null and selected_asset.supports_engagement_controls():
		selected_asset.set_engage_unknown(enabled)

func _on_priority_target_requested() -> void:
	if selected_asset != null and selected_track != null and selected_asset.supports_engagement_controls():
		selected_asset.set_priority_track(selected_track.track_id)
		hud.set_feedback("항적을 우선표적으로 지정했습니다")

func _on_munition_mode_requested() -> void:
	if selected_asset != null and selected_asset.supports_munition_selection():
		selected_asset.cycle_munition_mode()
		hud.set_feedback("탄종 운용 모드를 변경했습니다")

func _on_resupply_requested() -> void:
	var requested := selected_asset != null and selected_asset.request_resupply()
	if requested:
		hud.set_feedback("재보급 작업을 요청했습니다")
	else:
		hud.set_feedback("현재 재보급을 요청할 수 없습니다")
		ui_audio.play_event(UiAudio.ACTION_REJECTED)
	if game_mode == GameMode.TRAINING:
		training_controller.resupply_requested(requested)

func _on_repair_requested() -> void:
	if selected_asset != null and selected_asset.request_repair():
		hud.set_feedback("수리 작업을 요청했습니다")
	else:
		hud.set_feedback("현재 수리를 요청할 수 없습니다")
		ui_audio.play_event(UiAudio.ACTION_REJECTED)

func _on_city_restoration_requested() -> void:
	var definition := objective.definition
	if objective.current_integrity >= definition.maximum_integrity:
		hud.set_feedback("도시 기능이 이미 최대입니다")
		ui_audio.play_event(UiAudio.ACTION_REJECTED)
		return
	if not session.try_spend(definition.restoration_cost):
		hud.set_feedback("도시 복구 예산이 부족합니다")
		ui_audio.play_event(UiAudio.ACTION_REJECTED)
		return
	var restored := mini(definition.restoration_amount, definition.maximum_integrity - objective.current_integrity)
	objective.restore_integrity(objective.current_integrity + restored)
	hud.set_feedback("도시 기능을 %d 복구했습니다" % restored)
	ui_audio.play_event(UiAudio.ACTION_COMPLETE)

func _on_relocation_requested() -> void:
	if selected_asset != null and selected_asset.can_request_relocation():
		placement.select_relocation(selected_asset)
	else:
		hud.set_feedback("현재 재배치할 수 없습니다")
		ui_audio.play_event(UiAudio.ACTION_REJECTED)

func save_operation() -> String:
	if game_mode != GameMode.SUSTAINED:
		return "저장은 지속 작전에서만 사용할 수 있습니다"
	return SaveStore.write(capture_save_document(), save_path)

func load_operation() -> String:
	if game_mode != GameMode.SUSTAINED:
		return "불러오기는 지속 작전에서만 사용할 수 있습니다"
	var result := SaveStore.read(save_path)
	var error: String = result.error
	if error.is_empty():
		error = restore_from_document(result.document)
	return error

func capture_save_document() -> Dictionary:
	return SaveDocument.create(SessionSnapshot.capture_payload(self))

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

func _on_training_next_requested() -> void:
	if game_mode == GameMode.TRAINING:
		training_controller.next_requested()

func _clear_selection() -> void:
	_set_selected_asset(null)
	selected_track = null
	track_display.select_track(null)
	track_display.select_engagement_source(null)
	tactical_screen_overlay.select_track(null)
	c2_overlay.select_asset(null)
	hud.set_selected_asset(null, 0)
	hud.set_selected_track(null, false)

func _set_selected_asset(unit: DefenseUnit) -> void:
	if selected_asset != null and is_instance_valid(selected_asset):
		selected_asset.set_selected(false)
	selected_asset = unit
	if selected_asset != null and is_instance_valid(selected_asset):
		selected_asset.set_selected(true)

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
	objective.restore_damage_smoke_state(world_state.get("objective_damage_smoke", []))
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
	var restored_tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	engagement_coordinator.restore_state(world_state.engagements)
	support_manager.restore_state(world_state.support)
	relocation_manager.restore_state(world_state.relocations)
	enemy_knowledge.restore_state(world_state.enemy_knowledge)
	for state: Dictionary in world_state.projectiles:
		if String(state.type) == "air_strike_munition":
			var strike_munition := AIR_STRIKE_MUNITION_SCENE.instantiate() as Node3D
			threat_parent.add_child(strike_munition)
			strike_munition.call("restore_state", state, objective)
			continue
		var target_track: PlayerTrack = player_knowledge.call("find_track", int(state.target_track_id))
		if String(state.type) == "homing_interceptor":
			var owner := _find_defense(int(state.owner_defense_id)) as MissileBattery
			var interceptor := HOMING_INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
			projectile_parent.add_child(interceptor)
			interceptor.restore_state(state, target_track, registry, restored_tracks, battlefield)
			interceptor.target_changed.connect(owner._on_interceptor_target_changed)
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
	_set_selected_asset(null)
	selected_track = null
	track_display.select_track(null)
	track_display.select_engagement_source(null)
	tactical_screen_overlay.select_track(null)
	c2_overlay.select_asset(null)
	hud.set_selected_asset(null, 0)
	hud.set_selected_track(null, false)
