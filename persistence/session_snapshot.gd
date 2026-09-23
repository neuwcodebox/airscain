class_name SessionSnapshot
extends RefCounted

const AIR_STRIKE_MUNITION_SCRIPT := preload("res://effects/air_strike_munition/air_strike_munition.gd")

class PreparationResult:
	extends RefCounted

	var payload: Dictionary = {}
	var repairs: Array[String] = []
	var error: String = ""

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

static func prepare(payload: Dictionary, scenario: ScenarioDefinition) -> PreparationResult:
	var result := PreparationResult.new()
	result.payload = payload.duplicate(true)
	var structure_error := _repairable_structure_error(result.payload)
	if not structure_error.is_empty():
		result.error = structure_error
		return result
	_repair_cross_references(result.payload, scenario, result.repairs)
	result.error = validation_error(result.payload, scenario)
	return result

static func _repairable_structure_error(payload: Dictionary) -> String:
	for section: String in SaveDocument.REQUIRED_SECTIONS:
		if not payload.get(section) is Dictionary:
			return "저장 섹션이 없거나 올바르지 않습니다: %s" % section
	var world: Dictionary = payload.world
	for key: String in ["defenses", "contacts", "projectiles"]:
		if not world.get(key) is Array:
			return "월드 객체 목록이 올바르지 않습니다"
	for key: String in ["engagements", "support", "relocations", "enemy_knowledge"]:
		if not world.get(key) is Dictionary:
			return "월드 객체 목록이 올바르지 않습니다"
	if not payload.player_knowledge.get("tracks") is Array:
		return "플레이어 지식 상태가 올바르지 않습니다"
	return ""

