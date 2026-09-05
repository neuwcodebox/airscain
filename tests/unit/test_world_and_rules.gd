extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")
const GLOBAL_FONT_PATH := "res://ui/fonts/NanumSquareB.ttf"

func test_wreck_hits_the_current_roof_instead_of_the_original_ground_height() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var bounds := field.city_building_bounds(0)
	var roof := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	var wreck := preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate() as FallingWreckEffect
	field.add_child(wreck)
	wreck.battlefield = field
	wreck.global_position = roof + Vector3.UP * 20
	wreck.setup(Color.GRAY, Vector3.DOWN * 1000, -1000)
	wreck._process(0.1)
	assert_true(wreck.impacted)
	assert_almost_eq(wreck.global_position, roof, Vector3.ONE * 0.01)
	assert_false(wreck.wreck.visible)
	assert_true(wreck.smoke_released)
	var effects := field.get_children().filter(func(node: Node) -> bool: return node is ExplosionEffect)
	assert_eq(effects.size(), 1)
	assert_almost_eq((effects[0] as Node3D).global_position, roof, Vector3.ONE * 0.01)

func test_lost_track_missile_pulls_up_without_changing_speed() -> void:
	var missile := add_child_autofree(preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate()) as HomingInterceptor
	missile.global_position = Vector3(0, 1000, 0)
	missile.speed = 100
	missile.maximum_lifetime = 10
	missile.turn_rate = 2.0
	missile.velocity = Vector3(1, -1, 0).normalized() * missile.speed
	var track := PlayerTrack.new()
	track.state = PlayerTrack.State.LOST
	missile.target_track = track
	var original_y := missile.velocity.y
	missile.gameplay_tick(0.1)
	assert_gt(missile.velocity.y, original_y)
	for index: int in 8:
		missile.gameplay_tick(0.1)
	assert_gt(missile.velocity.y, 0.0)
	assert_almost_eq(missile.velocity.length(), missile.speed, 0.001)
	assert_gt(missile.reacquisition_remaining, 0.0)

func test_placement_contours_are_world_local_and_do_not_change_terrain() -> void:
	var first := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	var second := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	first.build(SCENARIO)
	second.build(SCENARIO)
	var heights := first.generator.heights.duplicate()
	first.set_placement_contours(true, Vector3(120, 30, 40))
	var material := first.terrain.material_override as ShaderMaterial
	assert_eq(material.get_shader_parameter("placement_contours"), true)
	assert_ne(material, second.terrain.material_override)
	assert_ne((second.terrain.material_override as ShaderMaterial).get_shader_parameter("placement_contours"), true)
	first.set_placement_contours(false)
	assert_eq(material.get_shader_parameter("placement_contours"), false)
	assert_eq(first.generator.heights, heights)
	var placement := add_child_autofree(PlacementController.new()) as PlacementController
	placement.battlefield = first
	placement.select(SCENARIO.available_defenses[0])
	placement.candidate_position = Vector3(100, first.generator.sea_level + 45, 100)
	placement._update_elevation_guide()
	assert_true(placement.elevation_label.text.begins_with("해발 45m"))
	assert_eq(material.get_shader_parameter("placement_contours"), true)
	placement.cancel()
	assert_eq(material.get_shader_parameter("placement_contours"), false)

func test_expired_smoke_can_reuse_slots_without_restoring_old_puffs() -> void:
	var effect := add_child_autofree(preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate()) as FallingWreckEffect
	var trail := effect.smoke
	trail.emitting = true
	trail.sample_world_segment(Vector3.ZERO, Vector3(20, 0, 0))
	trail._process(trail.lifetime + 0.1)
	assert_eq(trail.multimesh.visible_instance_count, 0)
	trail.sample_world_segment(Vector3(100, 0, 0), Vector3(120, 0, 0))
	assert_gt(trail.active_puff_count(), 0)
	assert_gt(trail.smoke_bounds().position.x, 50.0)

func test_building_spatial_candidates_preserve_nearest_segment_impacts() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 27331
	for trial: int in 300:
		var start := Vector3(rng.randf_range(-500, 500), rng.randf_range(0, 150), rng.randf_range(-500, 500))
		var end := Vector3(rng.randf_range(-500, 500), rng.randf_range(0, 150), rng.randf_range(-500, 500))
		if trial < field.city_buildings.size():
			start = field.city_building_bounds(trial).get_center()
		var expected_index := -1
		var expected_position := Vector3.ZERO
		var nearest := INF
		for index: int in field.city_buildings.size():
			var hit: Variant = field.city_building_bounds(index).intersects_segment(start, end)
			if hit is Vector3 and start.distance_squared_to(hit) < nearest:
				nearest = start.distance_squared_to(hit)
				expected_index = index
				expected_position = hit
		var actual := field.building_segment_impact(start, end)
		assert_eq(int(actual.get("building_index", -1)), expected_index)
		if expected_index >= 0:
			assert_almost_eq((actual.position as Vector3).distance_to(expected_position), 0.0, 0.001)

func test_smoke_animates_shared_birth_records_without_per_puff_reuploads() -> void:
	var effect := add_child_autofree(preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate()) as FallingWreckEffect
	var trail := effect.smoke
	trail.emitting = true
	trail.sample_world_segment(Vector3.ZERO, Vector3(20, 0, 0))
	var visible_buffer := trail.multimesh.buffer
	var shadow_buffer := trail.shadow_particles.multimesh.buffer
	trail._process(0.3)
	assert_eq(trail.multimesh.buffer, visible_buffer)
	assert_eq(trail.shadow_particles.multimesh.buffer, shadow_buffer)
	assert_almost_eq(float(trail.smoke_material.get_shader_parameter("trail_time")), 0.3, 0.0001)
	assert_eq(trail.smoke_material.get_shader_parameter("trail_time"), trail.shadow_material.get_shader_parameter("trail_time"))
	assert_true(trail.multimesh.custom_aabb.has_point(Vector3(20, 0, 0)))

func test_falling_wreck_preserves_airframe_geometry_without_live_systems() -> void:
	var aircraft := add_child_autofree(preload("res://enemy/strike_aircraft/strike_aircraft.tscn").instantiate()) as Node3D
	aircraft.rotation = Vector3(0.1, 0.8, -0.2)
	var wreck := add_child_autofree(preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate()) as FallingWreckEffect
	wreck.setup(Color.GRAY, Vector3.ZERO, -100)
	wreck.use_airframe(aircraft)
	var original := aircraft.find_child("FacetedFuselage", true, false) as MeshInstance3D
	var fallen := wreck.wreck.find_child("FacetedFuselage", true, false) as MeshInstance3D
	assert_not_null(fallen)
	assert_same(fallen.mesh, original.mesh, "추락 시 원래 메시를 공유합니다")
	assert_eq(wreck.wreck.basis, aircraft.global_basis)
	assert_ne(fallen.get_active_material(0), original.get_active_material(0))
	assert_lt((fallen.get_active_material(0) as StandardMaterial3D).albedo_color.v, (original.get_active_material(0) as StandardMaterial3D).albedo_color.v)
	assert_null(wreck.wreck.find_child("LeftEngineGlow", true, false))
	assert_eq(wreck.wreck.find_children("*", "Light3D", true, false).size(), 0)
	assert_null(wreck.wreck.get_child(0).get_script(), "잔해에 비행 AI나 모델 생성 스크립트를 복제하지 않습니다")
	assert_not_null(wreck.wreck.find_child("SweptWing", true, false))
	assert_not_null(wreck.wreck.find_child("TwinFin", true, false))

func test_falling_wreck_timeout_is_ten_seconds_and_releases_trail() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var wreck := preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate() as FallingWreckEffect
	parent.add_child(wreck)
	wreck.setup(Color.GRAY, Vector3.ZERO, -100000)
	wreck.set_process(false)
	wreck._process(5.1)
	assert_false(wreck.is_queued_for_deletion())
	wreck._process(4.8)
	assert_false(wreck.is_queued_for_deletion())
	wreck._process(0.11)
	assert_true(wreck.is_queued_for_deletion())
	assert_true(wreck.smoke_released)
	assert_same(wreck.smoke.get_parent(), parent)

