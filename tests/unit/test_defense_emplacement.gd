extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")

func _deployed(definition: DefenseDefinition) -> DefenseUnit:
	var unit := definition.scene.instantiate() as DefenseUnit
	add_child_autofree(unit)
	unit.setup(1, definition)
	return unit

func test_every_asset_stands_on_a_pad_inside_its_footprint() -> void:
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		var unit := _deployed(definition)
		assert_not_null(unit.emplacement, String(definition.id))
		if unit.emplacement == null:
			continue
		var bounds := unit.emplacement.global_transform * unit.emplacement.get_aabb()
		var world_radius := maxf(bounds.size.x, bounds.size.z) * 0.5
		assert_lte(world_radius, definition.placement_profile.footprint_radius, "%s: 받침이 배치 점유 반경을 넘지 않습니다" % definition.id)

func test_pad_does_not_enlarge_the_pickable_silhouette() -> void:
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		var unit := _deployed(definition)
		assert_false(unit.pointer_target.meshes.has(unit.emplacement), String(definition.id))

func test_identical_assets_share_pad_geometry() -> void:
	var definition: DefenseDefinition = SCENARIO.available_defenses[0]
	var first := _deployed(definition)
	var second := _deployed(definition)
	assert_same(first.emplacement.mesh, second.emplacement.mesh)
