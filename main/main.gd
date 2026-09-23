class_name AirscainMain
extends Node3D

enum GameMode { SUSTAINED, TRAINING, SANDBOX }

signal restart_game_requested(mode: GameMode, world_seed: int, battlefield_layout_id: StringName)
signal main_menu_requested

const BASE_SCENARIO := preload("res://main/first_scenario.tres")
const MAXIMUM_GAMEPLAY_STEP := 1.0 / 30.0

static var requested_seed: int = -1
static var requested_mode: GameMode = GameMode.SUSTAINED
static var requested_layout_id: StringName = &""
static var last_generated_seed: int = -1

static func generate_world_seed() -> int:
	var generated := (int(Time.get_unix_time_from_system() * 1000.0) ^ int(Time.get_ticks_usec())) & 0x7fffffff
	if generated == last_generated_seed:
		generated = (generated + 1) & 0x7fffffff
	last_generated_seed = generated
	return generated

var auto_start_sustained: bool = true

var scenario: ScenarioDefinition
var registry := ThreatRegistry.new()
var objective: ProtectedObjective
var defenses: Array[DefenseUnit] = []
var selected_asset: DefenseUnit
var selected_track: PlayerTrack
var save_path: String = SaveStore.DEFAULT_PATH
var tactical_ui_refresh_remaining: float = 0.0
var game_mode: GameMode = GameMode.SUSTAINED
var combat_effect_pool: CombatEffectPool
var radar_tracking_coordinator := RadarTrackingCoordinator.new()
var last_persistence_repairs: Array[String] = []
var briefing_panel: OperationBriefingPanel
var speed_before_briefing: float = 1.0
var harbor_port: HarborPort

@onready var battlefield: Battlefield = $Battlefield
@onready var session: GameSession = $GameSession
@onready var player_knowledge: PlayerKnowledge = $PlayerKnowledge
@onready var c2_network: C2Network = $C2Network
@onready var engagement_coordinator: EngagementCoordinator = $EngagementCoordinator
@onready var support_manager: SupportManager = $SupportManager
@onready var power_manager: PowerManager = $PowerManager
@onready var relocation_manager: RelocationManager = $RelocationManager
@onready var enemy_knowledge: EnemyKnowledge = $EnemyKnowledge
@onready var combat_audio: CombatAudio = $CombatAudio
@onready var resolution_effects: ThreatResolutionEffects = $ThreatResolutionEffects
@onready var ui_audio: UiAudio = $UiAudio
@onready var track_display: TrackDisplay = $WorldObjects/TacticalTracks
@onready var c2_overlay: C2Overlay = $WorldObjects/C2Overlay
@onready var tactical_range_overlay: TacticalRangeOverlay = $WorldObjects/TacticalRangeOverlay
@onready var director: ThreatDirector = $ThreatDirector
@onready var training_controller: TrainingController = $TrainingController
@onready var briefing_controller: OperationBriefingController = $OperationBriefingController
@onready var camera_rig: CameraRig = $CameraRig
@onready var world_objects: Node3D = $WorldObjects
@onready var objectives: Node3D = $WorldObjects/Objectives
@onready var defense_parent: Node3D = $WorldObjects/Defenses
@onready var threat_parent: Node3D = $WorldObjects/Threats
@onready var projectile_parent: Node3D = $WorldObjects/Projectiles
@onready var effects_parent: Node3D = $WorldObjects/Effects
@onready var placement: PlacementController = $PlacementController
@onready var hud: Hud = $UI/HUD
@onready var tactical_screen_overlay: TacticalScreenOverlay = $UI/TacticalScreenOverlay
@onready var altitude_profile: AltitudeProfile = $UI/AltitudeProfile

var day_night := DayNightCycle.new()