static func _repair_cross_references(payload: Dictionary, scenario: ScenarioDefinition, repairs: Array[String]) -> void:
	var world: Dictionary = payload.world
	var defense_definitions := defense_definition_map(scenario)
	var contact_definitions := contact_definition_map(scenario)
	var raid_definition_ids: Dictionary[StringName, bool] = {}
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		raid_definition_ids[entry.threat_definition.id] = true
	var district_ids := city_district_definition_ids(scenario)
	var defense_ids: Dictionary[int, bool] = {}
	var sensor_ids: Dictionary[int, bool] = {}
	var armed_ids: Dictionary[int, bool] = {}
	var mobile_ids: Dictionary[int, bool] = {}
	var projectile_owner_definitions: Dictionary[int, DefenseDefinition] = {}
	var defense_definitions_by_runtime_id: Dictionary[int, DefenseDefinition] = {}
	var reservation_kinds: Dictionary[int, StringName] = {}
	var valid_defenses: Array = []
	for value: Variant in world.defenses:
		if not value is Dictionary:
			repairs.append("형식이 손상된 방공 자산을 제거했습니다")
			continue
		var state := value as Dictionary
		var definition_id := StringName(String(state.get("definition_id", "")))
		var definition: DefenseDefinition = defense_definitions.get(definition_id)
		var runtime_id := int(state.get("runtime_id", 0))
		var rotation_y: Variant = state.get("rotation_y", 0.0)
		if definition == null or runtime_id <= 0 or defense_ids.has(runtime_id) or not SaveDocument.is_valid_vector3_data(state.get("position")) or not (rotation_y is int or rotation_y is float) or not is_finite(float(rotation_y)) or not state.get("content_state", {}) is Dictionary:
			repairs.append("복원할 수 없는 방공 자산 %d을 제거했습니다" % runtime_id)
			continue
		var integrity := float(state.get("integrity", -1.0))
		var neutralized_count: Variant = state.get("neutralized_count", 0)
		var original_content: Dictionary = state.get("content_state", {})
		var repaired_content := definition.repair_runtime_state(original_content)
		if repaired_content != original_content:
			state.content_state = repaired_content
			repairs.append("방공 자산 %d의 콘텐츠 상태를 정리했습니다" % runtime_id)
		var content_error := definition.runtime_state_validation_error(repaired_content)
		if not is_finite(integrity) or integrity < 0.0 or integrity > definition.maximum_integrity or not (neutralized_count is int or neutralized_count is float) or not is_finite(float(neutralized_count)) or float(neutralized_count) != floorf(float(neutralized_count)) or int(neutralized_count) < 0 or not content_error.is_empty():
			repairs.append("상태가 손상된 방공 자산 %d을 제거했습니다" % runtime_id)
			continue
		valid_defenses.append(state)
		defense_ids[runtime_id] = true
		defense_definitions_by_runtime_id[runtime_id] = definition
		reservation_kinds[runtime_id] = definition.engagement_reservation_kind()
		if definition.mobile:
			mobile_ids[runtime_id] = true
		if definition.has_ammunition_state():
			armed_ids[runtime_id] = true
		if (definition.placement_c2_roles() & DefenseUnit.C2Role.SENSOR) != 0:
			sensor_ids[runtime_id] = true
		if not definition.persistent_projectile_types().is_empty():
			projectile_owner_definitions[runtime_id] = definition
	world.defenses = valid_defenses

	var hostile_contact_ids: Dictionary[int, bool] = {}
	var all_contact_ids: Dictionary[int, bool] = {}
	var valid_contacts: Array = []
	for value: Variant in world.contacts:
		if not value is Dictionary:
			repairs.append("형식이 손상된 접촉을 제거했습니다")
			continue
		var state := value as Dictionary
		var definition_id := StringName(String(state.get("definition_id", "")))
		var definition: ThreatDefinition = contact_definitions.get(definition_id)
		var runtime_id := int(state.get("runtime_id", 0))
		if definition == null or runtime_id == 0 or all_contact_ids.has(runtime_id) or not SaveDocument.is_valid_vector3_data(state.get("position")) or not state.get("content_state", {}) is Dictionary or not state.get("countermeasure", {}) is Dictionary:
			repairs.append("복원할 수 없는 접촉 %d을 제거했습니다" % runtime_id)
			continue
		var charge_count := int(state.get("countermeasure_charges", -1))
		var original_content: Dictionary = state.get("content_state", {})
		var repaired_content := definition.repair_runtime_state(original_content, defense_ids)
		if repaired_content != original_content:
			state.content_state = repaired_content
			repairs.append("접촉 %d의 콘텐츠 상태를 정리했습니다" % runtime_id)
		var original_countermeasure: Dictionary = state.get("countermeasure", {})
		var repaired_countermeasure := definition.repair_countermeasure_state(original_countermeasure, state.get("position"))
		if repaired_countermeasure != original_countermeasure:
			state.countermeasure = repaired_countermeasure
			repairs.append("접촉 %d의 대응책 상태를 초기화했습니다" % runtime_id)
		var content_error := definition.runtime_state_validation_error(repaired_content, defense_ids)
		var countermeasure_error := definition.countermeasure_state_validation_error(repaired_countermeasure)
		if charge_count < 0 or charge_count > definition.countermeasure_charges or not content_error.is_empty() or not countermeasure_error.is_empty():
			repairs.append("상태가 손상된 접촉 %d을 제거했습니다" % runtime_id)
			continue
		valid_contacts.append(state)
		all_contact_ids[runtime_id] = true
		if definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
			hostile_contact_ids[runtime_id] = true
	world.contacts = valid_contacts

	var knowledge: Dictionary = payload.player_knowledge
	var track_ids: Dictionary[int, bool] = {}
	var valid_tracks: Array = []
	var highest_track_id := 0
	for value: Variant in knowledge.tracks:
		if not value is Dictionary:
			repairs.append("형식이 손상된 항적을 제거했습니다")
			continue
		var track := value as Dictionary
		var track_id := int(track.get("track_id", 0))
		var contributions: Variant = track.get("contributing_sensor_ids")
		var observed_at: Variant = track.get("sensor_observed_at")
		if contributions is Array and observed_at is Dictionary:
			var valid_contributions: Array = []
			var valid_times: Dictionary = {}
			for sensor_value: Variant in contributions:
				var sensor_id := int(sensor_value)
				var key := str(sensor_id)
				if sensor_ids.has(sensor_id) and observed_at.has(key) and not valid_contributions.has(sensor_id):
					valid_contributions.append(sensor_id)
					valid_times[key] = observed_at[key]
			if valid_contributions.size() != contributions.size() or valid_times.size() != observed_at.size():
				track.contributing_sensor_ids = valid_contributions
				track.sensor_observed_at = valid_times
				repairs.append("항적 %d의 없는 센서 기여를 정리했습니다" % track_id)
		if track_ids.has(track_id) or not _track_validation_error(track, sensor_ids).is_empty():
			repairs.append("상태가 손상된 항적 %d을 제거했습니다" % track_id)
			continue
		track_ids[track_id] = true
		highest_track_id = maxi(highest_track_id, track_id)
		valid_tracks.append(track)
	knowledge.tracks = valid_tracks
	if int(knowledge.get("next_track_id", 0)) <= highest_track_id:
		knowledge.next_track_id = highest_track_id + 1
		repairs.append("다음 항적 ID를 복구했습니다")

	_repair_engagements(world.engagements, track_ids, defense_ids, reservation_kinds, repairs)
	_repair_support(world.support, defense_ids, armed_ids, defense_definitions_by_runtime_id, repairs)
	_repair_relocations(world.relocations, defense_ids, mobile_ids, world.support, repairs)
	_repair_projectiles(world, track_ids, defense_ids, projectile_owner_definitions, repairs)
	_repair_director(payload.director, hostile_contact_ids, contact_definitions, raid_definition_ids, defense_ids, district_ids, repairs)
	_repair_enemy_knowledge(world.enemy_knowledge, defense_ids, world.contacts, contact_definitions, repairs)

