extends GutTest

const RADAR_DECOY := preload("res://defense/decoy/radar_decoy.tres")
const WEAPON_DECOY := preload("res://defense/decoy/weapon_decoy.tres")

func test_decoys_report_their_spoofed_roles_without_defense_capabilities() -> void:
	var knowledge := add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	for definition: DecoyDefinition in [RADAR_DECOY, WEAPON_DECOY]:
		var decoy := add_child_autofree(definition.scene.instantiate()) as DecoyUnit
		decoy.setup(10 if definition.spoof_role == "sensor" else 11, definition)
		decoy.configure_enemy_knowledge(knowledge)
		assert_eq(definition.validation_error(), "", String(definition.id))
		assert_eq(decoy.c2_roles(), 0, String(definition.id))
		assert_false(decoy.uses_ammunition(), String(definition.id))
		assert_false(decoy.can_request_repair(), String(definition.id))
		assert_gt(decoy.pointer_target.meshes.size(), 0, String(definition.id))
		knowledge.record_recon(decoy)
		assert_eq(String(knowledge.estimates[decoy.runtime_id].role), definition.spoof_role, String(definition.id))

func test_radar_decoy_emits_a_false_radar_report_without_scanning() -> void:
	var knowledge := add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	var decoy := add_child_autofree(RADAR_DECOY.scene.instantiate()) as DecoyUnit
	decoy.setup(31, RADAR_DECOY)
	decoy.configure_enemy_knowledge(knowledge)
	decoy.gameplay_tick(0.1)
	assert_eq(knowledge.reports.back().source, "radar_emission")
	assert_eq(knowledge.best_estimate_for_role(&"sensor").asset_id, 31)
	assert_eq(decoy.c2_roles(), 0)
	assert_eq(decoy.power_demand(), 0.0)

func test_first_positive_hit_destroys_a_decoy_once() -> void:
	var decoy := add_child_autofree(WEAPON_DECOY.scene.instantiate()) as DecoyUnit
	decoy.setup(42, WEAPON_DECOY)
	watch_signals(decoy)
	assert_true(decoy.receive_damage(0.1))
	assert_false(decoy.active)
	assert_eq(decoy.integrity, 0.0)
	assert_signal_emit_count(decoy, "destroyed", 1)
	assert_false(decoy.receive_damage(10.0))
	assert_signal_emit_count(decoy, "destroyed", 1)
