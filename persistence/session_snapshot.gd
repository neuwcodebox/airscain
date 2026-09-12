class_name SessionSnapshot
extends RefCounted

const AIR_STRIKE_MUNITION_SCRIPT := preload("res://effects/air_strike_munition/air_strike_munition.gd")

static func migrate_content(payload: Dictionary, version: int, scenario: ScenarioDefinition) -> Dictionary:
	if version >= SaveDocument.CURRENT_VERSION:
		return payload
	var defense_definitions: Dictionary[StringName, DefenseDefinition] = {}
	var contact_definitions: Dictionary[StringName, ThreatDefinition] = {}
	if scenario != null:
		defense_definitions = defense_definition_map(scenario)
		contact_definitions = contact_definition_map(scenario)
	return SessionSnapshotMigration.migrate_content(payload, version, scenario, defense_definitions, contact_definitions)

static func capture_payload(main: AirscainMain) -> Dictionary:
	return SessionSnapshotCapture.capture_payload(main)

static func validation_error(payload: Dictionary, scenario: ScenarioDefinition) -> String:
	if int(payload.scenario.get("world_seed", -1)) < 0:
		return "전장 seed가 올바르지 않습니다"
	var session_state: Dictionary = payload.session
	var phase: int = int(session_state.get("phase", -1))
	if phase < GameSession.Phase.PREPARATION or phase > GameSession.Phase.GAME_OVER:
		return "세션 단계가 올바르지 않습니다"
	if int(session_state.get("budget", -1)) < 0 or float(session_state.get("survival_time", -1.0)) < 0.0:
		return "세션 경제 또는 시간이 올바르지 않습니다"
	if int(session_state.get("current_pressure", 0)) < 1 or float(session_state.get("support_interval", 0.0)) <= 0.0 or int(session_state.get("support_amount", -1)) < 0 or float(session_state.get("next_support_at", -1.0)) < 0.0 or int(session_state.get("support_payment_count", -1)) < 0 or int(session_state.get("completed_attack_windows", -1)) < 0 or int(session_state.get("total_support_received", -1)) < 0:
		return "세션 성장 또는 작전 지원 상태가 올바르지 않습니다"
	if int(session_state.get("starting_budget", -1)) < 0 or int(session_state.get("defense_spending", -1)) < 0 or int(session_state.get("support_spending", -1)) < 0 or int(session_state.get("weapon_fire_count", -1)) < 0 or int(session_state.get("neutralized_reward_total", -1)) < 0 or not session_state.get("neutralized_by_type", null) is Dictionary:
		return "세션 결과 통계가 올바르지 않습니다"
	for definition_id: String in session_state.neutralized_by_type:
		if not contact_definition_map(scenario).has(StringName(definition_id)) or int(session_state.neutralized_by_type[definition_id]) < 0:
			return "위협 유형별 결과 통계가 올바르지 않습니다"
	var world_state: Dictionary = payload.world
	if int(world_state.get("objective_integrity", -1)) < 0:
		return "도시 기능 상태가 올바르지 않습니다"
	var damage_smoke_states: Variant = world_state.get("objective_damage_smoke", [])
	if not damage_smoke_states is Array or damage_smoke_states.size() > ProtectedObjective.MAX_DAMAGE_SMOKE_SITES:
		return "도시 손상 연기 상태가 올바르지 않습니다"
	for smoke_state: Variant in damage_smoke_states:
		if not smoke_state is Dictionary or not SaveDocument.is_valid_vector3_data(smoke_state.get("offset")) or float(smoke_state.get("building_height", 0.0)) <= 0.0:
			return "도시 손상 연기 위치가 올바르지 않습니다"
		var repair_at: Variant = smoke_state.get("repair_at")
		if not (repair_at is int or repair_at is float) or not is_finite(float(repair_at)) or float(repair_at) != floorf(float(repair_at)) or float(repair_at) <= float(world_state.objective_integrity) or float(repair_at) > scenario.objective_definition.maximum_integrity:
			return "도시 연기 수리 단계가 올바르지 않습니다"
	if not damage_smoke_states.is_empty() and int(damage_smoke_states.back().repair_at) != scenario.objective_definition.maximum_integrity:
		return "완전 복구까지 남을 도시 연기가 없습니다"
	if not world_state.get("defenses", null) is Array or not world_state.get("contacts", null) is Array or not world_state.get("projectiles", null) is Array or not world_state.get("engagements", null) is Dictionary or not world_state.get("support", null) is Dictionary or not world_state.get("relocations", null) is Dictionary or not world_state.get("enemy_knowledge", null) is Dictionary:
		return "월드 객체 목록이 올바르지 않습니다"
	var defense_definitions := defense_definition_map(scenario)
	var contact_definitions := contact_definition_map(scenario)
	var defense_ids: Dictionary[int, bool] = {}
	var repair_definitions_by_id: Dictionary[int, DefenseDefinition] = {}
	var sensor_ids: Dictionary[int, bool] = {}
	var armed_ids: Dictionary[int, bool] = {}
	var mobile_ids: Dictionary[int, bool] = {}
	var projectile_owner_definitions: Dictionary[int, DefenseDefinition] = {}
	var reservation_kinds: Dictionary[int, StringName] = {}
	for state: Dictionary in world_state.defenses:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not defense_definitions.has(definition_id):
			return "저장된 방공망 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		var runtime_id := int(state.get("runtime_id", 0))
		if runtime_id <= 0 or defense_ids.has(runtime_id):
			return "방공망 runtime ID가 올바르지 않습니다"
		defense_ids[runtime_id] = true
		var definition: DefenseDefinition = defense_definitions[definition_id]
		repair_definitions_by_id[runtime_id] = definition
		reservation_kinds[runtime_id] = definition.engagement_reservation_kind()
		if definition.mobile:
			mobile_ids[runtime_id] = true
		if definition.has_ammunition_state():
			armed_ids[runtime_id] = true
		if (definition.placement_c2_roles() & DefenseUnit.C2Role.SENSOR) != 0:
			sensor_ids[runtime_id] = true
		if not definition.persistent_projectile_types().is_empty():
			projectile_owner_definitions[runtime_id] = definition
		if not SaveDocument.is_valid_vector3_data(state.get("position")):
			return "방공망 위치가 올바르지 않습니다"
		var maximum_integrity: float = definition.maximum_integrity
		var integrity := float(state.get("integrity", -1.0))
		if integrity < 0.0 or integrity > maximum_integrity:
			return "방공망 내구도가 올바르지 않습니다"
		var neutralized_count: Variant = state.get("neutralized_count", 0)
		if not (neutralized_count is int or neutralized_count is float) or not is_finite(float(neutralized_count)) or float(neutralized_count) != floorf(float(neutralized_count)) or int(neutralized_count) < 0:
			return "방공망 무력화 실적이 올바르지 않습니다"
		var content_error := definition.runtime_state_validation_error(state.get("content_state", {}))
		if not content_error.is_empty():
			return "%s: %s" % [definition_id, content_error]
	var contact_ids: Dictionary[int, bool] = {}
	for state: Dictionary in world_state.contacts:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not contact_definitions.has(definition_id):
			return "저장된 접촉 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		if not SaveDocument.is_valid_vector3_data(state.get("position")):
			return "접촉 위치가 올바르지 않습니다"
		var countermeasure_charges := int(state.get("countermeasure_charges", -1))
		if countermeasure_charges < 0 or countermeasure_charges > contact_definitions[definition_id].countermeasure_charges:
			return "위협 대응책 상태가 올바르지 않습니다"
		var contact_definition: ThreatDefinition = contact_definitions[definition_id]
		if not state.get("countermeasure", {}) is Dictionary:
			return "대응탄 문서가 올바르지 않습니다"
		var countermeasure_error := contact_definition.countermeasure_state_validation_error(state.get("countermeasure", {}))
		if not countermeasure_error.is_empty():
			return countermeasure_error
		if contact_definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
			contact_ids[int(state.get("runtime_id", 0))] = true
		var content_error := contact_definition.runtime_state_validation_error(state.get("content_state", {}), defense_ids)
		if not content_error.is_empty():
			return "%s: %s" % [definition_id, content_error]
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
		if not SaveDocument.is_valid_vector3_data(track_state.get("estimated_position")) or not SaveDocument.is_valid_vector3_data(track_state.get("estimated_velocity")) or not SaveDocument.is_valid_vector3_data(track_state.get("last_measured_position")):
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
	var fire_support_owners: Dictionary[int, bool] = {}
	for reservation: Variant in engagement_state.reservations:
		if not reservation is Dictionary:
			return "교전 예약 상태가 올바르지 않습니다"
		var reserved_track_id := int(reservation.get("track_id", 0))
		var owner_defense_id := int(reservation.get("owner_defense_id", 0))
		var kind := StringName(String(reservation.get("kind", "")))
		if not reservation_kinds.has(owner_defense_id) or kind != reservation_kinds[owner_defense_id]:
			return "교전 예약 정책이 올바르지 않습니다"
		if kind == EngagementCoordinator.INTERCEPTOR:
			reservation_counts[reserved_track_id] = reservation_counts.get(reserved_track_id, 0) + 1
			if reservation_counts[reserved_track_id] > 2:
				return "요격탄 예약 상한을 초과했습니다"
		elif kind == EngagementCoordinator.FIRE_SUPPORT:
			if fire_support_owners.has(owner_defense_id):
				return "근접방어 할당이 중복되었습니다"
			fire_support_owners[owner_defense_id] = true
		else:
			return "지원하지 않는 교전 예약 정책입니다"
		if not track_ids.has(reserved_track_id):
			return "교전 예약 항적 참조가 올바르지 않습니다"
		if not defense_ids.has(owner_defense_id) or float(reservation.get("remaining", 0.0)) <= 0.0:
			return "교전 예약 방어체계 또는 시간이 올바르지 않습니다"
	var support_state: Dictionary = world_state.support
	if not support_state.get("tasks", null) is Array:
		return "지원 작업 목록이 올바르지 않습니다"
	if not support_state.get("automatic_resupply_ids") is Array:
		return "자동 재보급 목록이 올바르지 않습니다"
	var automatic_targets: Dictionary[int, bool] = {}
	for value: Variant in support_state.automatic_resupply_ids:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)):
			return "자동 재보급 대상 ID가 올바르지 않습니다"
		var target_id := int(value)
		if not armed_ids.has(target_id) or automatic_targets.has(target_id):
			return "자동 재보급 대상이 올바르지 않습니다"
		automatic_targets[target_id] = true
	var support_targets: Dictionary[int, bool] = {}
	for task: Dictionary in support_state.tasks:
		if not task.get("user_requested") is bool:
			return "지원 작업 요청 출처가 올바르지 않습니다"
		var kind := String(task.get("kind", ""))
		var target_defense_id := int(task.get("target_defense_id", 0))
		if kind != SupportManager.RESUPPLY and kind != SupportManager.REPAIR:
			return "지원 작업 종류가 올바르지 않습니다"
		if not defense_ids.has(target_defense_id) or (kind == SupportManager.RESUPPLY and not armed_ids.has(target_defense_id)) or support_targets.has(target_defense_id) or float(task.get("remaining_work", 0.0)) <= 0.0:
			return "재보급 작업 대상 또는 작업량이 올바르지 않습니다"
		if kind == SupportManager.REPAIR:
			var repair_error := repair_definitions_by_id[target_defense_id].repair_amount_validation_error(task.get("repair_amount"))
			if not repair_error.is_empty():
				return repair_error
		support_targets[target_defense_id] = true
	var relocation_state: Dictionary = world_state.relocations
	if not relocation_state.get("tasks", null) is Array:
		return "재배치 작업 목록이 올바르지 않습니다"
	var relocation_targets: Dictionary[int, bool] = {}
	for task: Dictionary in relocation_state.tasks:
		var target_defense_id := int(task.get("target_defense_id", 0))
		if not mobile_ids.has(target_defense_id) or support_targets.has(target_defense_id) or relocation_targets.has(target_defense_id) or float(task.get("remaining", 0.0)) <= 0.0 or not SaveDocument.is_valid_vector3_data(task.get("origin")) or not SaveDocument.is_valid_vector3_data(task.get("destination")):
			return "재배치 작업 대상 또는 상태가 올바르지 않습니다"
		relocation_targets[target_defense_id] = true
	for projectile_state: Dictionary in world_state.projectiles:
		var projectile_type := StringName(String(projectile_state.get("type", "")))
		if projectile_type == &"air_strike_munition":
			var strike_target_id := int(projectile_state.get("target_defense_id", 0))
			if strike_target_id != 0 and not defense_ids.has(strike_target_id):
				return "공대지 탄의 타격 대상이 올바르지 않습니다"
			var strike_error: String = AirStrikeMunition.state_validation_error(projectile_state)
			if not strike_error.is_empty():
				return strike_error
			continue
		var owner_id := int(projectile_state.get("owner_defense_id", 0))
		if not projectile_owner_definitions.has(owner_id):
			return "요격체가 존재하지 않는 포대를 참조합니다"
		var owner_definition: DefenseDefinition = projectile_owner_definitions[owner_id]
		if not owner_definition.persistent_projectile_types().has(projectile_type):
			return "요격체 형식과 포대가 일치하지 않습니다"
		if not track_ids.has(int(projectile_state.get("target_track_id", 0))):
			return "요격체가 존재하지 않는 항적을 참조합니다"
		if not SaveDocument.is_valid_vector3_data(projectile_state.get("position")) or not SaveDocument.is_valid_vector3_data(projectile_state.get("velocity")):
			return "요격체 위치 또는 속도가 올바르지 않습니다"
		var projectile_error := owner_definition.persistent_projectile_state_validation_error(projectile_type, projectile_state)
		if not projectile_error.is_empty():
			return projectile_error
	var director_state: Dictionary = payload.director
	var last_pattern: Variant = director_state.get("last_raid_pattern")
	if not last_pattern is String or not (String(last_pattern).is_empty() or StringName(last_pattern) in RaidPlanner.PATTERNS):
		return "공습 생성 이력이 올바르지 않습니다"
	if float(director_state.get("elapsed", -1.0)) < 0.0 or float(director_state.get("until_spawn", -1.0)) < 0.0 or int(director_state.get("pressure_level", 0)) < 1 or int(director_state.get("next_runtime_id", 0)) < 1 or int(director_state.get("completed_attack_windows", -1)) < 0 or not director_state.get("in_recovery", null) is bool or not director_state.get("pending_waves", null) is Array:
		return "공격 Director 상태가 올바르지 않습니다"
	var opening_error := ThreatDirector.opening_state_validation_error(director_state)
	if not opening_error.is_empty():
		return opening_error
	for id: Variant in director_state.opening_threat_ids:
		if not contact_ids.has(int(id)):
			return "첫 공습이 존재하지 않는 위협을 참조합니다"
	for wave: Dictionary in director_state.pending_waves:
		var definition_id := StringName(String(wave.get("definition_id", "")))
		if not contact_definitions.has(definition_id) or float(wave.get("remaining", -1.0)) < 0.0 or not is_finite(float(wave.get("angle", NAN))):
			return "예약 공격 파동 상태가 올바르지 않습니다"
	var enemy_state: Dictionary = world_state.enemy_knowledge
	if float(enemy_state.get("simulation_time", -1.0)) < 0.0 or not enemy_state.get("estimates", null) is Array or not enemy_state.get("reports", null) is Array or not enemy_state.get("recent_outcomes", null) is Array:
		return "적 지식 상태가 올바르지 않습니다"
	var recon_error := EnemyKnowledge.recon_validation_error(enemy_state, scenario.battlefield_size, defense_ids)
	if not recon_error.is_empty():
		return recon_error
	var recon_owners: Dictionary[int, bool] = {}
	for contact: Dictionary in world_state.contacts:
		var definition: ThreatDefinition = contact_definitions[StringName(contact.definition_id)]
		var mission := definition.mission_definition()
		if mission != null and mission.area_recon and bool(contact.get("active", false)):
			recon_owners[int(contact.runtime_id)] = true
	for reservation: Dictionary in enemy_state.get("recon_search", {}).get("assignments", []):
		if not recon_owners.has(int(reservation.owner)):
			return "정찰 구역을 소유한 기체가 없습니다"
	var estimate_ids: Dictionary[int, bool] = {}
	for estimate: Dictionary in enemy_state.estimates:
		var asset_id := int(estimate.get("asset_id", 0))
		var observed_at := float(estimate.get("observed_at", -1.0))
		if not defense_ids.has(asset_id) or estimate_ids.has(asset_id) or not SaveDocument.is_valid_vector3_data(estimate.get("estimated_position")) or float(estimate.get("confidence", -1.0)) < 0.0 or float(estimate.get("confidence", 2.0)) > 1.0 or float(estimate.get("uncertainty", -1.0)) < 0.0 or observed_at < 0.0 or observed_at > float(enemy_state.simulation_time):
			return "적 자산 추정 상태가 올바르지 않습니다"
		estimate_ids[asset_id] = true
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
	var pending: Array = result.values()
	while not pending.is_empty():
		var definition := pending.pop_back() as ThreatDefinition
		for released: ThreatDefinition in definition.released_threat_definitions():
			if not result.has(released.id):
				result[released.id] = released
				pending.append(released)
	return result