static func _repair_engagements(state: Dictionary, track_ids: Dictionary[int, bool], defense_ids: Dictionary[int, bool], reservation_kinds: Dictionary[int, StringName], repairs: Array[String]) -> void:
	if not state.get("reservations") is Array:
		return
	var valid: Array = []
	var interceptor_counts: Dictionary[int, int] = {}
	var support_owners: Dictionary[int, bool] = {}
	for value: Variant in state.reservations:
		if not value is Dictionary:
			repairs.append("형식이 손상된 교전 예약을 제거했습니다")
			continue
		var reservation := value as Dictionary
		var track_id := int(reservation.get("track_id", 0))
		var owner_id := int(reservation.get("owner_defense_id", 0))
		var kind := StringName(String(reservation.get("kind", "")))
		var keep: bool = track_ids.has(track_id) and defense_ids.has(owner_id) and reservation_kinds.get(owner_id, &"") == kind and float(reservation.get("remaining", 0.0)) > 0.0
		if keep and kind == EngagementCoordinator.INTERCEPTOR:
			interceptor_counts[track_id] = interceptor_counts.get(track_id, 0) + 1
			keep = interceptor_counts[track_id] <= 2
		elif keep and kind == EngagementCoordinator.FIRE_SUPPORT:
			keep = not support_owners.has(owner_id)
			if keep:
				support_owners[owner_id] = true
		else:
			keep = false
		if keep:
			valid.append(reservation)
		else:
			repairs.append("유효하지 않은 교전 예약을 제거했습니다")
	state.reservations = valid

static func _track_validation_error(track: Dictionary, sensor_ids: Dictionary[int, bool]) -> String:
	var track_id := int(track.get("track_id", 0))
	if track_id <= 0:
		return "항적 ID가 올바르지 않습니다"
	if not SaveDocument.is_valid_vector3_data(track.get("estimated_position")) or not SaveDocument.is_valid_vector3_data(track.get("estimated_velocity")) or not SaveDocument.is_valid_vector3_data(track.get("last_measured_position")):
		return "항적 위치 또는 속도가 올바르지 않습니다"
	var lifecycle := int(track.get("state", -1))
	if lifecycle < PlayerTrack.State.TENTATIVE or lifecycle > PlayerTrack.State.LOST:
		return "항적 생명주기 상태가 올바르지 않습니다"
	if not track.get("contributing_sensor_ids") is Array or not track.get("sensor_observed_at") is Dictionary:
		return "항적 센서 기여 상태가 올바르지 않습니다"
	for sensor_id: Variant in track.contributing_sensor_ids:
		if not sensor_ids.has(int(sensor_id)) or not track.sensor_observed_at.has(str(int(sensor_id))):
			return "항적이 존재하지 않는 센서를 참조합니다"
	for key: String in ["last_observed_at", "track_quality", "position_uncertainty"]:
		var value := float(track.get(key, -1.0))
		if not is_finite(value) or value < 0.0:
			return "항적 추정 상태가 올바르지 않습니다"
	if float(track.get("track_quality", 2.0)) > 1.0:
		return "항적 추정 상태가 올바르지 않습니다"
	if track.has("capacity_limited") and not track.capacity_limited is bool:
		return "항적 추적 용량 상태가 올바르지 않습니다"
	if not track.get("classification_scores") is Dictionary or not track.get("affiliation_scores") is Dictionary:
		return "항적 분류 상태가 올바르지 않습니다"
	return ""

