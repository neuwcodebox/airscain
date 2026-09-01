class_name SessionSnapshot
extends RefCounted

static func capture_payload(main: AirscainMain) -> Dictionary:
	var defense_states: Array[Dictionary] = []
	for unit: DefenseUnit in main.defenses:
		if is_instance_valid(unit):
			defense_states.append(unit.capture_state())
	var contact_states: Array[Dictionary] = []
	for contact: ThreatUnit in main.registry.get_active():
		contact_states.append(contact.capture_state())
	var projectile_states: Array[Dictionary] = []
	for child: Node in main.projectile_parent.get_children():
		if child is HomingInterceptor and not child.is_queued_for_deletion():
			projectile_states.append((child as HomingInterceptor).capture_state())
	return {
		"scenario": {
			"world_seed": main.scenario.world_seed,
		},
		"session": main.session.capture_state(),
		"world": {
			"objective_integrity": main.objective.current_integrity,
			"defenses": defense_states,
			"contacts": contact_states,
			"projectiles": projectile_states,
			"engagements": main.engagement_coordinator.capture_state(),
			"support": main.support_manager.capture_state(),
			"relocations": main.relocation_manager.capture_state(),
		},
		"player_knowledge": main.player_knowledge.call("capture_state"),
		"director": main.director.capture_state(),
	}