func test_wreck_impact_reuses_one_composite_blast_and_birds_remain_quiet() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var pool := CombatEffectPool.new()
	parent.add_child(pool)
	var initial_available := pool.available.size()
	for flash_enabled: bool in [true, false]:
		var wreck := preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate() as FallingWreckEffect
		parent.add_child(wreck)
		wreck.setup(Color.GRAY, Vector3.DOWN, 0.0, 1.0, flash_enabled, flash_enabled)
		wreck.set_process(false)
		wreck._process(0.1)
		assert_true(wreck.impacted)
		assert_false(wreck.wreck.visible)
		assert_eq(pool.available.size(), initial_available - 1, "조류는 추가 폭발을 만들지 않습니다")
		wreck._process(0.2)
		assert_eq(pool.available.size(), initial_available - 1, "착지 폭발은 한 번만 생성합니다")

func test_project_uses_bundled_bold_nanum_square_with_symbol_fallback() -> void:
	assert_eq(ProjectSettings.get_setting("gui/theme/custom_font", ""), "")
	var bundled_font := AirscainApp.apply_global_font()
	assert_not_null(bundled_font)
	assert_true(bundled_font.allow_system_fallback)
	assert_true(bundled_font.has_char("▼".unicode_at(0)))
	assert_true(bundled_font.has_char("▲".unicode_at(0)))
	var label := add_child_autofree(Label.new()) as Label
	assert_eq(label.get_theme_font("font").resource_path, GLOBAL_FONT_PATH)
	assert_eq(ThemeDB.fallback_font.resource_path, GLOBAL_FONT_PATH)

func test_first_scenario_has_all_required_references_and_valid_ranges() -> void:
	assert_eq(SCENARIO.validation_error(), "")

func test_world_seed_reproduces_height_and_city_layout() -> void:
	var first := WorldGenerator.new()
	var second := WorldGenerator.new()
	first.generate(91827, 1200.0, 49, 330.0)
	second.generate(91827, 1200.0, 49, 330.0)
	assert_almost_eq(first.height_at(412.5, -277.0), second.height_at(412.5, -277.0), 0.0001)
	assert_eq(first.heights, second.heights)
	assert_eq(first.city_block_layout(), second.city_block_layout())
	assert_eq(first.building_transforms(), second.building_transforms())

func test_city_keeps_a_dense_core_and_uses_an_irregular_terrain_suitable_edge() -> void:
	var generator := WorldGenerator.new()
	generator.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	var blocks := generator.city_block_layout()
	var row_counts: Dictionary = {}
	var has_center := false
	for block: Dictionary in blocks:
		var grid: Vector2i = block.grid
		row_counts[grid.y] = int(row_counts.get(grid.y, 0)) + 1
		if grid == Vector2i.ZERO:
			has_center = true
		if float(block.normalized_distance) > 0.34:
			var position: Vector3 = block.position
			assert_gt(generator.height_at(position.x, position.z), generator.sea_level + 3.0)
			assert_lte(generator.slope_degrees_at(position.x, position.z, SCENARIO.city_size / float(SCENARIO.battlefield_layout().city_blocks) * 0.32), 11.0)
	assert_true(has_center)
	assert_lt(blocks.size(), SCENARIO.battlefield_layout().city_blocks ** 2)
	assert_gt(blocks.size(), 45)
	var distinct_row_widths: Dictionary = {}
	for count: int in row_counts.values():
		distinct_row_widths[count] = true
	assert_gt(distinct_row_widths.size(), 2)
	assert_gt(generator.building_transforms().size(), blocks.size())

func test_active_city_footprint_is_flattened_below_roads_and_buildings() -> void:
	var generator := WorldGenerator.new()
	generator.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	var block_step := SCENARIO.city_size / float(SCENARIO.battlefield_layout().city_blocks)
	for block: Dictionary in generator.city_block_layout():
		var position: Vector3 = block.position
		for offset: Vector2 in [Vector2.ZERO, Vector2(block_step * 0.4, block_step * 0.4), Vector2(-block_step * 0.4, block_step * 0.4), Vector2(block_step * 0.4, -block_step * 0.4), Vector2(-block_step * 0.4, -block_step * 0.4)]:
			assert_almost_eq(generator.height_at(position.x + offset.x, position.z + offset.y), WorldGenerator.CITY_GROUND_HEIGHT, 0.25)

func test_city_skyline_is_taller_near_the_center() -> void:
	var generator := WorldGenerator.new()
	generator.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	var inner_heights: Array[float] = []
	var outer_heights: Array[float] = []
	for building: Transform3D in generator.building_transforms():
		var height := building.basis.get_scale().y
		if Vector2(building.origin.x, building.origin.z).length() < SCENARIO.city_size * 0.3:
			inner_heights.append(height)
		else:
			outer_heights.append(height)
	assert_gt(_average(inner_heights), _average(outer_heights))

func test_battlefield_builds_only_the_irregular_city_footprint() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	assert_eq(battlefield.city_block_surface_count, battlefield.generator.city_block_layout().size())
	var buildings := battlefield.generator.building_transforms()
	assert_eq(battlefield.city_building_footprints.size(), buildings.size())
	assert_lt(battlefield.city_block_surface_count, SCENARIO.battlefield_layout().city_blocks ** 2)
	assert_null(battlefield.city_visuals.get_node_or_null("RoadNetwork"))
	assert_not_null(battlefield.city_visuals.get_node_or_null("RoadTile0_0"))
	assert_not_null(battlefield.city_visuals.get_node_or_null("LaneX0_0"))
	assert_not_null(battlefield.city_visuals.get_node_or_null("LaneZ0_0"))
	assert_gt(battlefield.city_window_band_count, 300)
	assert_gt(battlefield.city_rooftop_detail_count, 20)
	assert_gt(battlefield.city_amenity_count, 0)
	assert_not_null(battlefield.city_visuals.get_node_or_null("FacadeWindows"))
	assert_false(battlefield.rooftop_pad_visuals.is_empty())
	for pad: MeshInstance3D in battlefield.rooftop_pad_visuals:
		assert_false(pad.visible)
	battlefield.set_rooftop_pads_visible(true)
	for pad: MeshInstance3D in battlefield.rooftop_pad_visuals:
		assert_true(pad.visible)
	battlefield.set_rooftop_pads_visible(false)

func test_city_building_targets_use_seeded_ranges_and_segments_hit_the_first_surface() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	assert_eq(battlefield.city_buildings.size(), battlefield.generator.building_transforms().size())
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 90817
	second_rng.seed = 90817
	var first_target := Vector3.ZERO
	var last_target := Vector3.ZERO
	for sample: int in 24:
		var target := battlefield.random_city_building_target(first_rng)
		assert_eq(target, battlefield.random_city_building_target(second_rng))
		var contained := false
		for index: int in battlefield.city_buildings.size():
			if battlefield.city_building_bounds(index).has_point(target):
				contained = true
				break
		assert_true(contained)
		if sample == 0:
			first_target = target
		last_target = target
	assert_gt(first_target.distance_to(last_target), 1.0)
	var bounds := battlefield.city_building_bounds(0)
	var center := bounds.get_center()
	var impact := battlefield.building_segment_impact(Vector3(bounds.position.x - 20.0, center.y, center.z), Vector3(bounds.end.x + 20.0, center.y, center.z))
	assert_false(impact.is_empty())
	assert_almost_eq((impact.position as Vector3).x, bounds.position.x, 0.001)
	assert_eq(int(impact.building_index), 0)
	assert_eq(float(impact.building_height), bounds.size.y)
	var miss := battlefield.building_segment_impact(Vector3(bounds.position.x - 20.0, bounds.end.y + 10.0, center.z), Vector3(bounds.end.x + 20.0, bounds.end.y + 10.0, center.z))
	assert_true(miss.is_empty())

func test_city_objective_uses_a_civic_landmark() -> void:
	var city := add_child_autofree(preload("res://world/objective/city/city_objective.tscn").instantiate()) as CityObjective
	assert_not_null(city.get_node_or_null("CivicHall"))
	assert_not_null(city.get_node_or_null("CivicTower"))
	assert_gt((city.get_node("CoreMarker") as MeshInstance3D).position.y, 28.0)