static func _repair_support(state: Dictionary, defense_ids: Dictionary[int, bool], armed_ids: Dictionary[int, bool], definitions: Dictionary[int, DefenseDefinition], repairs: Array[String]) -> void:
	if state.get("automatic_resupply_ids") is Array:
		var automatic: Array = []
		for value: Variant in state.automatic_resupply_ids:
			var id := int(value)
			if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and armed_ids.has(id) and not automatic.has(id):
				automatic.append(id)
			else:
				repairs.append("유효하지 않은 자동 재보급 대상을 제거했습니다")
		state.automatic_resupply_ids = automatic
	if not state.get("tasks") is Array:
		return
	var tasks: Array = []
	var targets: Dictionary[int, bool] = {}
	for value: Variant in state.tasks:
		if not value is Dictionary:
			repairs.append("형식이 손상된 지원 작업을 제거했습니다")
			continue
		var task := value as Dictionary
		var kind := String(task.get("kind", ""))
		var id := int(task.get("target_defense_id", 0))
		var keep: bool = (kind == SupportManager.RESUPPLY or kind == SupportManager.REPAIR) and defense_ids.has(id) and not targets.has(id) and float(task.get("remaining_work", 0.0)) > 0.0 and task.get("user_requested") is bool
		if keep and kind == SupportManager.RESUPPLY:
			keep = armed_ids.has(id)
		elif keep and kind == SupportManager.REPAIR:
			keep = definitions[id].repair_amount_validation_error(task.get("repair_amount")).is_empty()
		if keep:
			targets[id] = true
			tasks.append(task)
		else:
			repairs.append("유효하지 않은 지원 작업을 제거했습니다")
	state.tasks = tasks

static func _repair_relocations(state: Dictionary, defense_ids: Dictionary[int, bool], mobile_ids: Dictionary[int, bool], support: Dictionary, repairs: Array[String]) -> void:
	if not state.get("tasks") is Array:
		return
	var support_targets: Dictionary[int, bool] = {}
	for value: Variant in support.get("tasks", []):
		if value is Dictionary:
			support_targets[int(value.get("target_defense_id", 0))] = true
	var targets: Dictionary[int, bool] = {}
	var tasks: Array = []
	for value: Variant in state.tasks:
		if not value is Dictionary:
			repairs.append("형식이 손상된 재배치 작업을 제거했습니다")
			continue
		var task := value as Dictionary
		var id := int(task.get("target_defense_id", 0))
		var keep: bool = defense_ids.has(id) and mobile_ids.has(id) and not support_targets.has(id) and not targets.has(id) and float(task.get("remaining", 0.0)) > 0.0 and SaveDocument.is_valid_vector3_data(task.get("origin")) and SaveDocument.is_valid_vector3_data(task.get("destination"))
		if keep:
			targets[id] = true
			tasks.append(task)
		else:
			repairs.append("유효하지 않은 재배치 작업을 제거했습니다")
	state.tasks = tasks