func _ready() -> void:
	scenario = BASE_SCENARIO.duplicate(true) as ScenarioDefinition
	game_mode = requested_mode
	if requested_seed >= 0:
		scenario.world_seed = requested_seed
	scenario.selected_battlefield_layout_id = requested_layout_id
	requested_seed = scenario.world_seed
	var scenario_error := scenario.validation_error()
	if not scenario_error.is_empty():
		push_error("시나리오를 시작할 수 없습니다: %s" % scenario_error)
		get_tree().quit(1)
		return
	battlefield.build(scenario)
	resolution_effects.configure(battlefield, effects_parent, combat_audio)
	add_child(day_night)
	day_night.configure($Sun, $WorldEnvironment, battlefield)
	camera_rig.configure_for_battlefield(scenario.battlefield_size, battlefield.terrain_height)
	_spawn_objective()
	_spawn_ambient_contacts()
	session.reset(scenario.starting_budget + scenario.battlefield_layout().starting_budget_bonus, scenario.support_interval, scenario.support_amount)
	if game_mode == GameMode.SUSTAINED:
		_create_harbor_port()
	if game_mode == GameMode.TRAINING:
		session.budget = 2500
	elif game_mode == GameMode.SANDBOX:
		session.configure_free_play()
	support_manager.configure(session, TrainingController.REPAIR_DURATION_LIMIT if game_mode == GameMode.TRAINING else INF)
	relocation_manager.configure(battlefield)
	enemy_knowledge.reset()
	player_knowledge.reset()
	radar_tracking_coordinator.reset()
	c2_network.reset()
	c2_network.configure(registry)
	track_display.configure(player_knowledge, defense_parent, engagement_coordinator)
	var range_label_obstacles: Array[Control] = [hud.catalog, hud.city_menu, hud.selected_asset_panel, hud.placement_hint_panel, hud.training_panel, altitude_profile]
	c2_overlay.configure(c2_network, support_manager, range_label_obstacles, battlefield)
	tactical_range_overlay.configure(defense_parent, registry, support_manager, battlefield)
	director.configure(scenario, battlefield, objective, registry, threat_parent, defense_parent, enemy_knowledge)
	placement.configure(session, battlefield, camera_rig.camera, defense_parent, projectile_parent, registry, relocation_manager, range_label_obstacles, game_mode != GameMode.TRAINING)
	hud.configure(session, objective, scenario.available_defenses, _sandbox_threat_definitions(), game_mode)
	if game_mode == GameMode.SANDBOX:
		hud.set_pressure(0)
	ui_audio.connect_buttons(hud)
	camera_rig.exclude_wheel_input_over(hud.get_node("Catalog") as Control)
	tactical_screen_overlay.configure(camera_rig.camera, player_knowledge, hud.training_panel)
	tactical_screen_overlay.placement = placement
	altitude_profile.configure(camera_rig.camera, player_knowledge, objective, scenario.battlefield_size)
	training_controller.configure(scenario, battlefield, objective, defenses, registry, director, session, hud, tactical_screen_overlay, c2_network)
	briefing_controller.configure(scenario, game_mode == GameMode.SUSTAINED)
	if game_mode == GameMode.SUSTAINED:
		briefing_panel = OperationBriefingPanel.new()
		hud.add_child(briefing_panel)
		briefing_panel.configure(scenario)
	_connect_flow()
	_deploy_initial_defenses()
	if game_mode == GameMode.TRAINING:
		var guidance := TrainingGuidance.new()
		guidance.name = "TrainingGuidance"
		hud.add_child(guidance)
		guidance.configure(training_controller, placement, camera_rig)
	elif game_mode == GameMode.SANDBOX:
		hud.set_feedback(tr("방공 자산을 배치하거나 위협 투입 메뉴에서 공격을 구성하세요."), false)
	else:
		hud.set_feedback(tr("적이 외곽에서 접근합니다. 방공 자산을 배치하세요."), false)
	combat_effect_pool = CombatEffectPool.new()
	effects_parent.add_child(combat_effect_pool)
	_prepare_combat_visuals()

func _prepare_combat_visuals() -> void:
	var blocker: CanvasLayer
	if DisplayServer.get_name() != "headless":
		blocker = CanvasLayer.new()
		blocker.layer = 100
		add_child(blocker)
		var panel := ColorRect.new()
		panel.color = Color("0b1b23")
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		blocker.add_child(panel)
		var label := Label.new()
		label.text = tr("전장 효과 준비 중…")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(label)
		await hud.prepare_result_visuals(_final_statistics())
	await combat_effect_pool.prepare(objective.prepared_smoke_effects, scenario, battlefield)
	if game_mode == GameMode.TRAINING:
		training_controller.begin()
	if game_mode == GameMode.SUSTAINED and auto_start_sustained and session.phase == GameSession.Phase.PREPARATION:
		_on_start_requested()
		director.launch_budgeted_raid()
		director._tick_pending_waves(0.0)
		director.until_spawn = director.automatic_raid_interval_at(0.0)
		hud.set_feedback(tr("적이 외곽에서 접근합니다. 방공 자산을 배치하세요."), false)
		briefing_controller.pressure_reached(director.pressure_level)
	if blocker != null:
		blocker.queue_free()