static func validation_error(payload: Dictionary, scenario: ScenarioDefinition) -> String:
	if int(payload.scenario.get("world_seed", -1)) < 0:
		return "전장 seed가 올바르지 않습니다"
	var session_state: Dictionary = payload.session
	var phase: int = int(session_state.get("phase", -1))
	if phase < GameSession.Phase.PREPARATION or phase > GameSession.Phase.GAME_OVER:
		return "세션 단계가 올바르지 않습니다"
	if int(session_state.get("budget", -1)) < 0 or float(session_state.get("survival_time", -1.0)) < 0.0:
		return "세션 경제 또는 시간이 올바르지 않습니다"
	var world_state: Dictionary = payload.world
	if int(world_state.get("objective_integrity", -1)) < 0:
		return "도시 기능 상태가 올바르지 않습니다"
	if not world_state.get("defenses", null) is Array or not world_state.get("contacts", null) is Array or not world_state.get("projectiles", null) is Array or not world_state.get("engagements", null) is Dictionary or not world_state.get("support", null) is Dictionary or not world_state.get("relocations", null) is Dictionary:
		return "월드 객체 목록이 올바르지 않습니다"
	var defense_definitions := defense_definition_map(scenario)
	var contact_definitions := contact_definition_map(scenario)
	var defense_ids: Dictionary[int, bool] = {}
	var battery_ids: Dictionary[int, bool] = {}
	var sensor_ids: Dictionary[int, bool] = {}
	var armed_ids: Dictionary[int, bool] = {}
	var mobile_ids: Dictionary[int, bool] = {}
	for state: Dictionary in world_state.defenses:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not defense_definitions.has(definition_id):
			return "저장된 방공망 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		var runtime_id := int(state.get("runtime_id", 0))
		if runtime_id <= 0 or defense_ids.has(runtime_id):
			return "방공망 runtime ID가 올바르지 않습니다"
		defense_ids[runtime_id] = true
		if defense_definitions[definition_id].mobile:
			mobile_ids[runtime_id] = true
		if defense_definitions[definition_id] is MissileBatteryDefinition:
			battery_ids[runtime_id] = true
		if defense_definitions[definition_id] is MissileBatteryDefinition or defense_definitions[definition_id] is CloseInGunDefinition:
			armed_ids[runtime_id] = true
		if defense_definitions[definition_id] is SearchRadarDefinition:
			sensor_ids[runtime_id] = true
		if not _valid_vector_data(state.get("position")):
			return "방공망 위치가 올바르지 않습니다"
		var maximum_integrity: float = defense_definitions[definition_id].maximum_integrity
		var integrity := float(state.get("integrity", -1.0))
		if integrity < 0.0 or integrity > maximum_integrity:
			return "방공망 내구도가 올바르지 않습니다"
		if defense_definitions[definition_id] is MissileBatteryDefinition or defense_definitions[definition_id] is CloseInGunDefinition:
			var content_state: Dictionary = state.get("content_state", {})
			var magazine_error := WeaponMagazine.validation_error(content_state.get("magazine"))
			if not magazine_error.is_empty():
				return "%s: %s" % [definition_id, magazine_error]
		if defense_definitions[definition_id] is HighEnergyLaserDefinition:
			var laser_state: Dictionary = state.get("content_state", {})
			var energy_error := EnergyWeaponState.validation_error(laser_state.get("energy"))
			if not energy_error.is_empty():
				return "%s: %s" % [definition_id, energy_error]
	for state: Dictionary in world_state.contacts:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not contact_definitions.has(definition_id):
			return "저장된 접촉 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		if not _valid_vector_data(state.get("position")):
			return "접촉 위치가 올바르지 않습니다"
	var knowledge_state: Dictionary = payload.player_knowledge
	if float(knowledge_state.get("simulation_time", -1.0)) < 0.0 or int(knowledge_state.get("next_track_id", 0)) <= 0 or not knowledge_state.get("tracks", null) is Array:
		return "플레이어 지식 상태가 올바르지 않습니다"
	var track_ids: Dictionary[int, bool] = {}
	var highest_track_id := 0
	for track_state: Dictionary in knowledge_state.tracks:
		var track_id := int(track_state.get("track_id", 0))
		if track_id <= 0 or track_ids.has(track_id):
			return "항적 ID가 올바르지 않습니다"
		track_ids[track_id] = true
		highest_track_id = maxi(highest_track_id, track_id)
		if not _valid_vector_data(track_state.get("estimated_position")) or not _valid_vector_data(track_state.get("estimated_velocity")) or not _valid_vector_data(track_state.get("last_measured_position")):
			return "항적 위치 또는 속도가 올바르지 않습니다"
		var track_lifecycle := int(track_state.get("state", -1))
		if track_lifecycle < PlayerTrack.State.TENTATIVE or track_lifecycle > PlayerTrack.State.LOST:
			return "항적 생명주기 상태가 올바르지 않습니다"
		if not track_state.get("contributing_sensor_ids", null) is Array or not track_state.get("sensor_observed_at", null) is Dictionary:
			return "항적 센서 기여 상태가 올바르지 않습니다"
		for sensor_id: Variant in track_state.contributing_sensor_ids:
			if not sensor_ids.has(int(sensor_id)) or not track_state.sensor_observed_at.has(str(int(sensor_id))):
				return "항적이 존재하지 않는 센서를 참조합니다"
		if float(track_state.get("last_observed_at", -1.0)) < 0.0 or float(track_state.get("track_quality", -1.0)) < 0.0 or float(track_state.get("track_quality", 2.0)) > 1.0 or float(track_state.get("position_uncertainty", -1.0)) < 0.0:
			return "항적 추정 상태가 올바르지 않습니다"
		if not track_state.get("classification_scores", null) is Dictionary or not track_state.get("affiliation_scores", null) is Dictionary:
			return "항적 분류 상태가 올바르지 않습니다"
	if int(knowledge_state.next_track_id) <= highest_track_id:
		return "다음 항적 ID가 올바르지 않습니다"
	var engagement_state: Dictionary = world_state.engagements
	if not engagement_state.get("reservations", null) is Array:
		return "교전 예약 목록이 올바르지 않습니다"
	var reservation_counts: Dictionary[int, int] = {}
	for reservation: Dictionary in engagement_state.reservations:
		var reserved_track_id := int(reservation.get("track_id", 0))
		var owner_defense_id := int(reservation.get("owner_defense_id", 0))
		reservation_counts[reserved_track_id] = reservation_counts.get(reserved_track_id, 0) + 1
		if not track_ids.has(reserved_track_id) or reservation_counts[reserved_track_id] > 2:
			return "교전 예약 항적 참조가 올바르지 않습니다"
		if not defense_ids.has(owner_defense_id) or float(reservation.get("remaining", 0.0)) <= 0.0:
			return "교전 예약 방어체계 또는 시간이 올바르지 않습니다"
	var support_state: Dictionary = world_state.support
	if not support_state.get("tasks", null) is Array:
		return "지원 작업 목록이 올바르지 않습니다"
	var support_targets: Dictionary[int, bool] = {}
	for task: Dictionary in support_state.tasks:
		var kind := String(task.get("kind", ""))
		var target_defense_id := int(task.get("target_defense_id", 0))
		if kind != SupportManager.RESUPPLY and kind != SupportManager.REPAIR:
			return "지원 작업 종류가 올바르지 않습니다"
		if not defense_ids.has(target_defense_id) or (kind == SupportManager.RESUPPLY and not armed_ids.has(target_defense_id)) or support_targets.has(target_defense_id) or float(task.get("remaining_work", 0.0)) <= 0.0:
			return "재보급 작업 대상 또는 작업량이 올바르지 않습니다"
		support_targets[target_defense_id] = true
	var relocation_state: Dictionary = world_state.relocations
	if not relocation_state.get("tasks", null) is Array:
		return "재배치 작업 목록이 올바르지 않습니다"
	var relocation_targets: Dictionary[int, bool] = {}
	for task: Dictionary in relocation_state.tasks:
		var target_defense_id := int(task.get("target_defense_id", 0))
		if not mobile_ids.has(target_defense_id) or support_targets.has(target_defense_id) or relocation_targets.has(target_defense_id) or float(task.get("remaining", 0.0)) <= 0.0 or not _valid_vector_data(task.get("origin")) or not _valid_vector_data(task.get("destination")):
			return "재배치 작업 대상 또는 상태가 올바르지 않습니다"
		relocation_targets[target_defense_id] = true
	for projectile_state: Dictionary in world_state.projectiles:
		if String(projectile_state.get("type", "")) != "homing_interceptor":
			return "지원하지 않는 발사체 형식입니다"
		if not battery_ids.has(int(projectile_state.get("owner_defense_id", 0))):
			return "요격체가 존재하지 않는 포대를 참조합니다"
		if not track_ids.has(int(projectile_state.get("target_track_id", 0))):
			return "요격체가 존재하지 않는 항적을 참조합니다"
		if not _valid_vector_data(projectile_state.get("position")) or not _valid_vector_data(projectile_state.get("velocity")):
			return "요격체 위치 또는 속도가 올바르지 않습니다"
		var maximum_lifetime := float(projectile_state.get("maximum_lifetime", 0.0))
		var age := float(projectile_state.get("age", -1.0))
		if float(projectile_state.get("speed", 0.0)) <= 0.0 or float(projectile_state.get("turn_rate", 0.0)) <= 0.0 or maximum_lifetime <= 0.0 or float(projectile_state.get("damage", 0.0)) <= 0.0 or float(projectile_state.get("proximity_radius", 0.0)) <= 0.0 or age < 0.0 or age >= maximum_lifetime:
			return "요격체 비행 상태가 올바르지 않습니다"
	return ""

static func defense_definition_map(scenario: ScenarioDefinition) -> Dictionary[StringName, DefenseDefinition]:
	var result: Dictionary[StringName, DefenseDefinition] = {}
	for definition: DefenseDefinition in scenario.available_defenses:
		result[definition.id] = definition
	return result

static func contact_definition_map(scenario: ScenarioDefinition) -> Dictionary[StringName, ThreatDefinition]:
	var result: Dictionary[StringName, ThreatDefinition] = {}
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		result[entry.threat_definition.id] = entry.threat_definition
	for definition: ThreatDefinition in scenario.ambient_contacts:
		result[definition.id] = definition
	return result

static func _valid_vector_data(value: Variant) -> bool:
	return value is Array and value.size() == 3