static func _repair_projectiles(world: Dictionary, track_ids: Dictionary[int, bool], defense_ids: Dictionary[int, bool], owner_definitions: Dictionary[int, DefenseDefinition], repairs: Array[String]) -> void:
	var projectiles: Array = []
	for value: Variant in world.projectiles:
		if not value is Dictionary:
			repairs.append("형식이 손상된 발사체를 제거했습니다")
			continue
		var state := value as Dictionary
		var projectile_type := StringName(String(state.get("type", "")))
		var keep: bool = true
		if projectile_type == &"air_strike_munition":
			var target_id := int(state.get("target_defense_id", 0))
			keep = (target_id == 0 or defense_ids.has(target_id)) and AIR_STRIKE_MUNITION_SCRIPT.state_validation_error(state).is_empty()
		else:
			var owner_id := int(state.get("owner_defense_id", 0))
			var definition: DefenseDefinition = owner_definitions.get(owner_id)
			if definition != null:
				var repaired_state := definition.repair_persistent_projectile_state(projectile_type, state)
				if repaired_state != state:
					state = repaired_state
					repairs.append("발사체의 콘텐츠 상태를 정리했습니다")
			keep = definition != null and definition.persistent_projectile_types().has(projectile_type) and track_ids.has(int(state.get("target_track_id", 0))) and SaveDocument.is_valid_vector3_data(state.get("position")) and SaveDocument.is_valid_vector3_data(state.get("velocity")) and definition.persistent_projectile_state_validation_error(projectile_type, state).is_empty()
		if keep:
			projectiles.append(state)
		else:
			repairs.append("참조나 상태가 유효하지 않은 발사체를 제거했습니다")
	world.projectiles = projectiles

static func _repair_director(state: Dictionary, contact_ids: Dictionary[int, bool], contact_definitions: Dictionary[StringName, ThreatDefinition], raid_definition_ids: Dictionary[StringName, bool], defense_ids: Dictionary[int, bool], district_ids: Dictionary[StringName, bool], repairs: Array[String]) -> void:
	var repaired_history := ThreatDirector.repair_history_state(state, raid_definition_ids)
	if repaired_history != state:
		state.merge(repaired_history, true)
		repairs.append("공습 생성 이력을 정리했습니다")
	if state.get("opening_threat_ids") is Array:
		var ids: Array = []
		for value: Variant in state.opening_threat_ids:
			var id := int(value)
			if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and contact_ids.has(id) and not ids.has(id):
				ids.append(id)
			else:
				repairs.append("없는 위협을 참조하는 첫 공습 ID를 제거했습니다")
		state.opening_threat_ids = ids
	if state.get("pending_waves") is Array:
		var waves: Array = []
		for value: Variant in state.pending_waves:
			if value is Dictionary and contact_definitions.has(StringName(String(value.get("definition_id", "")))) and float(value.get("remaining", -1.0)) >= 0.0 and is_finite(float(value.get("angle", NAN))) and value.get("opening_raid", false) is bool:
				var wave := value as Dictionary
				if not ThreatDirector.planned_target_validation_error(wave, defense_ids).is_empty():
					ThreatDirector.clear_planned_target(wave)
					repairs.append("예약 공격의 유효하지 않은 관측 표적을 제거했습니다")
				if not ThreatDirector.city_district_validation_error(wave, district_ids).is_empty():
					wave.erase(ThreatDirector.CITY_DISTRICT_KEY)
					repairs.append("예약 공격의 유효하지 않은 도시 지구를 제거했습니다")
				waves.append(value)
			else:
				repairs.append("유효하지 않은 예약 공격 파동을 제거했습니다")
		state.pending_waves = waves

