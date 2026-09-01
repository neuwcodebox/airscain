extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_reports_build_role_estimates_that_age_over_time() -> void:
	var knowledge: EnemyKnowledge = add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	var radar: SearchRadar = add_child_autofree((SCENARIO.available_defenses[1] as SearchRadarDefinition).scene.instantiate()) as SearchRadar
	radar.setup(11, SCENARIO.available_defenses[1])
	radar.global_position = Vector3(240.0, 10.0, -80.0)
	knowledge.record_emission(radar)
	assert_eq(knowledge.reports.back().source, "radar_emission")
	var initial := knowledge.best_estimate_for_role(&"sensor")
	assert_eq(initial.asset_id, 11)
	assert_eq(initial.confidence, 0.42)
	var initial_uncertainty := float(initial.uncertainty)
	knowledge.gameplay_tick(30.0)
	var aged := knowledge.best_estimate_for_role(&"sensor")
	assert_lt(float(aged.confidence), 0.42)
	assert_gt(float(aged.uncertainty), initial_uncertainty)
	knowledge.record_recon(radar)
	var recon := knowledge.best_estimate_for_role(&"sensor")
	assert_eq(recon.source, "reconnaissance")
	assert_eq(recon.confidence, 0.92)
	assert_lt(float(recon.uncertainty), float(aged.uncertainty))

func test_engagement_and_outcome_reports_round_trip() -> void:
	var knowledge: EnemyKnowledge = add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	var battery: MissileBattery = add_child_autofree((SCENARIO.available_defenses[0] as MissileBatteryDefinition).scene.instantiate()) as MissileBattery
	battery.setup(21, SCENARIO.available_defenses[0])
	knowledge.record_engagement(battery, &"missile")
	knowledge.record_outcome(true, Vector3(15.0, 20.0, 25.0), &"attack_uav")
	assert_eq(knowledge.reports.back().source, "engagement:missile")
	assert_true(knowledge.recent_outcomes.back().neutralized)
	var restored: EnemyKnowledge = add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	restored.restore_state(knowledge.capture_state())
	assert_eq(restored.capture_state(), knowledge.capture_state())
