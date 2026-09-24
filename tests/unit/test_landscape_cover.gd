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

func _layout_generator(layout_id: StringName) -> WorldGenerator:
	var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	scenario.selected_battlefield_layout_id = layout_id
	var generator := WorldGenerator.new()
	generator.generate(scenario.world_seed, scenario.battlefield_size, scenario.terrain_resolution, scenario.city_size, scenario.battlefield_layout())
	return generator

func test_farmed_fields_are_flat_lowland_in_groups() -> void:
	var checked := 0
	for layout_id: StringName in [&"rugged_harbor", &"island_city", &"valley_corridor", &"coastal_plain"]:
		var generator := _layout_generator(layout_id)
		var cover := _cover(generator)
		for cell: Vector2i in cover.farmed_cells:
			var label := "%s %s" % [layout_id, cell]
			var lowest := INF
			var highest := -INF
			for corner: Vector2 in [Vector2(0.05, 0.05), Vector2(0.95, 0.05), Vector2(0.05, 0.95), Vector2(0.95, 0.95), Vector2(0.5, 0.5)]:
				var point := cover._from_field((Vector2(cell) + corner) * GroundCover.FIELD_CELL)
				var height := generator.height_at(point.x, point.y)
				lowest = minf(lowest, height)
				highest = maxf(highest, height)
			assert_lte(highest - lowest, GroundCover.FIELD_MAXIMUM_RELIEF + 1.0, "%s: 필지 전체가 완만합니다" % label)
			assert_lt(highest, generator.sea_level + GroundCover.FIELD_MAXIMUM_HEIGHT, "%s: 구릉 정상이 아닌 저지대입니다" % label)
			var neighbors := 0
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				neighbors += 1 if cover.farmed_cells.has(cell + offset) else 0
			assert_gt(neighbors, 0, "%s: 외톨이 필지가 없습니다" % label)
			checked += 1
	assert_gt(checked, 0, "평야 전장에는 경작지가 생깁니다")

func test_no_scenery_stands_on_farmed_fields() -> void:
	var generator := _layout_generator(&"coastal_plain")
	var cover := _cover(generator)
	var vegetation := add_child_autofree(Vegetation.new()) as Vegetation
	vegetation.build(generator, cover)
	var on_fields := 0
	for position: Vector3 in vegetation.standing_positions():
		if cover.is_farmed(position.x, position.z):
			on_fields += 1
	assert_eq(on_fields, 0)
