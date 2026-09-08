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
	asset.definition = preload("res://main/first_scenario.tres").available_defenses[0]
	asset.runtime_id = 10
	assets.add_child(asset)
	asset.set_process(false)
	knowledge.configure_recon(assets, world, 600.0)

func scan() -> void:
	knowledge.gameplay_tick(0.5)
	knowledge.record_recon_area(Vector3(0, 145, 0), 85.0)

func test_sensor_requires_range_and_clear_building_and_terrain_sightlines() -> void:
	asset.position.x = 200.0
	scan()
	assert_true(knowledge.estimates.is_empty())
	asset.position.x = 0.0
	world.building_hidden = true
	scan()
	assert_true(knowledge.estimates.is_empty())
	world.building_hidden = false
	world.terrain_hidden = true
	scan()
	assert_true(knowledge.estimates.is_empty())
	world.terrain_hidden = false
	scan()
	assert_has(knowledge.estimates, 10)

func test_dwell_classifies_and_improves_position_without_multiplying_cameras() -> void:
	scan()
	assert_eq(knowledge.estimates[10].role, "")
	var initial := float(knowledge.estimates[10].confidence)
	var initial_error := float(knowledge.estimates[10].uncertainty)
	knowledge.record_recon_area(Vector3(0, 145, 0), 85.0)
	assert_eq(knowledge.estimates[10].confidence, initial)
	knowledge.gameplay_tick(0.1)
	knowledge.record_recon_area(Vector3(0, 145, 0), 85.0)
	assert_almost_eq(float(knowledge.sightings[10].seconds), 0.6, 0.001, "엇갈린 센서 주기도 실제 관측 시간을 초과하지 않습니다")
	for step: int in 7:
		scan()
	assert_eq(knowledge.estimates[10].role, "weapon")
	assert_gt(float(knowledge.estimates[10].confidence), initial)
	assert_lt(float(knowledge.estimates[10].uncertainty), initial_error)

func test_revisit_rejects_vacated_report_without_tracking_hidden_movement() -> void:
	for step: int in 8:
		scan()
	var report := knowledge.estimates[10].duplicate(true)
	asset.position.x = 500.0
	knowledge.gameplay_tick(1.0)
	assert_eq(knowledge.estimates[10].estimated_position, report.estimated_position)
	world.building_hidden = true
	scan()
	assert_has(knowledge.estimates, 10)
	world.building_hidden = false
	scan()
	assert_false(knowledge.estimates.has(10))

func test_partial_observations_and_assignments_survive_save() -> void:
	scan()
	knowledge.search_target(123, Vector3(300, 100, 0))
	var state := knowledge.capture_state()
	var restored := add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	restored.configure_recon(assets, world, 600.0)
	restored.restore_state(state)
	assert_eq(restored.capture_state(), state)
	assert_eq(EnemyKnowledge.recon_validation_error(state, 600.0, {10: true}), "")
	state.recon_sightings[0].seconds = -1.0
	assert_ne(EnemyKnowledge.recon_validation_error(state, 600.0, {10: true}), "")