func _process(delta: float) -> void:
	if combat_effect_pool != null and not combat_effect_pool.prepared:
		return
	tactical_ui_refresh_remaining -= delta
	if tactical_ui_refresh_remaining <= 0.0:
		tactical_ui_refresh_remaining += 0.2
		_refresh_tactical_ui()
	var simulation_delta := session.gameplay_delta(delta)
	if harbor_port != null:
		harbor_port.update_at_time(session.survival_time)
	day_night.apply_time(session.survival_time)
	combat_audio.simulation_paused = simulation_delta <= 0.0
	combat_audio.simulation_rate = session.simulation_speed
	if simulation_delta <= 0.0:
		return
	var gameplay_step_count := ceili(simulation_delta / MAXIMUM_GAMEPLAY_STEP)
	var gameplay_step := simulation_delta / float(gameplay_step_count)
	for _step_index: int in gameplay_step_count:
		_gameplay_step(gameplay_step)

func _gameplay_step(delta: float) -> void:
	director.gameplay_tick(delta)
	player_knowledge.gameplay_tick(delta)
	c2_network.gameplay_tick(delta)
	engagement_coordinator.gameplay_tick(delta)
	support_manager.gameplay_tick(delta)
	relocation_manager.gameplay_tick(delta)
	enemy_knowledge.gameplay_tick(delta)
	power_manager.begin_tick()
	for defense: DefenseUnit in defenses:
		if is_instance_valid(defense):
			defense.gameplay_tick(delta)
	for threat: ThreatUnit in registry.get_active():
		threat.gameplay_tick(delta)
	for munition: AirStrikeMunition in get_tree().get_nodes_in_group(AirStrikeMunition.SIMULATION_GROUP):
		if munition.get_parent() == threat_parent and not munition.is_queued_for_deletion():
			munition.gameplay_tick(delta)

func _spawn_objective() -> void:
	objective = scenario.objective_definition.scene.instantiate() as ProtectedObjective
	objectives.add_child(objective)
	battlefield.align_primary_city_objective(objective)
	objective.exclusion_radius = scenario.city_size * 0.5
	objective.setup(1, scenario.objective_definition)
	battlefield.set_objective(objective)

func _create_harbor_port() -> void:
	objective.impact_redirect = Callable()
	director.harbor_port = null
	tactical_screen_overlay.harbor_port = null
	if harbor_port != null:
		harbor_port.free()
	harbor_port = HarborPort.new()
	harbor_port.name = "HarborPort"
	world_objects.add_child(harbor_port)
	if harbor_port.configure(battlefield, session):
		session.external_regular_support = true
		objective.impact_redirect = Callable(harbor_port, "try_apply_impact")
		director.harbor_port = harbor_port
		harbor_port.struck.connect(_on_harbor_struck)
	else:
		push_warning("이 전장에 안전한 항구 항로를 찾지 못해 기존 정기 지원을 사용합니다")
		harbor_port.free()
		harbor_port = null
		session.external_regular_support = false
	tactical_screen_overlay.harbor_port = harbor_port

func _on_harbor_struck() -> void:
	hud.set_feedback(tr("항구 피격: 하역이 중단되어 정기 지원이 끊깁니다. 긴급 복구가 진행 중입니다."), true)

