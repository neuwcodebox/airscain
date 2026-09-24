extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func test_city_uses_a_bounded_set_of_shared_surfaces() -> void:
	for layout_id: StringName in [&"rugged_harbor", &"island_city", &"valley_corridor", &"coastal_plain"]:
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.selected_battlefield_layout_id = layout_id
		var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
		field.build(scenario)
		# Every distinct surface is a separate batch in each city cell.
		assert_lte(field.smoke_shadow_materials.size(), 26, String(layout_id))

func test_city_roofs_carry_rooftop_details() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	assert_gt(field.city_rooftop_detail_count, field.city_buildings.size(), "대부분의 옥상에 설비가 있습니다")
