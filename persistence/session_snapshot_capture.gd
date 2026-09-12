class_name SessionSnapshotCapture
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
		elif child is InterceptorDrone and not child.is_queued_for_deletion():
			projectile_states.append((child as InterceptorDrone).capture_state())
	for child: Node in main.threat_parent.get_children():
		if child is AirStrikeMunition and not child.is_queued_for_deletion():
			projectile_states.append((child as AirStrikeMunition).capture_state())
	return {
		"scenario": {
			"world_seed": main.scenario.world_seed,
		},
		"session": main.session.capture_state(),
		"world": {
			"objective_integrity": main.objective.current_integrity,
			"objective_damage_smoke": main.objective.capture_damage_smoke_state(),
			"defenses": defense_states,
			"contacts": contact_states,
			"projectiles": projectile_states,
			"engagements": main.engagement_coordinator.capture_state(),
			"support": main.support_manager.capture_state(),
			"relocations": main.relocation_manager.capture_state(),
			"enemy_knowledge": main.enemy_knowledge.capture_state(),
		},
		"player_knowledge": main.player_knowledge.capture_state(),
		"director": main.director.capture_state(),
	}