static func _repair_enemy_knowledge(state: Dictionary, defense_ids: Dictionary[int, bool], contacts: Array, contact_definitions: Dictionary[StringName, ThreatDefinition], repairs: Array[String]) -> void:
	for key: String in ["estimates", "reports", "recon_sightings"]:
		if not state.get(key) is Array:
			continue
		var entries: Array = []
		for value: Variant in state[key]:
			if value is Dictionary and defense_ids.has(int(value.get("asset_id", value.get("id", 0)))):
				entries.append(value)
			else:
				repairs.append("없는 자산을 참조하는 적 지식을 제거했습니다")
		state[key] = entries
	var recon_owners: Dictionary[int, bool] = {}
	for value: Variant in contacts:
		if not value is Dictionary:
			continue
		var definition: ThreatDefinition = contact_definitions.get(StringName(String(value.get("definition_id", ""))))
		var mission := definition.mission_definition() if definition != null else null
		if mission != null and mission.area_recon and bool(value.get("active", false)):
			recon_owners[int(value.get("runtime_id", 0))] = true
	var search: Variant = state.get("recon_search")
	if search is Dictionary and search.get("assignments") is Array:
		var assignments: Array = []
		for value: Variant in search.assignments:
			if value is Dictionary and recon_owners.has(int(value.get("owner", 0))):
				assignments.append(value)
			else:
				repairs.append("없는 정찰기의 구역 배정을 제거했습니다")
		search.assignments = assignments