func _deploy_initial_defenses() -> void:
	for mount: Dictionary in objective.initial_defense_mounts():
		for definition: DefenseDefinition in scenario.available_defenses:
			if definition.id == mount.definition_id:
				var result := session.deploy_initial_defense(definition, mount.position, float(mount.get("rotation_y", 0.0)), battlefield, defense_parent, registry, projectile_parent)
				if not result.success:
					push_error("초기 방공 자산 생성 실패: %s" % result.reason)
				break

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
	support_manager.task_requested.connect(training_controller.support_requested)
	relocation_manager.relocation_started.connect(training_controller.relocation_started)
	relocation_manager.relocation_completed.connect(training_controller.relocation_completed)
	hud.defense_selected.connect(placement.select)
	hud.start_requested.connect(_on_start_requested)
	hud.speed_requested.connect(session.set_simulation_speed)
	hud.restart_requested.connect(_on_restart_requested)
	hud.main_menu_requested.connect(_on_main_menu_requested)
	placement.feedback_changed.connect(hud.set_feedback)
	placement.placement_status_changed.connect(hud.set_placement_status)
	placement.asset_selected.connect(_on_asset_selected)
	placement.world_selected.connect(_on_world_selected)
	placement.placement_preview_changed.connect(_on_placement_preview_changed)
	placement.placement_succeeded.connect(_on_placement_succeeded)
	placement.placement_rejected.connect(_on_placement_rejected)
	hud.overlay_requested.connect(_on_overlay_requested)
	hud.hold_fire_requested.connect(_on_hold_fire_requested)
	hud.engage_unknown_requested.connect(_on_engage_unknown_requested)
	hud.target_kind_requested.connect(_on_target_kind_requested)
	hud.munition_mode_requested.connect(_on_munition_mode_requested)
	hud.resupply_requested.connect(_on_resupply_requested)
	hud.automatic_resupply_requested.connect(_on_automatic_resupply_requested)
	hud.repair_requested.connect(_on_repair_requested)
	hud.city_restoration_requested.connect(_on_city_restoration_requested)
	hud.relocation_requested.connect(_on_relocation_requested)
	hud.focus_requested.connect(_on_focus_requested)
	hud.training_next_requested.connect(_on_training_next_requested)
	hud.sandbox_threat_selected.connect(placement.select_sandbox_threat)
	placement.sandbox_threat_placement_requested.connect(_on_sandbox_threat_placement_requested)
	training_controller.selection_clear_requested.connect(_clear_selection)
	briefing_controller.briefing_delivered.connect(_on_briefing_delivered)
	if briefing_panel != null:
		briefing_panel.closed.connect(_on_briefing_closed)
		briefing_panel.deploy_requested.connect(_on_briefing_deploy_requested)
	player_knowledge.connect("track_removed", _on_track_removed)
	player_knowledge.connect("track_created", _on_track_contact_audio)
	objective.damage_received.connect(_on_objective_damage_audio)

func _on_start_requested() -> void:
	if session.start_defense():
		director.enabled = game_mode == GameMode.SUSTAINED
		if game_mode == GameMode.SANDBOX:
			hud.set_feedback(tr("위협 투입 메뉴에서 공격을 추가할 수 있습니다."), false)
		else:
			hud.set_feedback("", false)

func _on_defense_placed(unit: DefenseUnit) -> void:
	defenses.append(unit)
	unit.configure_player_knowledge(battlefield, player_knowledge)
	c2_network.register_asset(unit)
	unit.configure_c2(c2_network)
	unit.configure_audio(combat_audio)
	unit.configure_engagements(engagement_coordinator)
	unit.configure_sensor_tracking(radar_tracking_coordinator)
	unit.configure_support(support_manager)
	unit.configure_power(power_manager)
	unit.configure_relocation(relocation_manager)
	unit.configure_enemy_knowledge(enemy_knowledge)
	support_manager.register_asset(unit)
	power_manager.register_asset(unit)
	relocation_manager.register_asset(unit)
	_refresh_power_status()
	unit.weapon_fired.connect(_on_weapon_fired)
	unit.damage_received.connect(_on_defense_damage_audio)
	unit.projectile_launched.connect(_on_projectile_launched_audio)
	if game_mode == GameMode.TRAINING:
		training_controller.defense_placed(unit)

func _on_threat_spawned(threat: ThreatUnit) -> void:
	var haze := DistantContactHaze.new()
	threat.add_child(haze)
	haze.configure(threat, scenario.battlefield_size)
	combat_audio.register_threat(threat)
	director.bind_releases(threat)
	threat.configure_enemy_knowledge(enemy_knowledge)
	threat.resolved.connect(_on_threat_resolved)

func _on_threat_resolved(threat: ThreatUnit, neutralized: bool, reward: int) -> void:
	enemy_knowledge.record_outcome(neutralized, threat.global_position, threat.definition.id, threat.mission_result())
	registry.remove(threat)
	session.register_threat_resolution(threat, neutralized, reward)
	if not neutralized and threat.exits_without_impact():
		threat.queue_free()
		return
	resolution_effects.present(threat, neutralized)
	if game_mode == GameMode.TRAINING and threat.definition.has_resolution_explosion():
		training_controller.threat_resolved(threat)
	threat.queue_free()


