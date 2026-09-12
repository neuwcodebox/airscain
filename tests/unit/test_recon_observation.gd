extends GutTest

class OccludingWorld:
	extends Battlefield
	var building_hidden: bool = false
	var terrain_hidden: bool = false
	func building_blocks_segment(_a: Vector3, _b: Vector3) -> bool:
		return building_hidden
	func terrain_segment_impact(_a: Vector3, _b: Vector3) -> Dictionary:
		return {"position": Vector3.ZERO} if terrain_hidden else {}
	func terrain_height(_x: float, _z: float) -> float:
		return 0.0
	func flight_surface_height(_x: float, _z: float) -> float:
		return 0.0

var knowledge: EnemyKnowledge
var world: OccludingWorld
var assets: Node3D
var asset: DefenseUnit

func before_each() -> void:
	knowledge = add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	world = autofree(OccludingWorld.new()) as OccludingWorld
	assets = add_child_autofree(Node3D.new()) as Node3D
	asset = DefenseUnit.new()
	asset.definition = _defense_definition(&"missile_battery")
	assert_not_null(asset.definition, "정찰 fixture에는 weapon 역할의 missile_battery 정의가 필요합니다")
	asset.runtime_id = 10
	assets.add_child(asset)
	asset.set_process(false)
	knowledge.configure_recon(assets, world, 600.0)

func _scan() -> void:
	knowledge.gameplay_tick(0.5)
	knowledge.record_recon_area(Vector3(0, 145, 0), 85.0)

func _complete_dwell() -> void:
	for _step: int in 8:
		_scan()

func test_sensor_rejects_asset_outside_observation_area() -> void:
	asset.position.x = 200.0
	_scan()
	assert_true(knowledge.estimates.is_empty())

func test_sensor_requires_clear_building_sightline() -> void:
	world.building_hidden = true
	_scan()
	assert_true(knowledge.estimates.is_empty())
	world.building_hidden = false
	_scan()
	assert_has(knowledge.estimates, 10)

func test_sensor_requires_clear_terrain_sightline() -> void:
	world.terrain_hidden = true
	_scan()
	assert_true(knowledge.estimates.is_empty())
	world.terrain_hidden = false
	_scan()
	assert_has(knowledge.estimates, 10)

func test_repeated_area_sample_cannot_accumulate_more_than_elapsed_time() -> void:
	_scan()
	var initial := float(knowledge.estimates[10].confidence)
	knowledge.record_recon_area(Vector3(0, 145, 0), 85.0)
	assert_eq(knowledge.estimates[10].confidence, initial)
	knowledge.gameplay_tick(0.1)
	knowledge.record_recon_area(Vector3(0, 145, 0), 85.0)
	assert_almost_eq(float(knowledge.sightings[10].seconds), 0.6, 0.001, "엇갈린 센서 주기도 실제 관측 시간을 초과하지 않습니다")

func test_dwell_classifies_asset_and_improves_estimate() -> void:
	_scan()
	assert_eq(knowledge.estimates[10].role, "")
	var initial_confidence := float(knowledge.estimates[10].confidence)
	var initial_uncertainty := float(knowledge.estimates[10].uncertainty)
	for step: int in 7:
		_scan()
	assert_eq(knowledge.estimates[10].role, "weapon")
	assert_gt(float(knowledge.estimates[10].confidence), initial_confidence)
	assert_lt(float(knowledge.estimates[10].uncertainty), initial_uncertainty)

func test_estimate_does_not_follow_unobserved_asset_movement() -> void:
	_complete_dwell()
	var report := knowledge.estimates[10].duplicate(true)
	asset.position.x = 500.0
	knowledge.gameplay_tick(1.0)
	assert_eq(knowledge.estimates[10].estimated_position, report.estimated_position)

func test_revisit_keeps_occluded_report_then_rejects_vacated_position() -> void:
	_complete_dwell()
	asset.position.x = 500.0
	world.building_hidden = true
	_scan()
	assert_has(knowledge.estimates, 10)
	world.building_hidden = false
	_scan()
	assert_false(knowledge.estimates.has(10))

func test_partial_observations_and_assignments_survive_save() -> void:
	_scan()
	knowledge.search_target(123, Vector3(300, 100, 0))
	var state := knowledge.capture_state()
	var restored := add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	restored.configure_recon(assets, world, 600.0)
	restored.restore_state(state)
	assert_eq(restored.capture_state(), state)
	assert_eq(EnemyKnowledge.recon_validation_error(state, 600.0, {10: true}), "")

func test_recon_validation_rejects_negative_observation_time() -> void:
	_scan()
	var state := knowledge.capture_state()
	state.recon_sightings[0].seconds = -1.0
	assert_ne(EnemyKnowledge.recon_validation_error(state, 600.0, {10: true}), "", "음수 관측 누적 시간은 복원 전에 거절합니다")

func _defense_definition(definition_id: StringName) -> DefenseDefinition:
	var scenario := preload("res://main/first_scenario.tres") as ScenarioDefinition
	for definition: DefenseDefinition in scenario.available_defenses:
		if definition.id == definition_id:
			return definition
	return null
