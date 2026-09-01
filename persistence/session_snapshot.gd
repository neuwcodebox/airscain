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
	return {
		"scenario": {
			"world_seed": main.scenario.world_seed,
		},
		"session": main.session.capture_state(),
		"world": {
			"objective_integrity": main.objective.current_integrity,
			"defenses": defense_states,
			"contacts": contact_states,
			"projectiles": [],
		},
		"player_knowledge": {"tracks": []},
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
	if not world_state.get("defenses", null) is Array or not world_state.get("contacts", null) is Array:
		return "월드 객체 목록이 올바르지 않습니다"
	var defense_definitions := defense_definition_map(scenario)
	var contact_definitions := contact_definition_map(scenario)
	var defense_ids: Dictionary[int, bool] = {}
	for state: Dictionary in world_state.defenses:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not defense_definitions.has(definition_id):
			return "저장된 방공망 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		var runtime_id := int(state.get("runtime_id", 0))
		if runtime_id <= 0 or defense_ids.has(runtime_id):
			return "방공망 runtime ID가 올바르지 않습니다"
		defense_ids[runtime_id] = true
		if not _valid_vector_data(state.get("position")):
			return "방공망 위치가 올바르지 않습니다"
	for state: Dictionary in world_state.contacts:
		var definition_id := StringName(String(state.get("definition_id", "")))
		if not contact_definitions.has(definition_id):
			return "저장된 접촉 콘텐츠를 찾을 수 없습니다: %s" % definition_id
		if not _valid_vector_data(state.get("position")):
			return "접촉 위치가 올바르지 않습니다"
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