func _on_objective_depleted(_objective: ProtectedObjective) -> void:
	if not _objective.definition.required_for_survival:
		return
	director.enabled = false
	combat_audio.stop_all()
	session.end_game()
	hud.set_final_stats(_final_statistics())
	placement.cancel()

func _on_pressure_changed(level: int) -> void:
	if game_mode == GameMode.SANDBOX:
		return
	session.update_pressure(level)
	hud.set_pressure(level)
	combat_audio.play_event(CombatAudio.PRESSURE, clampf(0.45 + float(level) * 0.04, 0.45, 1.0))
	if session.phase == GameSession.Phase.RUNNING:
		briefing_controller.pressure_reached(level)

func _on_briefing_delivered(briefing: OperationBriefingDefinition) -> void:
	if briefing_panel == null or session.phase != GameSession.Phase.RUNNING:
		return
	if not bool(PlayerSettings.instance().values.get("briefings", true)):
		hud.set_feedback(tr("새 작전 첩보: %s  ·  Esc 메뉴에서 확인") % tr(briefing.title))
		return
	if not briefing_panel.visible:
		speed_before_briefing = session.simulation_speed
	session.set_simulation_speed(0.0)
	placement.cancel()
	hud.close_context_menus()
	camera_rig.input_blocked = true
	briefing_panel.present_delivered(briefing_controller.delivered_briefings(), briefing)

## Shows delivered briefings over the pause menu; the caller restores its own menu on close.
func open_briefing_archive() -> bool:
	if briefing_panel == null or briefing_controller.delivered_ids.is_empty():
		return false
	briefing_panel.present_archive(briefing_controller.delivered_briefings())
	return true

## New briefings pause the operation; the archive runs under the pause menu, which owns time and camera.
func _on_briefing_closed(archive: bool) -> void:
	if archive:
		return
	camera_rig.input_blocked = false
	session.set_simulation_speed(speed_before_briefing)

func _on_briefing_deploy_requested(defense_ids: Array[StringName]) -> void:
	hud.set_catalog_expanded(true)
	hud.highlight_new_defenses(defense_ids)

func _on_recovery_started(_completed_window: int) -> void:
	session.grant_attack_window_reward(scenario.attack_window_reward)

func _on_support_received(amount: int, reason: String) -> void:
	hud.set_feedback(tr("예산 +$%d (%s)") % [amount, tr(reason)])

func _on_support_task_completed(kind: StringName, unit: DefenseUnit, user_requested: bool) -> void:
	if user_requested:
		ui_audio.play_event(UiAudio.ACTION_COMPLETE)
	if game_mode == GameMode.TRAINING:
		training_controller.support_completed(kind, unit)

func _on_placement_succeeded() -> void:
	ui_audio.play_event(UiAudio.PLACEMENT_SUCCESS)

func _on_placement_rejected() -> void:
	ui_audio.play_event(UiAudio.ACTION_REJECTED)

func _on_track_contact_audio(_track: PlayerTrack) -> void:
	combat_audio.play_event(CombatAudio.CONTACT, 0.55)

func _on_weapon_fired(_unit: DefenseUnit, low_resources: bool) -> void:
	session.register_weapon_fire()
	if low_resources:
		combat_audio.play_event(CombatAudio.LOW_AMMO, 0.7)

func _on_defense_damage_audio(_unit: DefenseUnit, _amount: float, integrity_ratio: float) -> void:
	combat_audio.play_event(CombatAudio.DAMAGE, clampf(1.1 - integrity_ratio, 0.45, 1.0))

func _on_projectile_launched_audio(unit: DefenseUnit, projectile: Node) -> void:
	var event_id := unit.definition.weapon_audio_event()
	if not event_id.is_empty():
		combat_audio.play_missile_event(event_id, projectile)

func _on_objective_damage_audio(_amount: int) -> void:
	combat_audio.play_event(CombatAudio.BIG_EXPLOSION)

