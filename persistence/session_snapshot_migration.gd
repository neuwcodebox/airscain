class_name SessionSnapshotMigration
extends RefCounted

static func migrate_content(
	payload: Dictionary,
	version: int,
	scenario: ScenarioDefinition,
	defense_definitions: Dictionary[StringName, DefenseDefinition],
	contact_definitions: Dictionary[StringName, ThreatDefinition]
) -> Dictionary:
	if version >= SaveDocument.CURRENT_VERSION:
		return payload
	var result := payload.duplicate(true)
	# Version 33 records temporary harbor closure; earlier operations start with
	# an operational port and keep their existing support schedule.
	if version < 33 and result.get("world") is Dictionary:
		result.world.harbor = {"closed_from": -1.0, "closed_until": 0.0, "deliveries": []}
	# Version 32 records delivered operation briefings; older operations have
	# already seen every phase up to the threat level they reached.
	if version < 32 and scenario != null:
		result.briefings = OperationBriefingController.legacy_state(scenario, int(result.get("session", {}).get("current_pressure", 1)))
	# Version 31 records which threats already flew so debut weighting skips
	# content an older operation has presumably seen at its saved threat level.
	if version < 31 and result.get("director") is Dictionary and scenario != null:
		var debuted: Array = []
		for entry: ThreatSpawnEntry in scenario.threat_entries:
			if scenario.is_threat_available(entry, int(result.director.get("pressure_level", 1))) and not debuted.has(String(entry.threat_definition.id)):
				debuted.append(String(entry.threat_definition.id))
		result.director.debuted_threat_ids = debuted
	# Version 30 assigns saved city smoke sites to districts. The runtime resolves
	# legacy sites from their impact positions after rebuilding the battlefield.
	if version < 30:
		for site: Variant in result.get("world", {}).get("objective_damage_smoke", []):
			if site is Dictionary:
				site.district_id = ""
	var legacy_repairs: Dictionary[int, float] = {}
	for state: Dictionary in result.get("world", {}).get("defenses", []):
		var definition: DefenseDefinition = defense_definitions.get(StringName(state.get("definition_id", "")))
		if definition != null:
			legacy_repairs[int(state.get("runtime_id", 0))] = definition.maximum_integrity - float(state.get("integrity", 0.0))
	for task: Dictionary in result.get("world", {}).get("support", {}).get("tasks", []):
		if String(task.get("kind", "")) == SupportManager.REPAIR and not task.has("repair_amount"):
			task.repair_amount = legacy_repairs.get(int(task.get("target_defense_id", 0)), 0.0)
	# Version 29 assigns one target district to every newly planned city raid.
	# Older pending waves intentionally choose a valid district when they spawn.
	# Version 28 gives combat outcomes stable identities and preserves the
	# suppression follow-up assessment across saves.
	if version < 28:
		if result.get("director") is Dictionary:
			result.director.last_assessed_outcome_id = 0
			result.director.suppression_failure_streak = 0
		var enemy_state: Variant = result.get("world", {}).get("enemy_knowledge")
		if enemy_state is Dictionary:
			var next_outcome_id := 1
			for outcome: Variant in enemy_state.get("recent_outcomes", []):
				if outcome is Dictionary:
					outcome.outcome_id = next_outcome_id
					next_outcome_id += 1
			enemy_state.next_outcome_id = next_outcome_id
	# Version 27 adds optional observed-target snapshots to newly planned waves.
	# Older pending waves intentionally retain their legacy spawn-time selection.
	if version < 26 and result.get("director") is Dictionary:
		result.director.recent_raid_definitions = []
	if version >= 25:
		return result
	if version >= 23:
		return result
	if result.get("director") is Dictionary and not result.director.has("opening_raid_started"):
		var state: Dictionary = result.director
		var level := int(state.get("pressure_level", 1))
		var elapsed := float(state.get("elapsed", 0.0))
		state.opening_raid_started = level >= 2 or elapsed > 0.0
		state.opening_raid_complete = level >= 2
		state.opening_threat_ids = []
		state.pressure_started_at = elapsed - float(level - 2) * scenario.pressure_step_duration if level >= 2 else 0.0
		if level == 1:
			for contact: Dictionary in result.world.get("contacts", []):
				var definition: ThreatDefinition = contact_definitions.get(StringName(contact.get("definition_id", "")))
				if definition != null and definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
					state.opening_threat_ids.append(int(contact.get("runtime_id", 0)))
			for wave: Dictionary in state.get("pending_waves", []):
				wave["opening_raid"] = true
			state.opening_raid_started = state.opening_raid_started or not state.opening_threat_ids.is_empty() or not state.get("pending_waves", []).is_empty()
	if version >= 22:
		return result
	if result.get("director") is Dictionary:
		result.director.last_raid_pattern = ""
	if version >= 21:
		return result
	var support: Variant = result.world.get("support", {})
	if support is Dictionary and support.get("tasks") is Array:
		for task: Variant in support.tasks:
			if task is Dictionary:
				# Old resupply tasks have no reliable record of request origin.
				task.user_requested = String(task.get("kind", "")) == SupportManager.REPAIR
	if version >= 20:
		return result
	var smoke_sites: Variant = result.world.get("objective_damage_smoke", [])
	if smoke_sites is Array:
		var integrity := int(result.world.get("objective_integrity", 0))
		var maximum := scenario.objective_definition.maximum_integrity
		if integrity >= maximum:
			result.world.objective_damage_smoke = []
		else:
			for index: int in smoke_sites.size():
				if smoke_sites[index] is Dictionary:
					smoke_sites[index].repair_at = ProtectedObjective.smoke_repair_threshold(integrity, maximum, index, smoke_sites.size())
	var owner_kinds: Dictionary[int, StringName] = {}
	if result.world.get("defenses") is Array:
		for state: Variant in result.world.defenses:
			if not state is Dictionary or not state.get("content_state") is Dictionary:
				continue
			var id := StringName(String(state.get("definition_id", "")))
			if defense_definitions.has(id):
				state.content_state = (defense_definitions[id] as DefenseDefinition).migrate_runtime_state(state.content_state, version)
				owner_kinds[int(state.get("runtime_id", 0))] = (defense_definitions[id] as DefenseDefinition).engagement_reservation_kind()
	if result.world.get("engagements") is Dictionary and result.world.engagements.get("reservations") is Array:
		var upgraded: Array = []
		var support_by_owner: Dictionary[int, Dictionary] = {}
		for reservation: Variant in result.world.engagements.reservations:
			if not reservation is Dictionary:
				upgraded.append(reservation)
				continue
			var owner_id := int(reservation.get("owner_defense_id", 0))
			reservation.kind = String(owner_kinds.get(owner_id, EngagementCoordinator.INTERCEPTOR))
			if StringName(reservation.kind) == EngagementCoordinator.FIRE_SUPPORT:
				if support_by_owner.has(owner_id):
					var prior := support_by_owner[owner_id]
					if float(reservation.get("remaining", 0)) > float(prior.get("remaining", 0)):
						prior.merge(reservation, true)
					continue
				support_by_owner[owner_id] = reservation
			upgraded.append(reservation)
		result.world.engagements.reservations = upgraded
	return result
