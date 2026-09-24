extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func _generator(seed_value: int) -> WorldGenerator:
	var generator := WorldGenerator.new()
	generator.generate(seed_value, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	return generator

func _cover(generator: WorldGenerator) -> GroundCover:
	var cover := GroundCover.new()
	cover.build(generator, generator.city_block_layout())
	return cover

func test_city_blocks_have_no_forest_or_farmland() -> void:
	var generator := _generator(73129)
	var cover := _cover(generator)
	for block: Dictionary in generator.city_block_layout():
		var center: Vector3 = block.position
		var label := "%s %s" % [block.district_id, block.grid]
		assert_almost_eq(cover.forest_at(center.x, center.z), 0.0, 0.01, label)
		assert_almost_eq(cover.farmland_at(center.x, center.z), 0.0, 0.01, label)

func test_sea_has_no_forest_or_farmland() -> void:
	var generator := _generator(73129)
	var cover := _cover(generator)
	var half := generator.size * 0.5
	for point: Vector2 in [Vector2(-half * 0.97, 0.0), Vector2(half * 0.97, 0.0), Vector2(0.0, -half * 0.97), Vector2(0.0, half * 0.97)]:
		assert_lt(generator.height_at(point.x, point.y), generator.sea_level, "fixture %s is offshore" % point)
		assert_almost_eq(cover.forest_at(point.x, point.y), 0.0, 0.01, str(point))
		assert_almost_eq(cover.farmland_at(point.x, point.y), 0.0, 0.01, str(point))

func test_same_seed_scatters_identical_scenery() -> void:
	var first := add_child_autofree(Vegetation.new()) as Vegetation
	var second := add_child_autofree(Vegetation.new()) as Vegetation
	var generator := _generator(4242)
	first.build(generator, _cover(generator))
	second.build(generator, _cover(generator))
	assert_eq(first.instance_counts, second.instance_counts)
	assert_gt(first.instance_counts.get(Vegetation.Kind.BROADLEAF, 0) + first.instance_counts.get(Vegetation.Kind.PINE, 0), 500, "숲이 전장을 채웁니다")

func test_placed_equipment_clears_scenery_from_its_footprint() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var site := _densest_forest_site(field)
	assert_gt(field.vegetation.standing_within(site, 12.0), 0, "fixture site is wooded")
	field.register_occupancy(site, 10.0)
	assert_eq(field.vegetation.standing_within(site, 12.0), 0)

func _densest_forest_site(field: Battlefield) -> Vector3:
	var best := Vector3.ZERO
	var best_forest := -1.0
	for x: int in range(-1000, 1001, 50):
		for z: int in range(-1000, 1001, 50):
			var forest := field.ground_cover.forest_at(float(x), float(z))
			if forest > best_forest:
				best_forest = forest
				best = Vector3(float(x), field.terrain_height(float(x), float(z)), float(z))
	return best