func _final_statistics() -> Dictionary:
	var neutralized_entries: Array[Dictionary] = []
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		var count := int(session.neutralized_by_type.get(String(entry.threat_definition.id), 0))
		if count > 0:
			neutralized_entries.append({
				"name": entry.threat_definition.display_name,
				"count": count,
				"reward": entry.threat_definition.neutralization_reward,
			})
	neutralized_entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if first.count != second.count:
			return first.count > second.count
		if first.reward != second.reward:
			return first.reward > second.reward
		return String(first.name) < String(second.name)
	)
	var neutralized_parts: Array[String] = []
	for entry: Dictionary in neutralized_entries.slice(0, mini(3, neutralized_entries.size())):
		neutralized_parts.append("%s %d" % [tr(String(entry.name)), entry.count])
	var operational_count := 0
	var asset_damage := 0
	for defense: DefenseUnit in defenses:
		if not is_instance_valid(defense):
			continue
		if defense.active:
			operational_count += 1
		asset_damage += roundi(defense.definition.maximum_integrity - defense.integrity)
	var neutralized_text := "\n".join(neutralized_parts) if not neutralized_parts.is_empty() else tr("없음")
	if neutralized_entries.size() > neutralized_parts.size():
		neutralized_text += tr("\n그 외 %d종") % (neutralized_entries.size() - neutralized_parts.size())
	return {
		"summary": tr("방어 구간  %d\n최고 강도  %d\n도시 피해  %d") % [session.completed_attack_windows, session.highest_pressure, objective.definition.maximum_integrity - objective.current_integrity],
		"combat": tr("무력화  %d\n무기 운용  %d회\n\n주요 격추 · 상위 3종\n%s") % [session.neutralized_count, session.weapon_fire_count, neutralized_text],
		"network": tr("가동 자산  %d / %d\n자산 피해  %d\n\n방공망  $%d\n지원  $%d\n회수 보상  $%d") % [operational_count, session.defense_count, asset_damage, session.defense_spending, session.support_spending, session.neutralized_reward_total],
	}

func _on_restart_requested(same_seed: bool) -> void:
	var next_seed := scenario.world_seed if same_seed else generate_world_seed()
	requested_seed = next_seed
	if restart_game_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
		return
	restart_game_requested.emit(game_mode, next_seed, scenario.selected_battlefield_layout_id)

func _on_main_menu_requested() -> void:
	main_menu_requested.emit()

func _on_asset_selected(unit: DefenseUnit) -> void:
	_set_selected_asset(unit)
	selected_track = null
	track_display.select_track(null)
	tactical_screen_overlay.select_track(null)
	c2_overlay.select_asset(unit)
	hud.set_selected_asset(unit, c2_overlay.visible_c2_link_count, c2_overlay.visible_support_link_count)
	hud.set_selected_track(null)

func _on_placement_preview_changed(definition: DefenseDefinition, position: Vector3, active: bool) -> void:
	c2_overlay.preview_placement(definition, position, active)
	tactical_range_overlay.preview_placement(definition, position, active)
	var added_demand := definition.placement_power_demand() if definition != null else 0.0
	var added_capacity := definition.placement_power_capacity() if definition != null else 0.0
	var screen_position := camera_rig.camera.unproject_position(position) if active and definition != null else Vector2.ZERO
	hud.set_placement_power_preview(power_manager.total_demand(), added_demand, power_manager.generation_capacity(), added_capacity, screen_position, active)

func _on_overlay_requested(mode: StringName) -> void:
	tactical_range_overlay.set_mode(mode)

func _on_world_selected(position: Vector3, screen_position: Vector2 = Vector2.INF) -> void:
	var nearest_distance := 32.0
	selected_track = null
	var tracks: Array[PlayerTrack] = player_knowledge.get_active_tracks()
	if screen_position.is_finite():
		selected_track = tactical_screen_overlay.track_at_screen(screen_position)
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
	hud.set_selected_track(selected_track, int(details.sensor_count), int(details.engagement_count))

func _refresh_tactical_ui() -> void:
	_refresh_power_status()
	var hostile_count := 0
	var selectable_hostile_count := 0
	for track: PlayerTrack in player_knowledge.get_active_tracks():
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
		warnings.append(tr("탄약 고갈 %d") % depleted_count)
	if disabled_count > 0:
		warnings.append(tr("기능 정지 %d") % disabled_count)
	if objective != null and objective.current_integrity <= objective.definition.maximum_integrity * 0.3:
		warnings.append(tr("도시 기능 위험"))
	hud.set_tactical_alert(hostile_count, engagement_coordinator.total_reservations(), warnings)
	if game_mode == GameMode.TRAINING:
		training_controller.tracks_refreshed(selectable_hostile_count)
	if selected_track != null:
		_refresh_selected_track_panel()