func test_tactical_units_use_a_smaller_presentation_scale_without_changing_profiles() -> void:
	var defense := add_child_autofree(SCENARIO.available_defenses[0].scene.instantiate()) as DefenseUnit
	defense.setup(1, SCENARIO.available_defenses[0])
	var threat := add_child_autofree(SCENARIO.threat_entries[0].threat_definition.scene.instantiate()) as ThreatUnit
	threat.setup(1, SCENARIO.threat_entries[0].threat_definition)
	assert_eq(defense.scale, Vector3.ONE * DefenseUnit.PRESENTATION_SCALE)
	assert_eq(threat.scale, Vector3.ONE * ThreatUnit.PRESENTATION_SCALE)
	assert_eq(defense.definition.placement_profile.footprint_radius, SCENARIO.available_defenses[0].placement_profile.footprint_radius)
	assert_eq(threat.definition.radar_signature, SCENARIO.threat_entries[0].threat_definition.radar_signature)

func test_every_friendly_installation_exposes_a_fixed_size_role_icon() -> void:
	var role_icons: Dictionary = {}
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		var defense := add_child_autofree(definition.scene.instantiate()) as DefenseUnit
		defense.setup(1, definition)
		assert_not_null(defense.identity_marker)
		assert_true(defense.identity_marker.visible)
		var icon := defense.identity_marker.get_node("Icon") as Label3D
		assert_true(icon.fixed_size)
		assert_true(icon.no_depth_test)
		assert_gte(icon.render_priority, 100)
		assert_eq(icon.font_size, 12)
		assert_gt(defense.identity_marker.position.y, defense.status_marker.position.y)
		role_icons[icon.text] = true
	assert_true(role_icons.has("◎"))
	assert_true(role_icons.has("◆"))
	assert_true(role_icons.has("▲"))
	assert_true(role_icons.has("■"))

func test_friendly_installation_selection_highlights_icon_and_footprint() -> void:
	var defense := add_child_autofree(SCENARIO.available_defenses[0].scene.instantiate()) as DefenseUnit
	defense.setup(1, SCENARIO.available_defenses[0])
	var icon := defense.identity_marker.get_node("Icon") as Label3D
	var selection_ring := defense.identity_marker.get_node("SelectionRing") as MeshInstance3D
	assert_false(selection_ring.visible)
	assert_eq(icon.outline_size, 4)
	defense.set_selected(true)
	assert_true(selection_ring.visible)
	assert_eq(icon.outline_size, 8)
	assert_eq(icon.scale, Vector3.ONE * 1.2)
	assert_eq((selection_ring.mesh as TorusMesh).rings, 64)
	defense.set_selected(false)
	assert_false(selection_ring.visible)
	assert_eq(icon.scale, Vector3.ONE)

func _average(values: Array[float]) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(float(values.size()), 1.0)

func test_different_world_seed_changes_height_field() -> void:
	var first := WorldGenerator.new()
	var second := WorldGenerator.new()
	first.generate(1, 1200.0, 49, 330.0)
	second.generate(2, 1200.0, 49, 330.0)
	assert_ne(first.heights, second.heights)

func test_scenario_seed_selects_reproducible_distinct_battlefield_layouts() -> void:
	assert_eq(SCENARIO.battlefield_layout().id, &"island_city")
	var alternate := SCENARIO.duplicate(true) as ScenarioDefinition
	alternate.world_seed = SCENARIO.world_seed - 1
	assert_eq(alternate.battlefield_layout().id, &"rugged_harbor")
	assert_gt(alternate.battlefield_layout().starting_budget_bonus, SCENARIO.battlefield_layout().starting_budget_bonus)
	var island := WorldGenerator.new()
	var rugged := WorldGenerator.new()
	island.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	rugged.generate(alternate.world_seed, alternate.battlefield_size, alternate.terrain_resolution, alternate.city_size, alternate.battlefield_layout())
	assert_ne(island.building_transforms().size(), rugged.building_transforms().size())
	assert_ne(island.heights, rugged.heights)

func test_island_center_is_land_and_outer_edge_is_below_sea() -> void:
	var generator := WorldGenerator.new()
	generator.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size)
	assert_gt(generator.height_at(0.0, 0.0), generator.sea_level)
	var guaranteed_land_radius := SCENARIO.battlefield_size * 0.33
	for z: int in range(-750, 751, 125):
		for x: int in range(-750, 751, 125):
			if Vector2(float(x), float(z)).length() <= guaranteed_land_radius:
				assert_gt(generator.height_at(float(x), float(z)), generator.sea_level)
	var submerged_edge := SCENARIO.battlefield_size * 0.495
	assert_lt(generator.height_at(submerged_edge, 0.0), generator.sea_level)
	assert_lt(generator.height_at(0.0, -submerged_edge), generator.sea_level)

