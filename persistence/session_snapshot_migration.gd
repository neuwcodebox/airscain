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
	var legacy_repairs: Dictionary[int, float] = {}
	for state: Dictionary in result.get("world", {}).get("defenses", []):
		var definition: DefenseDefinition = defense_definitions.get(StringName(state.get("definition_id", "")))
		if definition != null:
			legacy_repairs[int(state.get("runtime_id", 0))] = definition.maximum_integrity - float(state.get("integrity", 0.0))
	for task: Dictionary in result.get("world", {}).get("support", {}).get("tasks", []):
		if String(task.get("kind", "")) == SupportManager.REPAIR and not task.has("repair_amount"):
			task.repair_amount = legacy_repairs.get(int(task.get("target_defense_id", 0)), 0.0)
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