func _refresh_power_status() -> void:
	hud.set_power_status(power_manager.total_demand(), power_manager.generation_capacity())

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

func _on_engage_unknown_requested(enabled: bool) -> void:
	if selected_asset != null and selected_asset.supports_engagement_controls():
		selected_asset.set_engage_unknown(enabled)

func _on_munition_mode_requested(mode: StringName) -> void:
	if selected_asset != null and selected_asset.supports_munition_selection():
		selected_asset.set_munition_mode(mode)
		hud.refresh_selected_asset()
		hud.set_feedback(tr("탄종 운용 모드를 변경했습니다"))

func _on_resupply_requested() -> void:
	var requested := selected_asset != null and selected_asset.request_resupply()
	if requested:
		hud.set_feedback(tr("재보급 작업을 요청했습니다"))
	else:
		hud.set_feedback(tr("현재 재보급을 요청할 수 없습니다"))
		ui_audio.play_event(UiAudio.ACTION_REJECTED)

func _on_automatic_resupply_requested(enabled: bool) -> void:
	if not is_instance_valid(selected_asset) or not selected_asset.uses_ammunition():
		return
	selected_asset.set_automatic_resupply(enabled)
	hud.refresh_selected_asset()
	hud.set_feedback(tr("자동 재보급 켜짐") if enabled else tr("자동 재보급 꺼짐"))

func _on_repair_requested() -> void:
	var requested := selected_asset != null and selected_asset.request_repair()
	if requested:
		hud.set_feedback(tr("수리 작업을 요청했습니다"))
	else:
		hud.set_feedback(tr("현재 수리를 요청할 수 없습니다"))
		ui_audio.play_event(UiAudio.ACTION_REJECTED)

func _on_city_restoration_requested() -> void:
	var definition := objective.definition
	if objective.current_integrity >= definition.maximum_integrity:
		hud.set_feedback(tr("도시 기능이 이미 최대입니다"))
		ui_audio.play_event(UiAudio.ACTION_REJECTED)
		return
	if not session.try_spend(definition.restoration_cost):
		hud.set_feedback(tr("도시 복구 예산이 부족합니다"))
		ui_audio.play_event(UiAudio.ACTION_REJECTED)
		return
	var restored := mini(definition.restoration_amount, definition.maximum_integrity - objective.current_integrity)
	objective.restore_integrity(objective.current_integrity + restored)
	hud.show_city_restoration(restored)
	hud.set_feedback(tr("도시 기능을 %d 복구했습니다") % restored)
	ui_audio.play_event(UiAudio.ACTION_COMPLETE)
	if game_mode == GameMode.TRAINING:
		training_controller.city_restored()

func _on_relocation_requested() -> void:
	if selected_asset != null and selected_asset.can_request_relocation():
		placement.select_relocation(selected_asset)
	else:
		hud.set_feedback(tr("현재 재배치할 수 없습니다"))
		ui_audio.play_event(UiAudio.ACTION_REJECTED)

func save_operation() -> String:
	if game_mode != GameMode.SUSTAINED:
		return tr("저장은 지속 작전에서만 사용할 수 있습니다")
	var document := capture_save_document()
	var prepared := SessionSnapshot.prepare(document.payload, scenario)
	last_persistence_repairs.assign(prepared.repairs)
	if not prepared.error.is_empty():
		return prepared.error
	document.payload = prepared.payload
	_report_persistence_repairs(PersistenceFeedback.Action.SAVE)
	return SaveStore.write(document, save_path)

func load_operation() -> String:
	last_persistence_repairs.clear()
	if game_mode != GameMode.SUSTAINED:
		return tr("불러오기는 지속 작전에서만 사용할 수 있습니다")
	var result := SaveStore.read(save_path)
	var error: String = result.error
	if error.is_empty():
		error = restore_from_document(result.document)
	if error.is_empty():
		return ""
	var primary_error := error
	var backup := SaveStore.read_backup(save_path)
	error = backup.error
	if error.is_empty():
		error = restore_from_document(backup.document)
	if error.is_empty():
		record_backup_recovery()
		return ""
	return SaveStore.combined_read_error(primary_error, error)

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
	var target_asset: DefenseUnit
	var mission := definition.mission_definition()
	if definition.requires_role_knowledge and mission != null:
		target_asset = director.choose_target_for(mission)
	var threat := director._spawn_entry(entry, 0.0, 0.0, null, target_asset)
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
	hud.set_selected_track(null)