func test_seed_shapes_an_irregular_island_coastline() -> void:
	var first := WorldGenerator.new()
	var second := WorldGenerator.new()
	first.generate(73129, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	second.generate(91827, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	var first_radii: Array[float] = []
	var second_radii: Array[float] = []
	for direction_index: int in 24:
		var angle := TAU * float(direction_index) / 24.0
		first_radii.append(_coast_radius(first, angle))
		second_radii.append(_coast_radius(second, angle))
	assert_gt(first_radii.max() - first_radii.min(), 140.0)
	assert_gt(second_radii.max() - second_radii.min(), 140.0)
	assert_ne(first_radii, second_radii)

func _coast_radius(generator: WorldGenerator, angle: float) -> float:
	for radius: int in range(450, 1181, 10):
		if generator.height_at(cos(angle) * float(radius), sin(angle) * float(radius)) <= generator.sea_level:
			return float(radius)
	return 1180.0

func test_objective_damage_and_depletion_are_bounded() -> void:
	var objective: ProtectedObjective = add_child_autofree(ProtectedObjective.new()) as ProtectedObjective
	var definition := ObjectiveDefinition.new()
	definition.maximum_integrity = 100
	objective.setup(1, definition)
	watch_signals(objective)
	var first_impact := Vector3(12.0, 30.0, -5.0)
	assert_true(objective.apply_building_impact(10, first_impact, 48.0))
	assert_eq(objective.current_integrity, 90)
	assert_eq(objective.damage_smoke_effects.size(), 1)
	assert_eq(objective.damage_smoke_effects[0].global_position, first_impact)
	var smoke := objective.damage_smoke_effects[0].get_node("Smoke") as GPUParticles3D
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	assert_eq(smoke.amount, DamageSmokeEffect.CITY_PARTICLE_COUNT)
	assert_eq(smoke.lifetime, DamageSmokeEffect.CITY_LIFETIME)
	assert_false(smoke_process.turbulence_enabled)
	assert_lte(smoke_process.spread, 7.0)
	assert_gte(smoke_process.initial_velocity_min, 7.5)
	assert_lte(smoke_process.initial_velocity_max, 10.5)
	assert_lt(smoke_process.gravity.y, 0.0)
	assert_gt(smoke_process.gravity.x, 0.0)
	assert_not_null(smoke_process.color_ramp)
	var growth_texture := smoke_process.scale_curve as CurveTexture
	assert_not_null(growth_texture)
	assert_lt(growth_texture.curve.sample(0.0), growth_texture.curve.sample(0.5))
	assert_lt(growth_texture.curve.sample(0.5), growth_texture.curve.sample(1.0))
	assert_lte(growth_texture.curve.sample(1.0), 1.3)
	assert_true(smoke.draw_pass_1 is QuadMesh)
	var smoke_material := (smoke.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert_eq(smoke_material.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_eq(smoke.preprocess, 0.0)
	assert_false(smoke.local_coords)
	assert_eq(smoke.fixed_fps, 30)
	assert_eq(smoke.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var smoke_shadow := smoke.get_node("SmokeShadow") as GPUParticles3D
	assert_eq(smoke_shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_true(smoke_shadow.draw_pass_1 is SphereMesh)
	assert_eq(smoke_shadow.amount, smoke.amount)
	assert_eq(smoke_shadow.lifetime, smoke.lifetime)
	assert_gte(smoke.visibility_aabb.size.y, 220.0)
	assert_null(objective.damage_smoke_effects[0].get_node_or_null("SmokeMiddle"))
	assert_null(objective.damage_smoke_effects[0].get_node_or_null("SmokeUpper"))
	assert_true(objective.apply_building_impact(10, Vector3(-8.0, 22.0, 14.0), 32.0))
	assert_true(objective.apply_building_impact(10, Vector3(18.0, 42.0, 20.0), 56.0))
	assert_true(objective.apply_building_impact(100, Vector3(-22.0, 35.0, -18.0), 44.0))
	assert_eq(objective.current_integrity, 0)
	assert_eq(objective.damage_smoke_effects.size(), 4)
	assert_signal_emit_count(objective, "depleted", 1)
	assert_false(objective.apply_mission_damage(10))
	assert_false(objective.apply_building_impact(10, Vector3.ZERO, 20.0))
	assert_eq(objective.damage_smoke_effects.size(), 4)
	assert_signal_emit_count(objective, "depleted", 1)
	objective.restore_integrity(75)
	assert_eq(objective.damage_smoke_effects.size(), 1)

func test_city_repair_removes_smoke_in_steps_and_preserves_the_last_site() -> void:
	var objective := add_child_autofree(SCENARIO.objective_definition.scene.instantiate()) as ProtectedObjective
	objective.setup(1, SCENARIO.objective_definition)
	var emitters := objective.prepared_smoke_effects.duplicate()
	for index: int in 4:
		objective.apply_building_impact(10, Vector3(index * 20, 20, 0), 20)
	var last_effect := objective.damage_smoke_effects.back() as DamageSmokeEffect
	var last_position := last_effect.position
	for integrity: int in range(61, 101):
		objective.restore_integrity(integrity)
		assert_eq(objective.damage_smoke_effects.size(), ceili(float(100 - integrity) / 10.0))
		assert_eq(objective.damage_smoke_effects.size() + objective.prepared_smoke_effects.size(), emitters.size())
		if integrity < 100:
			assert_same(objective.damage_smoke_effects.back(), last_effect)
			assert_eq(last_effect.position, last_position, "남은 연기는 다른 건물로 옮겨지지 않습니다")
	assert_true(objective.capture_damage_smoke_state().is_empty())
	objective.apply_building_impact(1, Vector3(100, 30, 0), 30)
	assert_eq(objective.damage_smoke_effects.size(), 1, "완료한 옛 피해 연기는 다시 나타나지 않습니다")
	assert_eq(objective.damage_smoke_effects[0].position, Vector3(100, 30, 0))

func test_city_repair_after_new_damage_never_clears_all_smoke_early() -> void:
	var objective := add_child_autofree(SCENARIO.objective_definition.scene.instantiate()) as ProtectedObjective
	objective.setup(1, SCENARIO.objective_definition)
	for index: int in 4:
		objective.apply_building_impact(10, Vector3(index * 10, 20, 0), 20)
	objective.restore_integrity(80)
	assert_eq(objective.damage_smoke_effects.size(), 2)
	objective.apply_building_impact(10, Vector3(60, 30, 0), 30)
	assert_eq(objective.damage_smoke_effects.size(), 3)
	objective.restore_integrity(99)
	assert_eq(objective.damage_smoke_effects.size(), 1)
	objective.restore_integrity(99)
	assert_eq(objective.damage_smoke_effects.size(), 1)
	objective.restore_integrity(100)
	assert_true(objective.damage_smoke_effects.is_empty())

func test_city_damage_smoke_uses_exact_building_impact_positions() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	var objective := add_child_autofree(ProtectedObjective.new()) as ProtectedObjective
	objective.global_position = Vector3(0.0, battlefield.terrain_height(0.0, 0.0), 0.0)
	var definition := ObjectiveDefinition.new()
	definition.maximum_integrity = 100
	objective.setup(1, definition)
	var bounds := battlefield.city_building_bounds(0)
	var impact := battlefield.building_segment_impact(bounds.get_center() + Vector3.LEFT * (bounds.size.x + 10.0), bounds.get_center())
	assert_true(objective.apply_building_impact(25, impact.position, float(impact.building_height)))
	assert_eq(objective.damage_smoke_effects.size(), 1)
	var effect := objective.damage_smoke_effects[0]
	assert_almost_eq(effect.global_position, impact.position as Vector3, Vector3.ONE * 0.001)
	var city_smoke := effect.get_node("Smoke") as GPUParticles3D
	var city_process := city_smoke.process_material as ParticleProcessMaterial
	assert_true(city_smoke.emitting)
	assert_false(city_process.turbulence_enabled)
	assert_gte(city_process.initial_velocity_min, 5.0)
	assert_gte(city_process.initial_velocity_min * city_smoke.lifetime, 80.0)
	var surface_impact := Vector3(24.0, battlefield.terrain_height(24.0, -18.0), -18.0)
	assert_true(objective.apply_surface_impact(10, surface_impact))
	assert_eq(objective.damage_smoke_effects.size(), 2)
	assert_almost_eq(objective.damage_smoke_effects.back().global_position, surface_impact, Vector3.ONE * 0.001)

func test_low_roof_smoke_becomes_visible_before_leaving_its_source() -> void:
	var effect := add_child_autofree(preload("res://effects/damage_smoke/damage_smoke.tscn").instantiate()) as DamageSmokeEffect
	effect.set_city_scale(1.5, 12.0)
	effect.restart_at_source()
	var process := effect.smoke.process_material as ParticleProcessMaterial
	var ramp := process.color_ramp as GradientTexture1D
	# The first visible puff must overlap the emission area, not rise several
	# metres above a low roof during an invisible fraction of its long lifetime.
	var age_near_source := 0.1 / effect.smoke.lifetime
	assert_gt(ramp.gradient.sample(age_near_source).a, 0.5)
	assert_eq(effect.smoke.shadow_particles.lifetime, effect.smoke.lifetime)
	assert_eq(effect.smoke.shadow_particles.amount_ratio, effect.smoke.amount_ratio)
	assert_true(effect.smoke.shadow_particles.emitting)

func test_all_smoke_particles_use_smooth_visible_materials_and_solid_shadow_casters() -> void:
	var smoke_cases: Array[Dictionary] = [
		{"scene": preload("res://effects/damage_smoke/damage_smoke.tscn"), "paths": ["Smoke"]},
		{"scene": preload("res://effects/explosion/explosion.tscn"), "paths": ["Smoke"]},
		{"scene": preload("res://effects/interceptor_miss/interceptor_miss.tscn"), "paths": ["Smoke"]},
	]
	for smoke_case: Dictionary in smoke_cases:
		var effect: Node = add_child_autofree((smoke_case.scene as PackedScene).instantiate())
		for path: String in smoke_case.paths:
			var particles := effect.get_node(path) as GPUParticles3D
			assert_eq(particles.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s visible pass must not cast thresholded shadows" % path)
			var mesh := particles.draw_pass_1 as Mesh
			assert_true(mesh is QuadMesh, "%s visible smoke must use a soft radial card" % path)
			var material := mesh.surface_get_material(0) as StandardMaterial3D
			assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "%s must blend smoothly without Compatibility depth-prepass centers" % path)
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL, "%s must interact with scene lighting" % path)
			var shadow := particles.get_node("SmokeShadow") as GPUParticles3D
			assert_eq(shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s GPU shadow proxy must render in Compatibility" % path)
			assert_eq(shadow.process_material, particles.process_material, "%s shadow motion must match visible smoke" % path)
			var shadow_mesh := shadow.draw_pass_1 as Mesh
			var shadow_material := shadow_mesh.surface_get_material(0) as ShaderMaterial
			assert_not_null(shadow_material, "%s shadow opacity must use the shadow-pass shader" % path)
			assert_eq(shadow_material.shader.resource_path, "res://effects/smoke_shadow.gdshader")
			assert_true(shadow_material.shader.code.contains("!IN_SHADOW_PASS"), "%s proxy must discard its camera color pass" % path)
			assert_false(shadow_material.shader.code.contains("ALPHA_HASH_SCALE"), "%s shadow must remain a solid surface instead of a pixel hash" % path)
			assert_true(shadow_material.shader.code.contains("VERTEX *= sqrt"), "%s shadow fade must contract the solid particle silhouette" % path)
			if mesh is QuadMesh:
				assert_true(shadow_mesh is SphereMesh, "%s billboard shadow must use round geometry without card corners" % path)

func test_sampled_flight_trails_use_compatibility_safe_soft_multimeshes() -> void:
	var trail_cases: Array[Dictionary] = [
		{"scene": preload("res://defense/missile_battery/homing_interceptor.tscn"), "paths": ["SmokeTrail"]},
		{"scene": preload("res://enemy/cruise_missile/cruise_missile.tscn"), "paths": ["Body/ExhaustTrail"]},
		{"scene": preload("res://enemy/strike_aircraft/strike_aircraft.tscn"), "paths": ["Body/LeftExhaustTrail", "Body/RightExhaustTrail"]},
		{"scene": preload("res://effects/air_strike_munition/air_strike_munition.tscn"), "paths": ["SmokeTrail"]},
		{"scene": preload("res://effects/falling_wreck/falling_wreck.tscn"), "paths": ["SmokeTrail"]},
	]
	for trail_case: Dictionary in trail_cases:
		var effect: Node = add_child_autofree((trail_case.scene as PackedScene).instantiate())
		for path: String in trail_case.paths:
			var trail := effect.get_node(path) as LingeringSmokeTrail
			assert_not_null(trail.multimesh, "%s must build a Compatibility-safe multimesh" % path)
			assert_true(trail.multimesh.mesh is QuadMesh, "%s visible puffs must be soft cards" % path)
			var material := (trail.multimesh.mesh as QuadMesh).material as ShaderMaterial
			assert_not_null(material.get_shader_parameter("puff_texture"))
			assert_true(trail.multimesh.use_custom_data)
			assert_eq(material.get_shader_parameter("trail_lifetime"), trail.lifetime)
			assert_eq(trail.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var shadow := trail.get_node("SmokeShadow") as MultiMeshInstance3D
			assert_eq(shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			assert_true(shadow.multimesh.mesh is SphereMesh)
			assert_eq(shadow.multimesh.instance_count, ceili(float(trail.amount) / float(trail.shadow_emission_stride)))
			var shadow_sphere := shadow.multimesh.mesh as SphereMesh
			assert_almost_eq(shadow_sphere.radius, maxf(trail.puff_mesh.size.x, trail.puff_mesh.size.y) * trail.shadow_radius_ratio, 0.001)
			assert_lte(shadow_sphere.radius, maxf(trail.puff_mesh.size.x, trail.puff_mesh.size.y) * 0.35, "%s trail shadow must remain smaller than each visible puff" % path)

func test_missile_trails_share_a_bright_smoke_body_material() -> void:
	var trail_cases: Array[Dictionary] = [
		{"scene": preload("res://defense/missile_battery/homing_interceptor.tscn"), "path": "SmokeTrail"},
		{"scene": preload("res://enemy/cruise_missile/cruise_missile.tscn"), "path": "Body/ExhaustTrail"},
		{"scene": preload("res://effects/air_strike_munition/air_strike_munition.tscn"), "path": "SmokeTrail"},
	]
	for trail_case: Dictionary in trail_cases:
		var effect: Node = add_child_autofree((trail_case.scene as PackedScene).instantiate())
		var trail := effect.get_node(trail_case.path as String) as LingeringSmokeTrail
		var material := trail.smoke_material
		var tint: Color = material.get_shader_parameter("tint")
		assert_gte(tint.r, 0.85)
		assert_gte(tint.g, 0.85)
		assert_gte(tint.b, 0.85)

func test_sampled_smoke_uses_irregular_variation_and_retires_expired_slots() -> void:
	var first_variation := SmokePuffDistribution.sample(1, 0.5)
	var has_position_variation := false
	var has_size_variation := false
	var has_opacity_variation := false
	var has_drift_variation := false
	for serial: int in range(2, 17):
		var variation := SmokePuffDistribution.sample(serial, 0.5)
		has_position_variation = has_position_variation or not variation.offset.is_equal_approx(first_variation.offset)
		has_size_variation = has_size_variation or not is_equal_approx(variation.size_ratio, first_variation.size_ratio)
		has_opacity_variation = has_opacity_variation or not is_equal_approx(variation.opacity_ratio, first_variation.opacity_ratio)
		has_drift_variation = has_drift_variation or not variation.drift_direction.is_equal_approx(first_variation.drift_direction)
	assert_true(has_position_variation)
	assert_true(has_size_variation)
	assert_true(has_opacity_variation)
	assert_true(has_drift_variation)
	var shadow_offsets: Array[int] = []
	for group: int in 10:
		for offset: int in 2:
			if SmokePuffDistribution.casts_shadow(group * 2 + offset + 1, 2):
				shadow_offsets.append(offset)
	assert_ne(shadow_offsets.min(), shadow_offsets.max(), "shadow samples must not form a fixed dark-light cadence")

	var effect := add_child_autofree(preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate()) as FallingWreckEffect
	var trail := effect.get_node("SmokeTrail") as LingeringSmokeTrail
	assert_eq(trail.multimesh.visible_instance_count, 0, "unused GPU smoke slots must not be initialized one by one")
	trail.emitting = true
	trail.sample_world_segment(Vector3.ZERO, Vector3(12.0, 0.0, 0.0))
	assert_gt(trail.active_puff_count(), 8)
	assert_gt(trail.multimesh.visible_instance_count, 0)
	trail._process(trail.lifetime + 0.1)
	assert_eq(trail.active_puff_count(), 0, "expired smoke must leave the per-frame update set")
	assert_eq(trail.multimesh.visible_instance_count, 0)

func test_transient_glows_use_soft_cards_without_realtime_light_shadows() -> void:
	var explosion := add_child_autofree(preload("res://effects/explosion/explosion.tscn").instantiate()) as ExplosionEffect
	for path: String in ["Flash", "FlashHalo", "PressureRing", "Shockwave"]:
		var mesh_instance := explosion.get_node(path) as MeshInstance3D
		assert_true(mesh_instance.mesh is QuadMesh, "%s must not expose a faceted glow mesh" % path)
		var material := mesh_instance.material_override as StandardMaterial3D
		assert_not_null(material.albedo_texture, "%s must have a soft radial mask" % path)
	var fireball := explosion.get_node("Fireball") as GPUParticles3D
	assert_true(fireball.draw_pass_1 is QuadMesh)
	assert_true(((fireball.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_texture == preload("res://effects/glow_card_texture.tres"))
	var explosion_smoke := explosion.get_node("Smoke") as ShadowedSmokeParticles
	var smoke_material := (explosion_smoke.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert_eq(smoke_material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_gte(smoke_material.albedo_color.r, 0.9, "smoke color must not be multiplied dark by both particle and mesh materials")
	assert_false((explosion.get_node("BlastLight") as OmniLight3D).shadow_enabled)
	var miss: Node = add_child_autofree(preload("res://effects/interceptor_miss/interceptor_miss.tscn").instantiate())
	assert_true((miss.get_node("Flash") as MeshInstance3D).mesh is QuadMesh)
	var countermeasure: Node = add_child_autofree(preload("res://effects/countermeasure_burst/countermeasure_burst.tscn").instantiate())
	assert_true((countermeasure.get_node("Flares") as GPUParticles3D).draw_pass_1 is QuadMesh)

func test_explosion_timeline_layers_expand_and_retire_in_order() -> void:
	var initial := ExplosionTimeline.sample(0.0, 10.0)
	var ignition := ExplosionTimeline.sample(0.2, 10.0)
	var pressure_tail := ExplosionTimeline.sample(0.8, 10.0)
	var ended := ExplosionTimeline.sample(ExplosionTimeline.TOTAL_DURATION, 10.0)
	assert_gt(ignition.core_scale, initial.core_scale)
	assert_lt(ignition.core_alpha, initial.core_alpha)
	assert_gt(ignition.pressure_alpha, initial.pressure_alpha)
	assert_gt(pressure_tail.pressure_scale, ignition.pressure_scale)
	assert_lt(pressure_tail.light_energy, ignition.light_energy)
	assert_eq(ended.core_alpha, 0.0)
	assert_eq(ended.halo_alpha, 0.0)
	assert_eq(ended.pressure_alpha, 0.0)
	assert_eq(ended.ground_wave_alpha, 0.0)
	assert_eq(ended.light_energy, 0.0)
	var doubled := ExplosionTimeline.sample(0.2, 20.0)
	assert_almost_eq(doubled.core_scale, ignition.core_scale * 2.0, 0.001)
	assert_almost_eq(doubled.pressure_scale, ignition.pressure_scale * 2.0, 0.001)

func test_energy_effects_retire_independently_and_can_be_replayed() -> void:
	var laser_scene := preload("res://effects/laser_pulse/laser_pulse.tscn")
	var first := add_child_autofree(laser_scene.instantiate()) as LaserPulse
	var second := add_child_autofree(laser_scene.instantiate()) as LaserPulse
	first.setup(Vector3.ZERO, Vector3(30, 12, 0))
	second.setup(Vector3.ZERO, Vector3(0, 20, 50))
	assert_not_same(first.glow_beam.material_override, second.glow_beam.material_override)
	first._process(first.lifetime)
	assert_true(first.is_queued_for_deletion())
	assert_false(second.is_queued_for_deletion())
	assert_gt(second.impact_light.light_energy, 0.0)
	var weapon := add_child_autofree(preload("res://defense/high_power_microwave/high_power_microwave.tscn").instantiate()) as HighPowerMicrowave
	weapon.scale = Vector3.ONE * 0.9
	weapon.pulse_visual.play(40.0)
	assert_true(weapon.pulse_visual.visible)
	weapon.pulse_visual._process(FieldPulse.DURATION)
	assert_false(weapon.pulse_visual.visible)
	assert_almost_eq(weapon.pulse_visual.global_basis.get_scale().x, 4.0, 0.001, "효과 반경은 장비의 표현 축척에 영향받지 않습니다")
	weapon.pulse_visual.play(25.0)
	assert_true(weapon.pulse_visual.visible)

func test_falling_wreck_impact_materials_are_instance_local() -> void:
	var scene := preload("res://effects/falling_wreck/falling_wreck.tscn")
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var first := scene.instantiate() as FallingWreckEffect
	var second := scene.instantiate() as FallingWreckEffect
	parent.add_child(first)
	parent.add_child(second)
	first.setup(Color.RED, Vector3.ZERO, 0.0)
	second.setup(Color.BLUE, Vector3.ZERO, 0.0)
	first._process(0.1)
	second._process(0.1)
	var explosions := parent.find_children("*", "ExplosionEffect", false, false)
	assert_eq(explosions.size(), 2)
	var first_material := (explosions[0] as ExplosionEffect).flash_material
	var second_material := (explosions[1] as ExplosionEffect).flash_material
	assert_ne(first_material, second_material)
	first_material.albedo_color.a = 0.0
	assert_gt(second_material.albedo_color.a, 0.0, "one wreck fade must not mutate another effect instance")

func test_enemy_swept_movement_resolves_at_a_building_surface_and_starts_smoke_there() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	var objective := add_child_autofree(ProtectedObjective.new()) as ProtectedObjective
	objective.global_position = Vector3(0.0, battlefield.terrain_height(0.0, 0.0), 0.0)
	objective.setup(1, SCENARIO.objective_definition)
	var definition := SCENARIO.threat_entries[0].threat_definition as AttackUavDefinition
	var threat := add_child_autofree(definition.scene.instantiate()) as AttackUav
	threat.setup(4001, definition)
	var bounds := battlefield.city_building_bounds(0)
	var target := bounds.get_center()
	threat.global_position = Vector3(bounds.position.x - 8.0, target.y, target.z)
	threat.configure_mission(objective, battlefield, target, 1.0)
	watch_signals(threat)
	threat.gameplay_tick((bounds.size.x + 16.0) / definition.movement.speed)
	assert_true(threat.resolved_state)
	assert_signal_emit_count(threat, "resolved", 1)
	assert_almost_eq(threat.global_position.x, bounds.position.x, 0.001)
	assert_eq(objective.damage_smoke_effects.size(), 1)
	assert_almost_eq(objective.damage_smoke_effects[0].global_position, threat.global_position, Vector3.ONE * 0.001)

func test_strike_and_exit_aircraft_is_not_stopped_by_incidental_city_buildings() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	var objective := add_child_autofree(ProtectedObjective.new()) as ProtectedObjective
	objective.global_position = Vector3(0.0, battlefield.terrain_height(0.0, 0.0), 0.0)
	objective.setup(1, SCENARIO.objective_definition)
	var definition := SCENARIO.threat_entries[3].threat_definition as AttackUavDefinition
	var threat := add_child_autofree(definition.scene.instantiate()) as AttackUav
	threat.setup(4002, definition)
	var bounds := battlefield.city_building_bounds(0)
	var center := bounds.get_center()
	var start := Vector3(bounds.position.x - 12.0, center.y, center.z)
	var target := Vector3(bounds.end.x + 80.0, center.y, center.z)
	threat.global_position = start
	threat.configure_mission(objective, battlefield, target, 1.0, null, target + Vector3.RIGHT * 500.0)
	threat.gameplay_tick(1.0)
	assert_false(threat.resolved_state)
	assert_gt(threat.global_position.x, bounds.position.x)

func test_threat_resolution_can_only_happen_once() -> void:
	var threat: ThreatUnit = autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.neutralization_reward = 30
	threat.setup(7, definition)
	watch_signals(threat)
	assert_true(threat.resolve_once(true))
	assert_false(threat.resolve_once(false))
	assert_signal_emit_count(threat, "resolved", 1)

func test_flare_and_chaff_can_defeat_matching_seekers_with_finite_charges() -> void:
	var threat: ThreatUnit = autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.flare_effectiveness = 0.8
	definition.chaff_effectiveness = 0.4
	definition.countermeasure_charges = 2
	threat.setup(8, definition)
	assert_true(threat.try_defeat_seeker(1.0, 0.0, 0.5))
	assert_false(threat.try_defeat_seeker(0.0, 1.0, 0.5))
	assert_true(threat.try_defeat_seeker(0.0, 1.0, 0.3))
	assert_eq(threat.countermeasure_charges_remaining, 0)
	assert_false(threat.try_defeat_seeker(1.0, 1.0, 0.0))

func test_neutral_contact_does_not_award_budget_or_hostile_statistics() -> void:
	var session := autofree(GameSession.new()) as GameSession
	session.reset(100)
	var contact := autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.affiliation = ThreatDefinition.Affiliation.NEUTRAL
	definition.neutralization_reward = 50
	contact.setup(-1, definition)
	session.register_threat_resolution(contact, true, definition.neutralization_reward)
	assert_eq(session.budget, 100)
	assert_eq(session.neutralized_count, 0)

func test_raid_pacing_rises_gradually_and_stays_bounded() -> void:
	var director: ThreatDirector = autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	assert_eq(director.pressure_level_at(0.0), 1)
	assert_eq(director.pressure_level_at(89.9), 1)
	assert_eq(director.pressure_level_at(90.0), 2)
	assert_eq(director.spawn_interval_at(0.0), 24.0)
	assert_lt(director.spawn_interval_at(450.0), director.spawn_interval_at(0.0))
	assert_gte(director.spawn_interval_at(10000.0), 14.0)
	assert_gt(director.threat_budget_at(240.0), director.threat_budget_at(0.0))
	assert_eq(director.speed_multiplier_at(0.0), 1.0)
	assert_eq(director.speed_multiplier_at(1200.0), 1.6)
	assert_eq(director.speed_multiplier_at(10000.0), 1.6)
	assert_eq(SCENARIO.initial_spawn_interval, 12.0)
	assert_eq(SCENARIO.attack_window_duration, 75.0)
	assert_eq(SCENARIO.recovery_duration, 45.0)
	assert_eq(SCENARIO.raid_archetypes[0].id, &"recon_saturation_strike")
	assert_eq(SCENARIO.raid_archetypes[0].phase_entries.size(), 3)
	assert_eq(SCENARIO.raid_archetypes[0].phase_delays, [0.0, 4.0, 8.0])
	assert_eq(SCENARIO.raid_archetypes[0].total_cost(), 9.0)

func test_running_session_receives_timed_and_attack_window_support() -> void:
	var session := autofree(GameSession.new()) as GameSession
	session.reset(100, 10.0, 25)
	session.defense_count = 1
	assert_true(session.start_defense())
	assert_eq(session.gameplay_delta(9.0), 9.0)
	assert_eq(session.budget, 100)
	session.gameplay_delta(1.0)
	assert_eq(session.budget, 125)
	assert_eq(session.support_payment_count, 1)
	session.grant_attack_window_reward(40)
	assert_eq(session.budget, 165)
	assert_eq(session.completed_attack_windows, 1)
	assert_eq(session.total_support_received, 65)

func test_director_enters_recovery_once_per_attack_window() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	director.enabled = true
	director.until_spawn = 1000.0
	var recovery_count: Array[int] = [0]
	director.recovery_started.connect(func(_window: int) -> void: recovery_count[0] += 1)
	director.gameplay_tick(SCENARIO.attack_window_duration)
	assert_true(director.in_recovery)
	assert_eq(recovery_count[0], 1)
	var paused_spawn_time := director.until_spawn
	director.gameplay_tick(SCENARIO.recovery_duration - 0.1)
	assert_eq(director.until_spawn, paused_spawn_time)
	director.gameplay_tick(0.1)
	assert_false(director.in_recovery)
	assert_eq(recovery_count[0], 1)

func test_advanced_defenses_require_matching_pressure_level() -> void:
	assert_eq(SCENARIO.available_defenses[0].unlock_pressure_level, 1)
	assert_eq(SCENARIO.available_defenses[3].unlock_pressure_level, 2)
	assert_eq(SCENARIO.available_defenses[6].unlock_pressure_level, 3)
	assert_eq(SCENARIO.available_defenses[7].unlock_pressure_level, 4)
	assert_eq(SCENARIO.available_defenses[9].unlock_pressure_level, 5)

func test_close_in_gun_has_distinct_small_target_match_and_short_range() -> void:
	var definition := SCENARIO.available_defenses[4] as CloseInGunDefinition
	var gun: CloseInGun = autofree(definition.scene.instantiate()) as CloseInGun
	gun.setup(1, definition)
	var missile_definition := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	var battery: MissileBattery = autofree(missile_definition.scene.instantiate()) as MissileBattery
	battery.setup(2, missile_definition)
	var small_track := PlayerTrack.new()
	small_track.classification = &"small_uav"
	var larger_track := PlayerTrack.new()
	larger_track.classification = &"uav"
	assert_lt(definition.attack_range, missile_definition.attack_range)
	assert_gt(gun.weapon_match(small_track), gun.weapon_match(larger_track))
	assert_eq(definition.engagement_reservation_kind(), EngagementCoordinator.FIRE_SUPPORT)
	assert_lt(battery.weapon_match(small_track), battery.weapon_match(larger_track))

func test_missile_layers_have_distinct_range_cost_ammunition_and_channels() -> void:
	var medium := SCENARIO.available_defenses[0] as MissileBatteryDefinition
	var long_range := SCENARIO.available_defenses[7] as MissileBatteryDefinition
	var short_range := SCENARIO.available_defenses[8] as MissileBatteryDefinition
	assert_gt(long_range.attack_range, medium.attack_range)
	assert_gt(medium.attack_range, short_range.attack_range)
	assert_gt(long_range.price, medium.price)
	assert_lt(short_range.price, medium.price)
	assert_eq(medium.munitions[0].magazine_capacity, 6)
	assert_eq(short_range.munitions[0].magazine_capacity, 4)
	assert_eq(long_range.munitions[0].magazine_capacity + long_range.munitions[1].magazine_capacity, 4)
	assert_eq(medium.engagement_channels, 6)
	assert_eq(short_range.engagement_channels, 4)
	assert_eq(long_range.engagement_channels, 4)
	assert_eq(medium.launch_interval, 0.56)
	assert_eq(short_range.launch_interval, 0.4)
	assert_eq(long_range.launch_interval, 0.7)
	assert_gt(long_range.maximum_engagement_altitude, medium.maximum_engagement_altitude)
	assert_gt(medium.maximum_engagement_altitude, short_range.maximum_engagement_altitude)
	assert_gt(long_range.minimum_engagement_altitude, short_range.minimum_engagement_altitude)
	assert_gt(short_range.munitions[0].small_target_match, medium.munitions[0].small_target_match)
	assert_eq(long_range.munitions.size(), 2)
	assert_true(long_range.munitions[1].high_cost)
	assert_eq(long_range.munitions[1].magazine_capacity, 2)
	assert_eq(long_range.munitions[1].preferred_classes, [&"ballistic_missile", &"rocket", &"strike_aircraft"])
	assert_ne(long_range.scene.resource_path, medium.scene.resource_path)
	assert_ne(short_range.scene.resource_path, medium.scene.resource_path)
	assert_ne(short_range.scene.resource_path, long_range.scene.resource_path)
	var medium_model := autofree(medium.scene.instantiate()) as MissileBattery
	var long_model := autofree(long_range.scene.instantiate()) as MissileBattery
	var short_model := autofree(short_range.scene.instantiate()) as MissileBattery
	assert_not_null(medium_model.get_node_or_null("Turret/Elevation/Launcher/SixCellRack"))
	assert_not_null(long_model.get_node_or_null("Turret/Elevation/Launcher/FourCanisterBank"))
	assert_not_null(short_model.get_node_or_null("Turret/Elevation/Launcher/QuickReactionCluster"))
	assert_eq(medium_model.get_meta("visual_role"), "medium_six_cell_rack")
	assert_eq(long_model.get_meta("visual_role"), "long_four_canister_bank")
	assert_eq(short_model.get_meta("visual_role"), "short_quick_reaction_cluster")
	var hpm := SCENARIO.available_defenses[9] as HighPowerMicrowaveDefinition
	assert_gt(hpm.effect_radius, 0.0)
	assert_gt(hpm.energy_per_pulse, 0.0)
	var drones := SCENARIO.available_defenses[10] as InterceptorDroneDefenseDefinition
	assert_gt(drones.drone_count, drones.engagement_channels)
	assert_gt(drones.recharge_duration, drones.launch_interval)

func test_threat_definitions_compose_movement_and_mission_profiles() -> void:
	var attack := SCENARIO.threat_entries[0].threat_definition as AttackUavDefinition
	var swarm := SCENARIO.threat_entries[1].threat_definition as AttackUavDefinition
	assert_not_null(attack.movement)
	assert_not_null(attack.mission)
	assert_eq(attack.mission.type, ThreatMissionDefinition.Type.IMPACT)
	assert_eq(attack.mission.target_role, ThreatMissionDefinition.TargetRole.CITY)
	assert_gt(swarm.movement.speed, attack.movement.speed)
	var decoy := SCENARIO.threat_entries[6].threat_definition as AttackUavDefinition
	assert_eq(decoy.id, &"decoy_uav")
	assert_eq(decoy.mission.type, ThreatMissionDefinition.Type.RECONNAISSANCE)
	assert_eq(decoy.mission.damage, 0.0)
	assert_eq(decoy.false_echo_count, 2)
	var jammer := SCENARIO.threat_entries[7].threat_definition as AttackUavDefinition
	assert_eq(jammer.id, &"electronic_warfare_uav")
	assert_gt(jammer.jamming_range, 0.0)
	assert_gt(jammer.jamming_strength, 0.0)
	var anti_radiation := SCENARIO.threat_entries[8].threat_definition as AttackUavDefinition
	assert_eq(anti_radiation.id, &"anti_radiation_missile")
	assert_eq(anti_radiation.mission.target_role, ThreatMissionDefinition.TargetRole.SENSOR)
	assert_eq(SCENARIO.raid_archetypes[1].id, &"deception_sead_strike")
	assert_eq(SCENARIO.raid_archetypes[1].total_cost(), 9.0)
	var ballistic := SCENARIO.threat_entries[9].threat_definition as AttackUavDefinition
	var rockets := SCENARIO.threat_entries[10]
	var aircraft := SCENARIO.threat_entries[11].threat_definition as AttackUavDefinition
	assert_eq(ballistic.movement.mode, ThreatMovementDefinition.Mode.BALLISTIC_ARC)
	assert_gt(ballistic.movement.ballistic_apex, 900.0)
	assert_gte(ballistic.movement.spawn_radius_multiplier, 1.5)
	assert_lt(ballistic.movement.ballistic_boost_fraction, ballistic.movement.ballistic_reentry_fraction)
	assert_lte(ballistic.movement.maximum_speed_multiplier, 1.2)
	assert_eq(rockets.group_size, 4)
	assert_lte((rockets.threat_definition as AttackUavDefinition).movement.maximum_speed_multiplier, 1.2)
	assert_eq(aircraft.mission.type, ThreatMissionDefinition.Type.STRIKE_AND_EXIT)
	assert_gt(aircraft.movement.speed, attack.movement.speed * 3.0)
	assert_gt(aircraft.movement.terminal_altitude, 80.0)
	assert_gt(aircraft.movement.terminal_distance, 500.0)
	assert_eq(SCENARIO.raid_archetypes[2].id, &"mixed_ballistic_air_strike")
	assert_lt(swarm.movement.cruise_altitude, attack.movement.cruise_altitude)
	assert_ne(swarm.movement, attack.movement)
	var cruise := SCENARIO.threat_entries[5].threat_definition as AttackUavDefinition
	assert_eq(cruise.movement.mode, ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING)
	assert_lt(cruise.movement.cruise_altitude, swarm.movement.cruise_altitude)
	assert_gt(cruise.movement.speed, swarm.movement.speed)
	assert_gt(aircraft.movement.cruise_altitude, jammer.movement.cruise_altitude)
	var search_radar := SCENARIO.available_defenses[1] as SearchRadarDefinition
	var high_altitude_radar := SCENARIO.available_defenses[3] as SearchRadarDefinition
	assert_lt(search_radar.maximum_detection_altitude, high_altitude_radar.minimum_detection_altitude + 150.0)
	assert_gt(high_altitude_radar.maximum_detection_altitude, ballistic.movement.ballistic_apex)

func test_recon_and_strike_missions_act_then_egress() -> void:
	var objective: ProtectedObjective = autofree(ProtectedObjective.new()) as ProtectedObjective
	var objective_definition := load("res://world/objective/city/city_objective.tres") as ObjectiveDefinition
	objective.setup(1, objective_definition)
	var support: SupportFacility = add_child_autofree(SupportFacility.new()) as SupportFacility
	support.setup(2, SCENARIO.available_defenses[5])
	support.global_position = Vector3(10.0, 0.0, 0.0)
	var strike_profile := ThreatMissionDefinition.new()
	strike_profile.type = ThreatMissionDefinition.Type.STRIKE_AND_EXIT
	strike_profile.target_role = ThreatMissionDefinition.TargetRole.SUPPORT
	strike_profile.damage = 25.0
	strike_profile.action_distance = 6.0
	var strike := ThreatMissionRuntime.new()
	strike.setup(strike_profile, objective, support.global_position, support, Vector3(100.0, 0.0, 0.0))
	assert_false(strike.gameplay_tick(support.global_position + Vector3.UP * 2.0, 0.1))
	assert_eq(support.integrity, 75.0)
	assert_eq(strike.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_true(strike.gameplay_tick(Vector3(100.0, 2.0, 0.0), 0.1))
	var recon_profile := ThreatMissionDefinition.new()
	recon_profile.type = ThreatMissionDefinition.Type.RECONNAISSANCE
	recon_profile.damage = 0.0
	recon_profile.action_distance = 6.0
	recon_profile.action_duration = 1.0
	var recon := ThreatMissionRuntime.new()
	recon.setup(recon_profile, objective, Vector3.ZERO, null, Vector3(100.0, 0.0, 0.0))
	assert_false(recon.gameplay_tick(Vector3.UP * 2.0, 0.6))
	assert_false(recon.gameplay_tick(Vector3.UP * 2.0, 0.5))
	assert_eq(recon.phase, ThreatMissionRuntime.Phase.EGRESS)
	assert_eq(objective.current_integrity, objective.definition.maximum_integrity)

func test_city_impact_reuses_prepared_emitters_through_repair_and_restore() -> void:
	var objective := add_child_autofree(SCENARIO.objective_definition.scene.instantiate()) as ProtectedObjective
	objective.setup(1, SCENARIO.objective_definition)
	var prepared := objective.prepared_smoke_effects.duplicate()
	assert_eq(prepared.size(), ProtectedObjective.MAX_DAMAGE_SMOKE_SITES)
	var node_count := objective.get_child_count()
	for index: int in 7:
		objective.apply_building_impact(1, Vector3(index * 10, 20, 0), 40)
		assert_true(prepared.has(objective.damage_smoke_effects.back()))
		assert_eq(objective.get_child_count(), node_count, "피격 때 새 연기 노드를 만들지 않습니다")
	var saved := objective.capture_damage_smoke_state()
	objective.restore_integrity(objective.definition.maximum_integrity)
	assert_eq(objective.prepared_smoke_effects.size(), prepared.size())
	objective.restore_damage_smoke_state(saved)
	objective.restore_integrity(90)
	for effect: DamageSmokeEffect in objective.damage_smoke_effects:
		assert_true(prepared.has(effect))
		assert_eq(effect.fire.amount, 32)
		assert_eq(effect.fire.preprocess, 0.0)

func test_explosion_pool_reuses_instances_and_materials_without_reviving_other_effects() -> void:
	var pool := add_child_autofree(CombatEffectPool.new()) as CombatEffectPool
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var first := pool.spawn_explosion(parent, Vector3.ZERO, Color.ORANGE, 8)
	var second := pool.spawn_explosion(parent, Vector3.RIGHT, Color.CYAN, 6)
	var material := first.flash_material
	first._process(first.duration)
	assert_false(first.visible)
	var reused := pool.spawn_explosion(parent, Vector3.UP, Color.WHITE, 10)
	assert_same(first, reused)
	assert_same(material, reused.flash_material)
	assert_eq(reused.elapsed, 0.0)
	assert_true(reused.visible)
	assert_eq(second.flash_material.emission, Color.CYAN)
	assert_eq(pool.available.size(), CombatEffectPool.CAPACITY - 2)

func test_explosion_layers_retire_only_at_zero_and_restart_with_the_same_timeline() -> void:
	var effect := add_child_autofree(preload("res://effects/explosion/explosion.tscn").instantiate()) as ExplosionEffect
	effect.setup(Color.ORANGE, 10)
	for index: int in 150:
		effect._process(0.01)
		var state := ExplosionTimeline.sample(effect.elapsed, 10)
		assert_eq(effect.flash.visible, state.core_alpha > 0.0)
		assert_eq(effect.flash_halo.visible, state.halo_alpha > 0.0)
		assert_eq(effect.pressure_ring.visible, state.pressure_alpha > 0.0)
		assert_eq(effect.shockwave.visible, state.ground_wave_alpha > 0.0)
		assert_eq(effect.blast_light.visible, state.light_energy > 0.0)
		assert_almost_eq(effect.shockwave_material.albedo_color.a, state.ground_wave_alpha, 0.00001)
	assert_true(effect.smoke.emitting)
	assert_true(effect.sparks.emitting)
	assert_true(effect.visible)
	effect.setup(Color.CYAN, 12)
	assert_true(effect.flash.visible)
	assert_true(effect.blast_light.visible)
	assert_false(effect.pressure_ring.visible)
	effect._process(0.1)
	assert_true(effect.pressure_ring.visible)

func test_overflow_explosions_reuse_buffers_without_limiting_simultaneous_effects() -> void:
	var pool := add_child_autofree(CombatEffectPool.new()) as CombatEffectPool
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var effects: Array[ExplosionEffect] = []
	for index: int in CombatEffectPool.RETAINED_CAPACITY + 2:
		effects.append(pool.spawn_explosion(parent, Vector3(index, 0, 0), Color.ORANGE, 8))
		assert_true(effects.back().visible)
	assert_eq(parent.get_child_count(), effects.size())
	assert_eq(pool.retained_count, CombatEffectPool.RETAINED_CAPACITY)
	var overflow := effects[CombatEffectPool.CAPACITY]
	var material := overflow.flash_material
	overflow._process(overflow.duration)
	var reused := pool.spawn_explosion(parent, Vector3.ZERO, Color.WHITE, 10)
	assert_same(reused, overflow)
	assert_same(reused.flash_material, material)
	assert_false(effects.back().reusable)

func test_street_details_rotate_local_length_with_the_road() -> void:
	var details := add_child_autofree(LandscapeDetails.new()) as LandscapeDetails
	for yaw: float in [0.0, PI * 0.5, -PI * 0.5]:
		details._append("car", Vector3.ZERO, Vector3(3.8, 1.2, 1.7), yaw)
	var cars: Array = details._batches["car"]
	for index: int in cars.size():
		var transform: Transform3D = cars[index]
		assert_almost_eq(transform.basis.x.length(), 3.8, 0.001, "차체 긴 축은 회전 후에도 차체 길이를 유지합니다")
		assert_almost_eq(transform.basis.z.length(), 1.7, 0.001)
	var northbound: Vector3 = cars[1].basis.x.normalized()
	assert_almost_eq(absf(northbound.dot(Vector3.FORWARD)), 1.0, 0.001, "남북 도로 차량의 긴 축도 남북을 향합니다")

func test_pause_and_speed_controls_scale_only_running_simulation() -> void:
	var session := autofree(GameSession.new()) as GameSession
	session.reset(400)
	session.defense_count = 1
	assert_true(session.start_defense())
	session.set_simulation_speed(0.0)
	assert_eq(session.gameplay_delta(1.0), 0.0)
	assert_eq(session.survival_time, 0.0)
	session.set_simulation_speed(2.0)
	assert_eq(session.gameplay_delta(1.0), 2.0)
	assert_eq(session.survival_time, 2.0)
	session.set_simulation_speed(4.0)
	assert_eq(session.gameplay_delta(0.5), 2.0)
	assert_eq(session.survival_time, 4.0)