static func validation_error(payload: Dictionary, scenario: ScenarioDefinition) -> String:
	if int(payload.scenario.get("world_seed", -1)) < 0:
		return "전장 seed가 올바르지 않습니다"
	var layout_id := StringName(String(payload.scenario.get("battlefield_layout_id", "")))
	if not layout_id.is_empty() and scenario.battlefield_layout_by_id(layout_id) == null:
		return "저장된 전장 레이아웃을 찾을 수 없습니다"
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
	var smoke_counts_by_district: Dictionary[StringName, int] = {}
	var smoke_district_ids := city_district_definition_ids(scenario)
	for smoke_state: Variant in damage_smoke_states:
		if not smoke_state is Dictionary or not SaveDocument.is_valid_vector3_data(smoke_state.get("offset")) or float(smoke_state.get("building_height", 0.0)) <= 0.0:
			return "도시 손상 연기 위치가 올바르지 않습니다"
		var district_id := StringName(String(smoke_state.get("district_id", "")))
		if not district_id.is_empty() and not smoke_district_ids.has(district_id):
			return "도시 손상 연기 지구가 올바르지 않습니다"
		smoke_counts_by_district[district_id] = smoke_counts_by_district.get(district_id, 0) + 1
		if smoke_counts_by_district[district_id] > ProtectedObjective.MAX_DAMAGE_SMOKE_SITES_PER_DISTRICT:
			return "도시 지구별 손상 연기 수가 올바르지 않습니다"
		var repair_at: Variant = smoke_state.get("repair_at")
		if not (repair_at is int or repair_at is float) or not is_finite(float(repair_at)) or float(repair_at) != floorf(float(repair_at)) or float(repair_at) <= float(world_state.objective_integrity) or float(repair_at) > scenario.objective_definition.maximum_integrity:
			return "도시 연기 수리 단계가 올바르지 않습니다"
	var has_final_smoke := false
	for smoke_state: Dictionary in damage_smoke_states:
		has_final_smoke = has_final_smoke or int(smoke_state.repair_at) == scenario.objective_definition.maximum_integrity
	if not damage_smoke_states.is_empty() and not has_final_smoke:
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
	var all_contact_ids: Dictionary[int, bool] = {}
	for state: Dictionary in world_state.contacts:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not contact_definitions.has(definition_id):
			return "저장된 접촉 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		var runtime_id := int(state.get("runtime_id", 0))
		if runtime_id == 0 or all_contact_ids.has(runtime_id):
			return "접촉 runtime ID가 올바르지 않습니다"
		all_contact_ids[runtime_id] = true
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
			contact_ids[runtime_id] = true
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
		var track_error := _track_validation_error(track_state, sensor_ids)
		if not track_error.is_empty():
			return track_error
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
	var recent_definitions: Variant = director_state.get("recent_raid_definitions")
	if not recent_definitions is Array or recent_definitions.size() > RaidPlanner.MAX_GROUPS:
		return "최근 공습 위협 이력이 올바르지 않습니다"
	var valid_raid_definitions: Dictionary[StringName, bool] = {}
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		valid_raid_definitions[entry.threat_definition.id] = true
	var seen_recent_definitions: Dictionary[StringName, bool] = {}
	for value: Variant in recent_definitions:
		var definition_id := StringName(String(value))
		if not value is String or not valid_raid_definitions.has(definition_id) or seen_recent_definitions.has(definition_id):
			return "최근 공습 위협 이력이 올바르지 않습니다"
		seen_recent_definitions[definition_id] = true
	var debuted: Variant = director_state.get("debuted_threat_ids")
	if not debuted is Array:
		return "위협 첫 출격 이력이 올바르지 않습니다"
	var seen_debuted: Dictionary[StringName, bool] = {}
	for value: Variant in debuted:
		var definition_id := StringName(String(value))
		if not value is String or not valid_raid_definitions.has(definition_id) or seen_debuted.has(definition_id):
			return "위협 첫 출격 이력이 올바르지 않습니다"
		seen_debuted[definition_id] = true
	if float(director_state.get("elapsed", -1.0)) < 0.0 or float(director_state.get("until_spawn", -1.0)) < 0.0 or int(director_state.get("pressure_level", 0)) < 1 or int(director_state.get("next_runtime_id", 0)) < 1 or int(director_state.get("completed_attack_windows", -1)) < 0 or int(director_state.get("last_assessed_outcome_id", -1)) < 0 or int(director_state.get("suppression_failure_streak", -1)) < 0 or not director_state.get("in_recovery", null) is bool or not director_state.get("pending_waves", null) is Array:
		return "공격 Director 상태가 올바르지 않습니다"
	var opening_error := ThreatDirector.opening_state_validation_error(director_state)
	if not opening_error.is_empty():
		return opening_error
	for id: Variant in director_state.opening_threat_ids:
		if not contact_ids.has(int(id)):
			return "첫 공습이 존재하지 않는 위협을 참조합니다"
	var valid_district_ids := city_district_definition_ids(scenario)
	for wave: Dictionary in director_state.pending_waves:
		var definition_id := StringName(String(wave.get("definition_id", "")))
		if not contact_definitions.has(definition_id) or float(wave.get("remaining", -1.0)) < 0.0 or not is_finite(float(wave.get("angle", NAN))):
			return "예약 공격 파동 상태가 올바르지 않습니다"
		var target_error := ThreatDirector.planned_target_validation_error(wave, defense_ids)
		if not target_error.is_empty():
			return target_error
		var district_error := ThreatDirector.city_district_validation_error(wave, valid_district_ids)
		if not district_error.is_empty():
			return district_error
	var enemy_state: Dictionary = world_state.enemy_knowledge
	if float(enemy_state.get("simulation_time", -1.0)) < 0.0 or int(enemy_state.get("next_outcome_id", 0)) < 1 or not enemy_state.get("estimates", null) is Array or not enemy_state.get("reports", null) is Array or not enemy_state.get("recent_outcomes", null) is Array:
		return "적 지식 상태가 올바르지 않습니다"
	var outcome_ids: Dictionary[int, bool] = {}
	for outcome: Dictionary in enemy_state.recent_outcomes:
		var outcome_id := int(outcome.get("outcome_id", 0))
		if outcome_id <= 0 or outcome_id >= int(enemy_state.next_outcome_id) or outcome_ids.has(outcome_id) or not SaveDocument.is_valid_vector3_data(outcome.get("position")):
			return "적 전투 결과 상태가 올바르지 않습니다"
		outcome_ids[outcome_id] = true
		if outcome.has("target_asset_id") and (not defense_ids.has(int(outcome.target_asset_id)) or not outcome.get("mission_succeeded", false) is bool or float(outcome.get("damage", -1.0)) < 0.0 or not outcome.get("target_disabled", false) is bool):
			return "적 시설 타격 결과가 올바르지 않습니다"
	if int(director_state.last_assessed_outcome_id) >= int(enemy_state.next_outcome_id):
		return "적 전투 결과 평가 위치가 올바르지 않습니다"
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

static func city_district_definition_ids(scenario: ScenarioDefinition) -> Dictionary[StringName, bool]:
	var result: Dictionary[StringName, bool] = {}
	if scenario == null:
		return result
	for district: CityDistrictDefinition in scenario.battlefield_layout().city_districts:
		result[district.id] = true
	if result.is_empty():
		result[WorldGenerator.CENTRAL_DISTRICT_ID] = true
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