func _set_selected_asset(unit: DefenseUnit) -> void:
	if selected_asset != null and is_instance_valid(selected_asset):
		selected_asset.set_selected(false)
	selected_asset = unit
	tactical_range_overlay.select_asset(unit)
	if selected_asset != null and is_instance_valid(selected_asset):
		selected_asset.set_selected(true)

func restore_from_document(document: Dictionary) -> String:
	last_persistence_repairs.clear()
	var current_document := SaveDocument.migrate(document)
	var document_error := SaveDocument.validation_error(current_document)
	if not document_error.is_empty():
		return document_error
	var payload := SessionSnapshot.migrate_content(current_document.payload, int(current_document.version), scenario)
	var prepared := SessionSnapshot.prepare(payload, scenario)
	last_persistence_repairs.assign(prepared.repairs)
	if not prepared.error.is_empty():
		return prepared.error
	_report_persistence_repairs(PersistenceFeedback.Action.LOAD)
	_apply_runtime_snapshot(prepared.payload)
	return ""

func persistence_success_message(action: PersistenceFeedback.Action) -> String:
	return PersistenceFeedback.success_message(action, last_persistence_repairs)

func record_backup_recovery() -> void:
	if last_persistence_repairs.has(PersistenceFeedback.BACKUP_RECOVERY):
		return
	last_persistence_repairs.push_front(PersistenceFeedback.BACKUP_RECOVERY)
	push_warning("불러오기 자동 복구: %s" % PersistenceFeedback.BACKUP_RECOVERY)

func _report_persistence_repairs(action: PersistenceFeedback.Action) -> void:
	for repair: String in last_persistence_repairs:
		push_warning("%s 자동 복구: %s" % [PersistenceFeedback.action_name(action), repair])

func _apply_runtime_snapshot(payload: Dictionary) -> void:
	_clear_runtime_objects()
	var restored_seed := int(payload.scenario.world_seed)
	var restored_layout_id := StringName(String(payload.scenario.get("battlefield_layout_id", "")))
	if scenario.world_seed != restored_seed or scenario.selected_battlefield_layout_id != restored_layout_id:
		scenario.world_seed = restored_seed
		scenario.selected_battlefield_layout_id = restored_layout_id
		requested_seed = restored_seed
		requested_layout_id = restored_layout_id
		battlefield.build(scenario)
	var world_state: Dictionary = payload.world
	var reconstruction := WorldReconstruction.new(battlefield, objective, registry, defense_parent, threat_parent, projectile_parent)
	reconstruction.defense_restored.connect(_on_defense_placed)
	reconstruction.contact_restored.connect(_on_threat_spawned)
	reconstruction.restore_objects(world_state, scenario)
	player_knowledge.restore_state(payload.player_knowledge)
	engagement_coordinator.restore_state(world_state.engagements)
	support_manager.restore_state(world_state.support)
	relocation_manager.restore_state(world_state.relocations)
	enemy_knowledge.restore_state(world_state.enemy_knowledge)
	reconstruction.restore_projectiles(world_state.projectiles, player_knowledge)
	briefing_controller.restore_state(payload.briefings)
	director.restore_state(payload.director)
	session.restore_state(payload.session)
	if game_mode == GameMode.SUSTAINED:
		_create_harbor_port()
		if harbor_port != null and world_state.get("harbor") is Dictionary:
			harbor_port.restore_state(world_state.harbor)
	day_night.apply_time(session.survival_time, true)

func _clear_runtime_objects() -> void:
	combat_audio.stop_all()
	for parent: Node in [defense_parent, threat_parent, projectile_parent, effects_parent]:
		for child: Node in parent.get_children():
			if child == combat_effect_pool:
				continue
			if child is ExplosionEffect and (child as ExplosionEffect).reusable:
				(child as ExplosionEffect).deactivate()
				combat_effect_pool.recycle(child as ExplosionEffect)
			else:
				child.free()
	defenses.clear()
	registry.clear()
	battlefield.clear_occupancy()
	player_knowledge.reset()
	track_display.reset()
	c2_network.reset()
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
	hud.set_selected_track(null)

func _on_target_kind_requested(kind: StringName, enabled: bool) -> void:
	if selected_asset == null or not selected_asset.supports_engagement_controls():
		return
	selected_asset.set_target_kind_allowed(kind, enabled)
	hud.refresh_selected_asset()
