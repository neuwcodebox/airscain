extends GutTest

const SCENARIO := preload("res://main/first_scenario.tres")
const GLOBAL_FONT_PATH := "res://ui/fonts/NanumSquareB.ttf"

class RecordingCityBoxBatch extends CityBoxBatch:
	var recorded_transforms: Array[Transform3D] = []

	func add_box(pose: Transform3D, material: StandardMaterial3D) -> void:
		recorded_transforms.append(pose)
		super.add_box(pose, material)

var _original_default_font: Font
var _original_fallback_font: Font

func before_each() -> void:
	_original_default_font = ThemeDB.get_default_theme().default_font
	_original_fallback_font = ThemeDB.fallback_font

func after_each() -> void:
	ThemeDB.get_default_theme().default_font = _original_default_font
	ThemeDB.fallback_font = _original_fallback_font

func test_building_occlusion_agrees_with_surface_collision_for_seeded_segments() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 65198
	for index: int in 500:
		var start := Vector3(rng.randf_range(-600, 600), rng.randf_range(-10, 180), rng.randf_range(-600, 600))
		var end := Vector3(rng.randf_range(-600, 600), rng.randf_range(-10, 180), rng.randf_range(-600, 600))
		assert_eq(
			field.building_blocks_segment(start, end),
			not field.building_segment_impact(start, end).is_empty(),
			"seed 65198 segment %d" % index
		)
	var bounds := field.city_building_bounds(0)
	for point: Vector3 in [bounds.position, bounds.end, bounds.get_center()]:
		assert_eq(field.building_blocks_segment(point, point), not field.building_segment_impact(point, point).is_empty())

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
	placement.select(_defense(&"missile_battery"))
	placement.candidate_position = Vector3(100, first.generator.sea_level + 45, 100)
	first.set_placement_contours(true, placement.candidate_position)
	assert_null(placement.preview.find_child("ElevationLabel", true, false))
	assert_eq(material.get_shader_parameter("placement_contours"), true)
	placement.cancel()
	assert_eq(material.get_shader_parameter("placement_contours"), false)

func test_placement_range_color_is_independent_of_model_validity() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.build(SCENARIO)
	var placement := add_child_autofree(PlacementController.new()) as PlacementController
	placement.battlefield = field
	for definition: DefenseDefinition in [_defense(&"missile_battery"), _defense(&"search_radar")]:
		placement.select(definition)
		var material := placement.range_disc.material_override as StandardMaterial3D
		var original_color := material.albedo_color
		for valid: bool in [true, false, true]:
			placement.preview_material.albedo_color = Color.GREEN if valid else Color.RED
			assert_eq(material.albedo_color, original_color, "범위는 배치 모형의 유효성 색상을 공유하지 않는다")
		placement.cancel()
	var overlay := add_child_autofree(C2Overlay.new()) as C2Overlay
	overlay.preview_placement(_defense(&"missile_battery"), Vector3.ZERO, true)
	for ready: bool in [true, false, true]:
		overlay.placement_ready = ready
		overlay._rebuild_range()
		assert_eq(overlay.range_material.albedo_color, C2Overlay.C2_COLOR)

func test_radar_terrain_coverage_splits_work_and_leaves_ridge_shadow_unpainted() -> void:
	var field := _flat_battlefield(80.0, 9)
	for z: int in field.generator.resolution:
		field.generator.heights[z * field.generator.resolution + 4] = 30.0
	var coverage := add_child_autofree(RadarTerrainCoverage.new()) as RadarTerrainCoverage
	coverage.configure(field)
	coverage.maximum_cells_per_frame = 4
	coverage.work_budget_usec = 1000000
	coverage.set_sources([RadarCoverageSource.new("radar", Vector3(-30.0, 0.0, 0.0), 80.0, Color(0.18, 0.82, 1.0, 0.18))])
	coverage._process(0.0)
	assert_true(coverage.is_calculating())
	assert_eq(coverage.completed_source_count(), 0)
	coverage.maximum_cells_per_frame = 10000
	coverage._process(0.0)
	assert_false(coverage.is_calculating())
	assert_eq(coverage.completed_source_count(), 1)
	assert_gt(coverage.coverage_color_at(Vector2(-20.0, 0.0)).a, 0.0)
	assert_eq(coverage.coverage_color_at(Vector2(30.0, 0.0)).a, 0.0)
	var origin := Vector3(-30.0, RadarTerrainCoverage.ANTENNA_HEIGHT, 0.0)
	var shadowed_surface := Vector3(30.0, RadarTerrainCoverage.SURFACE_CLEARANCE, 0.0)
	assert_false(TerrainLineOfSight.is_clear(field, origin, shadowed_surface))

func test_radar_terrain_coverage_invalidates_cache_after_terrain_rebuild() -> void:
	var field := _flat_battlefield(80.0, 9)
	var coverage := add_child_autofree(RadarTerrainCoverage.new()) as RadarTerrainCoverage
	coverage.configure(field)
	coverage.maximum_cells_per_frame = 10000
	coverage.work_budget_usec = 1000000
	var source := RadarCoverageSource.new("radar", Vector3.ZERO, 80.0, Color(0.18, 0.82, 1.0, 0.18))
	coverage.set_sources([source])
	coverage._process(0.0)
	assert_eq(coverage.completed_source_count(), 1)
	field.terrain_revision += 1
	coverage.set_sources([source])
	assert_eq(coverage.completed_source_count(), 0)
	assert_true(coverage.is_calculating())

func test_radar_coverage_targets_follow_preview_overlay_and_selection_priority() -> void:
	var field := _flat_battlefield(80.0, 9)
	var defense_parent := add_child_autofree(Node3D.new()) as Node3D
	var low_radar := _defense(&"search_radar").scene.instantiate() as DefenseUnit
	var high_radar := _defense(&"tracking_radar").scene.instantiate() as DefenseUnit
	defense_parent.add_child(low_radar)
	defense_parent.add_child(high_radar)
	low_radar.setup(1, _defense(&"search_radar"))
	high_radar.setup(2, _defense(&"tracking_radar"))
	var overlay := add_child_autofree(TacticalRangeOverlay.new()) as TacticalRangeOverlay
	overlay.configure(defense_parent, null, null, field)
	overlay.select_asset(low_radar)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 1)
	overlay.set_mode(TacticalRangeOverlay.MODE_SENSOR)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 2)
	overlay.preview_placement(_defense(&"missile_battery"), Vector3.ZERO, true)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 0)
	overlay.preview_placement(_defense(&"tracking_radar"), Vector3.ZERO, true)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 0)
	overlay._process(TacticalRangeOverlay.PLACEMENT_PREVIEW_DELAY)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 1)
	overlay.preview_placement(null, Vector3.ZERO, false)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 2)
	overlay.set_mode(TacticalRangeOverlay.MODE_NONE)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 1)
	overlay.select_asset(null)
	assert_eq(overlay.terrain_coverage.requested_source_count(), 0)
	var low_radar_definition := _defense(&"search_radar")
	assert_eq(low_radar_definition.tactical_overlay_color(), Color(0.18, 0.95, 0.42, 0.72))
	assert_eq(low_radar_definition.terrain_coverage_color(), Color(0.18, 0.82, 1.0, 0.18))
	assert_ne(low_radar_definition.tactical_overlay_color(), _defense(&"tracking_radar").tactical_overlay_color())

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
		var case_label := "seed 27331 segment %d" % trial
		assert_eq(int(actual.get("building_index", -1)), expected_index, case_label)
		if expected_index >= 0:
			assert_almost_eq((actual.position as Vector3).distance_to(expected_position), 0.0, 0.001, case_label)

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
	var original := aircraft.find_child("Airframe", true, false) as MeshInstance3D
	var fallen := wreck.wreck.find_child("Airframe", true, false) as MeshInstance3D
	assert_not_null(fallen)
	assert_same(fallen.mesh, original.mesh, "추락 시 원래 메시를 공유합니다")
	assert_eq(wreck.wreck.basis, aircraft.global_basis)
	assert_ne(fallen.get_active_material(0), original.get_active_material(0))
	assert_lt((fallen.get_active_material(0) as StandardMaterial3D).albedo_color.v, (original.get_active_material(0) as StandardMaterial3D).albedo_color.v)
	assert_null(wreck.wreck.find_child("LeftEngineGlow", true, false))
	assert_eq(wreck.wreck.find_children("*", "Light3D", true, false).size(), 0)
	assert_false(wreck.wreck is ThreatUnit)
	assert_false(wreck.wreck is AttackUav)
	assert_false(_has_property(wreck.wreck, &"registry"), "잔해는 실전 표적 등록 상태를 갖지 않습니다")
	assert_false(wreck.wreck.has_method("gameplay_tick"), "잔해는 전투 비행 동작을 실행하지 않습니다")
	assert_eq(fallen.mesh.get_aabb(), original.mesh.get_aabb(), "날개·수직미익을 포함한 전체 기체 형상을 복제합니다")
	assert_gt(original.mesh.get_aabb().size.x, 15.0)

func test_airframe_geometry_is_shared_but_content_colors_remain_independent() -> void:
	var definition := preload("res://enemy/strike_aircraft/strike_aircraft.tres")
	var first := add_child_autofree(definition.scene.instantiate()) as AttackUav
	var second := add_child_autofree(definition.scene.instantiate()) as AttackUav
	var first_definition := definition.duplicate() as AttackUavDefinition
	var second_definition := definition.duplicate() as AttackUavDefinition
	first_definition.visual_color = Color.RED
	second_definition.visual_color = Color.BLUE
	first.setup(1, first_definition)
	second.setup(2, second_definition)
	for child: Node in first.body.get_children():
		if not child.name.begins_with("Airframe"):
			continue
		var first_mesh := child as MeshInstance3D
		var second_mesh := second.body.get_node(NodePath(child.name)) as MeshInstance3D
		assert_same(first_mesh.mesh, second_mesh.mesh)
		assert_eq((first_mesh.get_active_material(0) as StandardMaterial3D).albedo_color, Color.RED)
		assert_eq((second_mesh.get_active_material(0) as StandardMaterial3D).albedo_color, Color.BLUE)
		assert_ne((first_mesh.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color, Color.RED)

func test_runtime_airframe_paint_survives_the_last_aircraft_leaving() -> void:
	var definition := preload("res://enemy/attack_uav/attack_uav.tres")
	var first := definition.scene.instantiate() as AttackUav
	add_child(first)
	first.setup(1, definition)
	var paint := (first.body.get_node("Airframe") as MeshInstance3D).material_override
	first.free()
	var next := add_child_autofree(definition.scene.instantiate()) as AttackUav
	next.setup(2, definition)
	assert_same((next.body.get_node("Airframe") as MeshInstance3D).material_override, paint, "Runtime material stays alive across empty battlefields")
	assert_false((paint as StandardMaterial3D).vertex_color_use_as_albedo)

func test_content_warmup_uses_runtime_setup_without_joining_combat() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var threat_definition := preload("res://enemy/strike_aircraft/strike_aircraft.tres")
	var defense_definition := preload("res://defense/close_in_gun/close_in_gun.tres")
	var threat := CombatVfxSampleCatalog.create_content_sample(parent, threat_definition) as AttackUav
	var defense := CombatVfxSampleCatalog.create_content_sample(parent, defense_definition) as CloseInGun
	assert_same(threat.definition, threat_definition)
	assert_same(defense.definition, defense_definition)
	assert_not_null(defense.gunfire)
	assert_not_null(defense.prepared_damage_smoke)
	assert_null(defense.registry)
	assert_eq(threat.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(defense.process_mode, Node.PROCESS_MODE_DISABLED)

func test_airframe_palette_preserves_triangles_and_surface_finishes() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var finishes: Array[StandardMaterial3D] = [ModelGeometry.material(Color.RED, 0.2, 0.7), ModelGeometry.material(Color.BLUE, 0.8, 0.3)]
	var parts: Array[MeshInstance3D] = []
	for index: int in finishes.size():
		parts.append(ModelGeometry.box(parent, "Part%d" % index, Vector3.ONE, Vector3(index * 3, 0, 0), finishes[index]))
	var sources := ModelGeometry.combine_static_parts(parts)
	var merged := TintedMeshPalette.combine(sources)
	assert_eq(merged.get_surface_count(), 1)
	var finish := merged.surface_get_material(0) as StandardMaterial3D
	assert_true(finish.vertex_color_use_as_albedo)
	assert_same(finish.metallic_texture, finish.roughness_texture)
	var palette := finish.metallic_texture.get_image()
	var arrays := merged.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var offset := 0
	for slot: int in sources.size():
		var original := sources[slot].surface_get_arrays(0)
		var original_indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
		assert_almost_eq(palette.get_pixel(slot, 0).r, finishes[slot].metallic, 0.00001)
		assert_almost_eq(palette.get_pixel(slot, 0).g, finishes[slot].roughness, 0.00001)
		for index: int in original_indices:
			var merged_index := indices[offset]
			assert_eq(positions[merged_index], original[Mesh.ARRAY_VERTEX][index])
			assert_almost_eq(normals[merged_index], original[Mesh.ARRAY_NORMAL][index], Vector3.ONE * 0.0001)
			assert_almost_eq(uvs[merged_index].x, (slot + 0.5) / sources.size(), 0.0001)
			offset += 1
	assert_eq(indices.size(), offset, "Every original triangle remains in the same winding")

func test_static_detail_batches_share_geometry_and_keep_attachment_transforms() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	parent.position = Vector3(30, 10, -20)
	var marker := Marker3D.new()
	marker.position = Vector3(1, 2, 3)
	parent.add_child(marker)
	var finish := ModelGeometry.material(Color.ORANGE)
	var first := ModelGeometry.box(parent, "One", Vector3(2, 4, 6), Vector3(-5, 0, 0), finish)
	var second := ModelGeometry.box(parent, "Two", Vector3(2, 4, 6), Vector3(5, 0, 0), finish)
	var expected := (first.transform * first.mesh.get_aabb()).merge(second.transform * second.mesh.get_aabb())
	var geometry := ModelGeometry.replace_static_children(parent, [])
	assert_eq(geometry.size(), 1)
	assert_eq(geometry[0].get_aabb(), expected)
	assert_same(geometry[0].surface_get_material(0), finish)
	assert_eq((geometry[0].surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 72, "Both boxes retain all triangles")
	assert_same(marker.get_parent(), parent)
	var duplicate := add_child_autofree(Node3D.new()) as Node3D
	var cached := ModelGeometry.replace_static_children(duplicate, geometry)
	assert_same(cached[0], geometry[0])
	parent.rotate_y(0.5)
	assert_almost_eq(marker.global_position, parent.global_transform * marker.position, Vector3.ONE * 0.00001)
	assert_same((parent.get_node("StaticDetail0") as MeshInstance3D).mesh, geometry[0])

func test_batched_radar_panels_preserve_variants_and_rotate_with_the_antenna() -> void:
	var search_definition := preload("res://sensing/search_radar/search_radar.tres")
	var high_definition := preload("res://sensing/tracking_radar/tracking_radar.tres")
	var search := add_child_autofree(search_definition.scene.instantiate()) as SearchRadar
	var high := add_child_autofree(high_definition.scene.instantiate()) as SearchRadar
	search.setup(11, search_definition)
	high.setup(12, high_definition)
	var search_panel := search.get_node("Antenna/PanelModules/StaticDetail0") as MeshInstance3D
	var high_panel := high.get_node("Antenna/PanelModules/StaticDetail0") as MeshInstance3D
	assert_gt(search_panel.mesh.get_aabb().size.x, high_panel.mesh.get_aabb().size.x)
	var local_transform := search_panel.transform
	var original_basis := search_panel.global_basis
	search.gameplay_tick(0.5)
	assert_eq(search_panel.transform, local_transform)
	assert_ne(search_panel.global_basis, original_basis)
	assert_eq((search.get_node("Details") as Node3D).rotation, Vector3.ZERO)

func test_static_model_merge_preserves_mirrored_winding_normals_and_surface() -> void:
	var part := add_child_autofree(MeshInstance3D.new()) as MeshInstance3D
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	part.mesh = source
	part.material_override = ModelGeometry.material(Color.ORANGE, 0.3, 0.6)
	part.transform = Transform3D(Basis.from_scale(Vector3(-2, 3, 0.5)), Vector3(5, 8, 2))
	var combined := ModelGeometry.combine_static_parts([part])[0]
	assert_same(combined.surface_get_material(0), part.material_override)
	var expected_bounds := part.transform * source.get_aabb()
	assert_almost_eq(combined.get_aabb().position, expected_bounds.position, Vector3.ONE * 0.0001)
	assert_almost_eq(combined.get_aabb().size, expected_bounds.size, Vector3.ONE * 0.0001)
	var result := combined.surface_get_arrays(0)
	var vertices: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = result[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = result[Mesh.ARRAY_INDEX]
	assert_eq(indices.size(), 3, "삼각형을 줄이거나 추가하지 않습니다")
	var face_normal := (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]]).normalized()
	for normal: Vector3 in normals:
		assert_almost_eq(normal, Vector3.BACK, Vector3.ONE * 0.0001)
		assert_gt(face_normal.dot(normal), 0.99, "거울 복제된 날개도 같은 앞면과 명암을 유지합니다")

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
	assert_eq(first.city_districts().size(), second.city_districts().size())
	assert_eq(first.city_districts()[0].id, second.city_districts()[0].id)
	assert_eq(first.city_districts()[0].blocks, second.city_districts()[0].blocks)
	assert_eq(first.city_districts()[0].buildings, second.city_districts()[0].buildings)

func test_ocean_uses_a_smoothed_copy_of_the_gameplay_heightfield() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	var material := battlefield.ocean.mesh.surface_get_material(0) as ShaderMaterial
	var ocean_heights := material.get_shader_parameter("terrain_heights") as Texture2D
	var expected_size := battlefield.generator.resolution * Battlefield.OCEAN_HEIGHT_TEXTURE_SCALE
	assert_eq(ocean_heights.get_width(), expected_size)
	assert_eq(ocean_heights.get_height(), expected_size)
	assert_eq(battlefield.generator.heights.size(), battlefield.generator.resolution ** 2, "게임 판정 높이장은 원래 해상도를 유지합니다")

func test_current_city_is_an_explicit_central_district() -> void:
	var generator := WorldGenerator.new()
	generator.generate(SCENARIO.world_seed, SCENARIO.battlefield_size, SCENARIO.terrain_resolution, SCENARIO.city_size, SCENARIO.battlefield_layout())
	var districts := generator.city_districts()
	assert_eq(districts.size(), 1)
	var district := districts[0]
	assert_eq(district.id, WorldGenerator.CENTRAL_DISTRICT_ID)
	assert_lt(district.center.length(), SCENARIO.city_size * 0.65)
	assert_ne(district.center, SCENARIO.battlefield_layout().city_districts[0].center)
	assert_eq(district.blocks, generator.city_block_layout())
	assert_eq(district.buildings, generator.building_transforms())
	assert_true(district.has_buildings())

func test_multiple_authored_districts_own_rotated_blocks_and_buildings() -> void:
	var core := CityDistrictDefinition.new()
	core.id = &"west_core"
	core.center = Vector2(-210.0, -40.0)
	core.rotation_degrees = -18.0
	core.size = 250.0
	core.block_count = 7
	core.minimum_building_height = 12.0
	core.maximum_building_height = 72.0
	var satellite := CityDistrictDefinition.new()
	satellite.id = &"east_satellite"
	satellite.role = CityDistrictDefinition.Role.RESIDENTIAL
	satellite.center = Vector2(225.0, 85.0)
	satellite.rotation_degrees = 27.0
	satellite.size = 220.0
	satellite.block_count = 7
	satellite.minimum_building_height = 7.0
	satellite.maximum_building_height = 32.0
	var layout := BattlefieldLayoutDefinition.new()
	layout.id = &"district_fixture"
	layout.display_name = "복수 지구 fixture"
	layout.summary = "복수 지구 생성 검증용 레이아웃입니다."
	layout.preview = SCENARIO.battlefield_layouts[0].preview
	layout.city_districts = [core, satellite]
	assert_eq(layout.validation_error(), "")
	var generator := WorldGenerator.new()
	generator.generate(44021, 1400.0, 57, 480.0, layout)
	var districts := generator.city_districts()
	assert_eq(districts.size(), 2)
	assert_eq(districts[0].id, core.id)
	assert_eq(districts[1].id, satellite.id)
	for district: CityDistrict in districts:
		assert_false(district.blocks.is_empty(), String(district.id))
		assert_false(district.buildings.is_empty(), String(district.id))
		for block: Dictionary in district.blocks:
			assert_eq(StringName(block.district_id), district.id)
			assert_almost_eq(generator.height_at(block.position.x, block.position.z), WorldGenerator.CITY_GROUND_HEIGHT, 0.25)
		var district_rotation := Basis(Vector3.UP, deg_to_rad(district.definition.rotation_degrees))
		var expected_right := district_rotation * Vector3.RIGHT
		var expected_back := district_rotation * Vector3.BACK
		for building: Transform3D in district.buildings:
			assert_almost_eq(building.basis.x.normalized().dot(expected_right), 1.0, 0.0001, "%s right axis" % district.id)
			assert_almost_eq(building.basis.z.normalized().dot(expected_back), 1.0, 0.0001, "%s back axis" % district.id)
	assert_gt(districts[0].center.distance_to(districts[1].center), 400.0)

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

func test_city_batches_preserve_each_box_surface_bounds_and_locality() -> void:
	var batch := CityBoxBatch.new()
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("aa9274")
	material.roughness = 0.85
	var poses: Array[Transform3D] = []
	for index: int in 24:
		var pose := Transform3D(Basis(Vector3.UP, index * 0.1).scaled(Vector3(8, 20, 12)), Vector3(index * 30 - 360, 40, 10))
		poses.append(pose)
		batch.add_box(pose, material.duplicate())
	batch.build(parent)
	assert_lt(parent.get_child_count(), poses.size(), "동일 표면의 인접 건물을 함께 렌더합니다")
	var instance_count := 0
	var batch_bounds: Array[AABB] = []
	for child: MultiMeshInstance3D in parent.get_children():
		var surface := child.material_override as StandardMaterial3D
		assert_eq(surface.albedo_color, material.albedo_color)
		assert_eq(surface.roughness, material.roughness)
		assert_eq(child.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		var instances := child.multimesh
		instance_count += instances.instance_count
		batch_bounds.append(instances.custom_aabb)
		assert_lt(instances.custom_aabb.size.x, 160.0, "국소 조명과 컬링을 위해 멀리 떨어진 건물을 묶지 않습니다")
	assert_eq(instance_count, poses.size())
	for pose: Transform3D in poses:
		var found := false
		var bounds := pose * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
		for candidate: AABB in batch_bounds:
			found = found or candidate.grow(0.001).encloses(bounds)
		assert_true(found, "회전·크기를 포함한 원래 형상이 컬링 경계 안에 있습니다")
	var count := parent.get_child_count()
	batch.build(parent)
	assert_eq(parent.get_child_count(), count, "이미 빌드한 형상을 중복 생성하지 않습니다")

func test_city_building_targets_use_seeded_ranges_and_segments_hit_the_first_surface() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	assert_eq(battlefield.city_buildings.size(), battlefield.generator.building_transforms().size())
	assert_eq(battlefield.city_districts.size(), 1)
	assert_eq(battlefield.city_districts[0].buildings, battlefield.city_buildings)
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 90817
	second_rng.seed = 90817
	var first_target := Vector3.ZERO
	var last_target := Vector3.ZERO
	for sample: int in 24:
		var target := battlefield.random_city_building_target(first_rng)
		var case_label := "seed 90817 sample %d" % sample
		assert_eq(target, battlefield.random_city_building_target(second_rng), case_label)
		var contained := false
		for index: int in battlefield.city_buildings.size():
			if battlefield.city_building_bounds(index).has_point(target):
				contained = true
				break
		assert_true(contained, case_label)
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

func test_city_building_target_is_selected_through_its_district() -> void:
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(SCENARIO)
	var district_rng := RandomNumberGenerator.new()
	var target_rng := RandomNumberGenerator.new()
	district_rng.seed = 11473
	target_rng.seed = 11473
	var district := battlefield.random_city_district(district_rng)
	assert_not_null(district)
	assert_eq(district.id, WorldGenerator.CENTRAL_DISTRICT_ID)
	assert_eq(
		battlefield.random_city_building_target_in_district(district, district_rng),
		battlefield.random_city_building_target(target_rng)
	)

func test_city_objective_uses_a_civic_landmark() -> void:
	var city := add_child_autofree(preload("res://world/objective/city/city_objective.tscn").instantiate()) as CityObjective
	assert_not_null(city.get_node_or_null("CivicHall"))
	assert_not_null(city.get_node_or_null("CivicTower"))
	var roof := city.get_node("CivicRoof") as MeshInstance3D
	var mount := city.get_node("CommandMount") as Marker3D
	assert_almost_eq(mount.position.y, roof.position.y + (roof.mesh as BoxMesh).size.y * 0.5, 0.001)
	city.rotation.y = deg_to_rad(37.0)
	assert_almost_eq(float(city.initial_defense_mounts()[0].rotation_y), city.global_rotation.y, 0.0001, "옥상 설치점은 시민청 방향을 제공합니다")
	var hall := city.get_node("CivicHall") as MeshInstance3D
	var rotated_inside := hall.global_transform * Vector3(16.0, 0.0, 11.0)
	var world_axis_corner := hall.global_position + Vector3(16.0, 0.0, 11.0)
	assert_true(city.excludes_placement(rotated_inside, 0.0), "회전한 시민청 내부를 배치 금지합니다")
	assert_false(city.excludes_placement(world_axis_corner, 0.0), "월드 축 사각형을 시민청 점유 영역으로 오인하지 않습니다")

func test_city_objective_width_follows_each_primary_block() -> void:
	for seed_value: int in 4:
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.world_seed = seed_value
		var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
		battlefield.build(scenario)
		var city := add_child_autofree(preload("res://world/objective/city/city_objective.tscn").instantiate()) as CityObjective
		battlefield.align_primary_city_objective(city)
		var hall := city.get_node("CivicHall") as MeshInstance3D
		var hall_width := (hall.mesh as BoxMesh).size.x * hall.global_basis.get_scale().x
		var expected_width := battlefield.primary_city_block_size() - CityObjective.BLOCK_MARGIN
		assert_almost_eq(hall_width, expected_width, 0.001, "seed %d 시민청 폭" % seed_value)
		assert_lt(hall_width, battlefield.primary_city_block_size(), "seed %d 시민청은 블록 안에 있습니다" % seed_value)
		assert_almost_eq(city.scale.y, 1.0, 0.0001, "seed %d 시민청 높이는 바꾸지 않습니다" % seed_value)

func test_tactical_units_use_a_smaller_presentation_scale_without_changing_profiles() -> void:
	var defense := add_child_autofree(_defense(&"missile_battery").scene.instantiate()) as DefenseUnit
	defense.setup(1, _defense(&"missile_battery"))
	var threat := add_child_autofree(_threat(&"attack_uav").scene.instantiate()) as ThreatUnit
	threat.setup(1, _threat(&"attack_uav"))
	assert_eq(defense.scale, Vector3.ONE * DefenseUnit.PRESENTATION_SCALE)
	assert_eq(threat.scale, Vector3.ONE * ThreatUnit.PRESENTATION_SCALE)
	assert_eq(defense.definition.placement_profile.footprint_radius, _defense(&"missile_battery").placement_profile.footprint_radius)
	assert_eq(threat.definition.radar_signature, _threat(&"attack_uav").radar_signature)

func test_every_friendly_installation_exposes_a_fixed_size_role_icon() -> void:
	assert_eq(_defense(&"search_radar").display_name, "저·중고도 레이더")
	assert_eq(_defense(&"tracking_radar").display_name, "고고도 레이더")
	var role_icons: Dictionary = {}
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		var case_label := "defense %s" % definition.id
		var defense := add_child_autofree(definition.scene.instantiate()) as DefenseUnit
		defense.setup(1, definition)
		assert_not_null(defense.identity_marker, "%s identity marker" % case_label)
		assert_true(defense.identity_marker.visible, "%s marker visibility" % case_label)
		var icon := defense.identity_marker.get_node("Icon") as Sprite3D
		assert_true(icon.fixed_size, "%s fixed-size icon" % case_label)
		assert_true(icon.no_depth_test, "%s icon depth" % case_label)
		assert_gte(icon.render_priority, 100, "%s icon priority" % case_label)
		assert_not_null(icon.texture, "%s icon texture" % case_label)
		assert_same(icon.texture, definition.identity_icon, "%s authored icon" % case_label)
		assert_true(icon.texture.resource_path.ends_with(".svg"), "%s vector icon" % case_label)
		assert_eq(defense.identity_marker.position, defense.status_marker.position, "%s 상태 표식은 같은 기준점에서 화면 기준 간격을 유지합니다" % case_label)
		role_icons[icon.texture.resource_path] = true
	assert_eq(role_icons.size(), SCENARIO.available_defenses.size(), "각 자산 종류의 아이콘을 구분할 수 있습니다")

func test_friendly_installation_selection_highlights_icon_and_footprint() -> void:
	var defense := add_child_autofree(_defense(&"missile_battery").scene.instantiate()) as DefenseUnit
	defense.setup(1, _defense(&"missile_battery"))
	var icon := defense.identity_marker.get_node("Icon") as Sprite3D
	var selection_ring := defense.identity_marker.get_node("SelectionRing") as MeshInstance3D
	assert_false(selection_ring.visible)
	var texture := icon.texture
	defense.set_selected(true)
	assert_true(selection_ring.visible)
	assert_same(icon.texture, texture)
	assert_eq(icon.scale, Vector3.ONE * 1.2)
	assert_eq((selection_ring.mesh as TorusMesh).rings, 64)
	defense.set_selected(false)
	assert_false(selection_ring.visible)
	assert_eq(icon.scale, Vector3.ONE)

func test_reload_marker_tracks_magazine_not_burst_cooldown() -> void:
	var definition := _defense(&"close_in_gun")
	var gun := add_child_autofree(definition.scene.instantiate()) as CloseInGun
	gun.setup(1, definition)
	var background := gun.identity_marker.get_node("ReloadBackground") as Sprite3D
	var fill := gun.identity_marker.get_node("ReloadFill") as Sprite3D
	gun.cooldown = 0.1
	gun._process(0.0)
	assert_false(background.visible, "연사 대기에는 재장전 막대가 없습니다")
	while gun.magazine.can_fire():
		gun.magazine.consume()
	gun._process(0.0)
	assert_true(background.visible)
	assert_false(fill.visible)
	gun.magazine.gameplay_tick(gun.magazine.reload_duration * 0.5)
	gun._process(0.0)
	assert_true(fill.visible)
	assert_gt(fill.region_rect.size.x, 0.0)
	assert_lt(fill.region_rect.size.x, float(background.texture.get_width()))
	assert_true(fill.fixed_size and fill.no_depth_test)
	assert_true(gun.selection_status_rows().any(func(row: Dictionary) -> bool: return row.label == "재장전"))
	gun.magazine.gameplay_tick(gun.magazine.reload_duration)
	gun._process(0.0)
	assert_false(background.visible)
	gun.magazine.reserve = 0
	while gun.magazine.can_fire():
		gun.magazine.consume()
	gun._process(0.0)
	assert_false(background.visible, "탄약 고갈은 재장전이 아닙니다")

func test_multiple_munition_reload_marker_uses_next_completion() -> void:
	var definition := _defense(&"long_range_missile")
	var battery := add_child_autofree(definition.scene.instantiate()) as MissileBattery
	battery.setup(1, definition)
	assert_eq(battery.magazines.size(), 2)
	for magazine: WeaponMagazine in battery.magazines.values():
		while magazine.can_fire():
			magazine.consume()
	var first := battery.magazines[&"area_defense"] as WeaponMagazine
	var second := battery.magazines[&"high_speed_interceptor"] as WeaponMagazine
	first.reload_remaining = 3.0
	second.reload_remaining = 1.0
	assert_same(battery.reload_display_magazine(), second)
	second.gameplay_tick(1.0)
	assert_same(battery.reload_display_magazine(), first)
	first.gameplay_tick(3.0)
	assert_null(battery.reload_display_magazine())

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

func test_explicit_battlefield_layout_overrides_seed_selection_and_validates_id() -> void:
	var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	scenario.selected_battlefield_layout_id = &"coastal_plain"
	assert_eq(scenario.battlefield_layout().id, &"coastal_plain")
	scenario.world_seed += 1
	assert_eq(scenario.battlefield_layout().id, &"coastal_plain")
	assert_eq(scenario.battlefield_layout_by_id(&"valley_corridor").display_name, "계곡 도시 회랑")
	scenario.selected_battlefield_layout_id = &"missing"
	assert_eq(scenario.validation_error(), "선택한 전장 레이아웃을 찾을 수 없습니다")

func test_battlefield_layout_requires_selection_summary_and_preview() -> void:
	var layout := SCENARIO.battlefield_layouts[0].duplicate(true) as BattlefieldLayoutDefinition
	layout.summary = ""
	assert_eq(layout.validation_error(), "전장 선택 화면용 설명 또는 미리보기가 없습니다")
	layout.summary = "전장 설명"
	layout.preview = null
	assert_eq(layout.validation_error(), "전장 선택 화면용 설명 또는 미리보기가 없습니다")

func test_scenario_exposes_distinct_island_bay_valley_and_coastal_plain_worlds() -> void:
	var expected_ids: Array[StringName] = [&"rugged_harbor", &"island_city", &"valley_corridor", &"coastal_plain"]
	var expected_district_counts: Array[int] = [2, 1, 3, 3]
	for index: int in expected_ids.size():
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.world_seed = index
		var selected := scenario.battlefield_layout()
		assert_eq(selected.id, expected_ids[index])
		var generator := WorldGenerator.new()
		generator.generate(scenario.world_seed, scenario.battlefield_size, scenario.terrain_resolution, scenario.city_size, selected)
		assert_eq(generator.city_districts().size(), expected_district_counts[index], String(expected_ids[index]))
		assert_eq(generator.primary_city_center(), generator.city_districts()[0].center)
		if generator.city_districts().size() > 1:
			var centers: Array[Vector2] = []
			for district: CityDistrict in generator.city_districts():
				centers.append(district.center)
			assert_gt(centers[0].distance_to(centers.back()), 300.0, String(expected_ids[index]))

func test_non_island_terrain_shapes_keep_their_macro_topology_inside_organic_coasts() -> void:
	var bay_scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	bay_scenario.world_seed = 0
	var bay := WorldGenerator.new()
	bay.generate(0, bay_scenario.battlefield_size, bay_scenario.terrain_resolution, bay_scenario.city_size, bay_scenario.battlefield_layout())
	var bay_rotation := Basis(Vector3.UP, deg_to_rad(bay.terrain_rotation_degrees))
	var inlet := bay_rotation * Vector3(bay.size * 0.34, 0.0, 0.0)
	var inland := bay_rotation * Vector3(-bay.size * 0.25, 0.0, 0.0)
	assert_lt(bay.height_at(inlet.x, inlet.z), bay.sea_level)
	assert_gt(bay.height_at(inland.x, inland.z), bay.sea_level)
	var valley_scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	valley_scenario.world_seed = 2
	var valley := WorldGenerator.new()
	valley.generate(2, valley_scenario.battlefield_size, valley_scenario.terrain_resolution, valley_scenario.city_size, valley_scenario.battlefield_layout())
	var valley_rotation := Basis(Vector3.UP, deg_to_rad(valley.terrain_rotation_degrees))
	var west_wall := valley_rotation * Vector3(-700.0, 0.0, 0.0)
	var east_wall := valley_rotation * Vector3(700.0, 0.0, 0.0)
	assert_gt(valley.height_at(west_wall.x, west_wall.z), valley.height_at(0.0, 0.0) + 25.0)
	assert_gt(valley.height_at(east_wall.x, east_wall.z), valley.height_at(0.0, 0.0) + 25.0)
	var coast_scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	coast_scenario.world_seed = 3
	var coast := WorldGenerator.new()
	coast.generate(3, coast_scenario.battlefield_size, coast_scenario.terrain_resolution, coast_scenario.city_size, coast_scenario.battlefield_layout())
	var coast_rotation := Basis(Vector3.UP, deg_to_rad(coast.terrain_rotation_degrees))
	var sea_side := coast_rotation * Vector3(1050.0, 0.0, 0.0)
	var land_side := coast_rotation * Vector3(-1050.0, 0.0, 0.0)
	assert_lt(coast.height_at(sea_side.x, sea_side.z), coast.sea_level)
	assert_gt(coast.height_at(land_side.x, land_side.z), coast.sea_level)

func test_seed_procedurally_varies_district_sites_sizes_and_macro_rotation() -> void:
	var first_scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	first_scenario.world_seed = 3
	var second_scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	second_scenario.world_seed = 7
	assert_eq(first_scenario.battlefield_layout().id, second_scenario.battlefield_layout().id)
	var first := WorldGenerator.new()
	var second := WorldGenerator.new()
	first.generate(first_scenario.world_seed, first_scenario.battlefield_size, first_scenario.terrain_resolution, first_scenario.city_size, first_scenario.battlefield_layout())
	second.generate(second_scenario.world_seed, second_scenario.battlefield_size, second_scenario.terrain_resolution, second_scenario.city_size, second_scenario.battlefield_layout())
	assert_ne(first.terrain_rotation_degrees, second.terrain_rotation_degrees)
	for district_index: int in first.city_districts().size():
		var first_definition := first.city_districts()[district_index].definition
		var second_definition := second.city_districts()[district_index].definition
		assert_ne(first_definition.center, second_definition.center, String(first_definition.id))
		assert_ne(first_definition.rotation_degrees, second_definition.rotation_degrees, String(first_definition.id))
		assert_ne(first_definition.size, second_definition.size, String(first_definition.id))

func test_every_terrain_shape_submerges_the_full_mesh_perimeter() -> void:
	for layout_index: int in SCENARIO.battlefield_layouts.size():
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.world_seed = layout_index
		var generator := WorldGenerator.new()
		generator.generate(scenario.world_seed, scenario.battlefield_size, scenario.terrain_resolution, scenario.city_size, scenario.battlefield_layout())
		var edge := scenario.battlefield_size * 0.5
		for position: Vector2 in [Vector2(edge, 0.0), Vector2(-edge, 0.0), Vector2(0.0, edge), Vector2(0.0, -edge)]:
			assert_lt(generator.height_at(position.x, position.y), generator.sea_level, "%s %s" % [scenario.battlefield_layout().id, position])

func test_procedural_district_sites_remain_playable_across_seed_variants() -> void:
	for seed_value: int in 12:
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.world_seed = seed_value
		var generator := WorldGenerator.new()
		generator.generate(scenario.world_seed, scenario.battlefield_size, scenario.terrain_resolution, scenario.city_size, scenario.battlefield_layout())
		var districts := generator.city_districts()
		for district: CityDistrict in districts:
			assert_false(district.blocks.is_empty(), "%d %s blocks" % [seed_value, district.id])
			assert_false(district.buildings.is_empty(), "%d %s buildings" % [seed_value, district.id])
			assert_gt(generator.height_at(district.center.x, district.center.y), generator.sea_level, "%d %s center" % [seed_value, district.id])
			if districts.size() > 1:
				assert_gt(district.definition.size, 310.0, "%d %s size" % [seed_value, district.id])
		for first_index: int in districts.size():
			for second_index: int in range(first_index + 1, districts.size()):
				var first := districts[first_index]
				var second := districts[second_index]
				var minimum_separation := (first.definition.size + second.definition.size) * 0.38
				assert_gt(first.center.distance_to(second.center), minimum_separation, "%d %s/%s separation" % [seed_value, first.id, second.id])

func test_every_battlefield_layout_keeps_rooftop_placement_sites() -> void:
	for layout_index: int in SCENARIO.battlefield_layouts.size():
		var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
		scenario.world_seed = layout_index
		var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
		battlefield.build(scenario)
		assert_false(battlefield.rooftop_pads.is_empty(), String(scenario.battlefield_layout().id))

func test_rotated_city_amenities_and_lamps_stay_on_their_district_blocks() -> void:
	var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	scenario.world_seed = 3
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	var city_boxes := RecordingCityBoxBatch.new()
	battlefield._city_boxes = city_boxes
	battlefield.build(scenario)
	var box_transforms := city_boxes.recorded_transforms
	var checked_park := false
	for block: Dictionary in battlefield.generator.city_block_layout():
		var grid: Vector2i = block.grid
		if grid != Vector2i.ZERO and (grid.x + grid.y) % 2 != 0:
			continue
		var block_center: Vector3 = block.position
		var block_step: float = block.block_step
		var has_building := battlefield.city_buildings.any(func(building: Transform3D) -> bool:
			return Vector2(building.origin.x - block_center.x, building.origin.z - block_center.z).length() <= block_step * 0.42
		)
		if has_building:
			continue
		var park_position := Vector3(block_center.x, battlefield.terrain_height(block_center.x, block_center.z) + 0.58, block_center.z)
		var park_transform := _city_box_at(box_transforms, park_position)
		assert_lt(float(park_transform.distance), 0.01, "회전 검사용 공원 바닥을 찾습니다")
		var expected_right := Basis(Vector3.UP, float(block.rotation)) * Vector3.RIGHT
		assert_almost_eq((park_transform.pose as Transform3D).basis.x.normalized().dot(expected_right), 1.0, 0.0001, "공원 바닥은 지구 축을 따릅니다")
		checked_park = true
		break
	assert_true(checked_park, "회전 검사용 공원이 생성됩니다")
	var first_block: Dictionary = battlefield.generator.city_block_layout()[0]
	var lamp := battlefield.city_visuals.get_node("Lamp0") as MeshInstance3D
	var lamp_right := Basis(Vector3.UP, float(first_block.rotation)) * Vector3.RIGHT
	assert_almost_eq(lamp.transform.basis.x.normalized().dot(lamp_right), 1.0, 0.0001, "가로등 등기구는 지구 축을 따릅니다")
	var lamp_delta := lamp.position - (first_block.position as Vector3)
	var lamp_local := Basis(Vector3.UP, float(first_block.rotation)).inverse() * Vector3(lamp_delta.x, 0.0, lamp_delta.z)
	var lamp_block_half_extent := (float(first_block.block_step) - battlefield.city_road_width) * 0.5
	assert_lte(absf(lamp_local.x), lamp_block_half_extent, "가로등은 x축 도로가 아니라 보도 안에 있습니다")
	assert_lte(absf(lamp_local.z), lamp_block_half_extent, "가로등은 z축 도로가 아니라 보도 안에 있습니다")

func test_rotated_city_building_footprints_cover_world_space_bounds() -> void:
	var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	scenario.world_seed = 2
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(scenario)
	for index: int in battlefield.city_buildings.size():
		var bounds := battlefield.city_building_bounds(index)
		var footprint := battlefield.city_building_footprints[index]
		assert_true(footprint.has_point(Vector2(bounds.position.x, bounds.position.z)), "building %d minimum" % index)
		assert_true(footprint.has_point(Vector2(bounds.end.x, bounds.end.z)), "building %d maximum" % index)

func _city_box_at(transforms: Array[Transform3D], position: Vector3) -> Dictionary:
	var closest := Transform3D.IDENTITY
	var closest_distance := INF
	for pose: Transform3D in transforms:
		var distance := pose.origin.distance_to(position)
		if distance < closest_distance:
			closest = pose
			closest_distance = distance
	return {"pose": closest, "distance": closest_distance}

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

func test_objective_damage_is_bounded_and_depletion_emits_once() -> void:
	var objective := _test_objective()
	watch_signals(objective)
	var first_impact := Vector3(12.0, 30.0, -5.0)
	assert_true(objective.apply_building_impact(10, first_impact, 48.0))
	assert_eq(objective.current_integrity, 90)
	assert_eq(objective.damage_smoke_effects.size(), 1)
	assert_eq(objective.damage_smoke_effects[0].global_position, first_impact)
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

func test_city_damage_smoke_uses_bounded_authored_particle_profile() -> void:
	var objective := _test_objective()
	var first_impact := Vector3(12.0, 30.0, -5.0)
	assert_true(objective.apply_building_impact(10, first_impact, 48.0))
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

func test_objective_repair_reduces_smoke_to_the_integrity_band() -> void:
	var objective := _test_objective()
	for index: int in 4:
		assert_true(objective.apply_building_impact(25, Vector3(index * 10.0, 20.0, 0.0), 30.0))
	assert_eq(objective.damage_smoke_effects.size(), 4)
	objective.restore_integrity(75)
	assert_eq(objective.current_integrity, 75)
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
		var scene := smoke_case.scene as PackedScene
		var effect: Node = add_child_autofree(scene.instantiate())
		for path: String in smoke_case.paths:
			var case_label := "%s:%s" % [scene.resource_path, path]
			var particles := effect.get_node(path) as GPUParticles3D
			assert_eq(particles.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s visible pass must not cast thresholded shadows" % case_label)
			var mesh := particles.draw_pass_1 as Mesh
			assert_true(mesh is QuadMesh, "%s visible smoke must use a soft radial card" % case_label)
			var material := mesh.surface_get_material(0) as StandardMaterial3D
			assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "%s must blend smoothly without Compatibility depth-prepass centers" % case_label)
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL, "%s must interact with scene lighting" % case_label)
			var shadow := particles.get_node("SmokeShadow") as GPUParticles3D
			assert_eq(shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s GPU shadow proxy must render in Compatibility" % case_label)
			assert_eq(shadow.process_material, particles.process_material, "%s shadow motion must match visible smoke" % case_label)
			var shadow_mesh := shadow.draw_pass_1 as Mesh
			var shadow_material := shadow_mesh.surface_get_material(0) as ShaderMaterial
			assert_not_null(shadow_material, "%s shadow opacity must use the shadow-pass shader" % case_label)
			if shadow_material == null:
				continue
			assert_eq(shadow_material.shader.resource_path, "res://effects/smoke_shadow.gdshader", "%s shadow shader" % case_label)
			assert_true(shadow_material.shader.code.contains("!IN_SHADOW_PASS"), "%s proxy must discard its camera color pass" % case_label)
			assert_false(shadow_material.shader.code.contains("ALPHA_HASH_SCALE"), "%s shadow must remain a solid surface instead of a pixel hash" % case_label)
			assert_true(shadow_material.shader.code.contains("VERTEX *= sqrt"), "%s shadow fade must contract the solid particle silhouette" % case_label)
			if mesh is QuadMesh:
				assert_true(shadow_mesh is SphereMesh, "%s billboard shadow must use round geometry without card corners" % case_label)

func test_sampled_flight_trails_use_compatibility_safe_soft_multimeshes() -> void:
	var trail_cases: Array[Dictionary] = [
		{"scene": preload("res://defense/missile_battery/homing_interceptor.tscn"), "paths": ["SmokeTrail"]},
		{"scene": preload("res://enemy/cruise_missile/cruise_missile.tscn"), "paths": ["Body/ExhaustTrail"]},
		{"scene": preload("res://enemy/strike_aircraft/strike_aircraft.tscn"), "paths": ["Body/LeftExhaustTrail", "Body/RightExhaustTrail"]},
		{"scene": preload("res://effects/air_strike_munition/air_strike_munition.tscn"), "paths": ["SmokeTrail"]},
		{"scene": preload("res://effects/falling_wreck/falling_wreck.tscn"), "paths": ["SmokeTrail"]},
	]
	for trail_case: Dictionary in trail_cases:
		var scene := trail_case.scene as PackedScene
		var effect: Node = add_child_autofree(scene.instantiate())
		for path: String in trail_case.paths:
			var case_label := "%s:%s" % [scene.resource_path, path]
			var trail := effect.get_node(path) as LingeringSmokeTrail
			assert_not_null(trail.multimesh, "%s must build a Compatibility-safe multimesh" % case_label)
			assert_true(trail.multimesh.mesh is QuadMesh, "%s visible puffs must be soft cards" % case_label)
			var material := (trail.multimesh.mesh as QuadMesh).material as ShaderMaterial
			assert_not_null(material.get_shader_parameter("puff_texture"), "%s puff texture" % case_label)
			assert_true(trail.multimesh.use_custom_data, "%s custom data" % case_label)
			assert_eq(material.get_shader_parameter("trail_lifetime"), trail.lifetime, "%s lifetime" % case_label)
			assert_eq(material.get_shader_parameter("trail_turbulence_strength"), trail.turbulence_strength, "%s visible turbulence" % case_label)
			assert_eq(trail.shadow_material.get_shader_parameter("trail_turbulence_strength"), trail.turbulence_strength, "%s shadow turbulence" % case_label)
			assert_eq(trail.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s visible shadow mode" % case_label)
			var shadow := trail.get_node("SmokeShadow") as MultiMeshInstance3D
			assert_eq(shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s shadow proxy mode" % case_label)
			assert_eq(shadow.layers, SmokeShadowFactory.SMOKE_LAYER, "%s shadow layer" % case_label)
			assert_true(shadow.multimesh.mesh is SphereMesh, "%s shadow geometry" % case_label)
			assert_eq(shadow.multimesh.instance_count, ceili(float(trail.amount) / float(trail.shadow_emission_stride)), "%s shadow capacity" % case_label)
			var shadow_sphere := shadow.multimesh.mesh as SphereMesh
			assert_almost_eq(shadow_sphere.radius, maxf(trail.puff_mesh.size.x, trail.puff_mesh.size.y) * trail.shadow_radius_ratio, 0.001, "%s shadow radius" % case_label)
			assert_lte(shadow_sphere.radius, maxf(trail.puff_mesh.size.x, trail.puff_mesh.size.y) * 0.35, "%s trail shadow must remain smaller than each visible puff" % case_label)

func test_fast_interceptor_smoke_samples_the_full_frame_path_without_gaps() -> void:
	var interceptor := add_child_autofree(preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate()) as HomingInterceptor
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	var long_range := _defense(&"long_range_missile") as MissileBatteryDefinition
	var high_speed := _munition(long_range, &"high_speed_interceptor")
	var representative_frame_seconds := 0.05
	var travel_distance := high_speed.interceptor_speed * representative_frame_seconds
	var expected_samples := floori(travel_distance / smoke.sample_spacing) * smoke.particles_per_sample
	smoke.sample_world_segment(Vector3.ZERO, Vector3.FORWARD * travel_distance)
	assert_gt(expected_samples, 1, "대표 고속 이동은 복수 연기 표본이 필요한 거리입니다")
	assert_gte(smoke.active_puff_count(), expected_samples, "이동 거리와 scene sample_spacing이 요구하는 모든 표본이 활성화됩니다")
	assert_gte(smoke.emitted_sample_count, expected_samples, "프레임 사이 경로를 양끝만으로 대체하지 않습니다")
	assert_lte(smoke.last_emitted_world_position.distance_to(Vector3.FORWARD * travel_distance), smoke.sample_spacing + 0.001, "마지막 표본과 프레임 끝의 간격도 scene 간격 안입니다")
	assert_lte(smoke.sample_spacing, maxf(smoke.puff_mesh.size.x, smoke.puff_mesh.size.y), "인접 표본의 가시 카드가 끊어지지 않습니다")

func test_interceptor_smoke_capacity_retains_its_expected_flight_and_drifts() -> void:
	var interceptor := add_child_autofree(preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate()) as HomingInterceptor
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	var expected_path_length := interceptor.speed * interceptor.maximum_lifetime
	var expected_flight_samples := floori(expected_path_length / smoke.sample_spacing) * smoke.particles_per_sample
	assert_gte(smoke.amount, expected_flight_samples, "scene이 선언한 최대 비행 동안 초기 표본을 덮어쓰지 않습니다")
	assert_gt(smoke.lifetime, interceptor.maximum_lifetime, "첫 비행 표본은 요격탄 비행이 끝난 뒤에도 남습니다")
	assert_gt(smoke.drift_speed, 0.0, "잔류 연기는 정지하지 않고 완만하게 이동합니다")
	assert_gt(smoke.final_scale, smoke.initial_scale, "잔류 연기는 수명 동안 완만하게 퍼집니다")

func test_interceptor_propulsion_uses_visible_emission_and_a_finite_light() -> void:
	var interceptor := add_child_autofree(preload("res://defense/missile_battery/homing_interceptor.tscn").instantiate()) as HomingInterceptor
	var flame := interceptor.get_node("Trail") as MeshInstance3D
	var flame_material := flame.material_override as StandardMaterial3D
	var flame_light := interceptor.get_node("FlameLight") as OmniLight3D
	assert_true(flame.visible, "요격탄 추진 화염 메시가 비행 표본에서 보입니다")
	assert_true(flame_material.emission_enabled, "추진 화염은 emissive 재질을 사용합니다")
	assert_true(is_finite(flame_material.emission_energy_multiplier))
	assert_gt(flame_material.emission_energy_multiplier, 0.0)
	assert_true(flame_light.visible, "요격탄 추진 광원이 비행 표본에서 보입니다")
	assert_true(is_finite(flame_light.light_energy))
	assert_gt(flame_light.light_energy, 0.0, "추진 광원은 양의 에너지를 가집니다")
	assert_true(is_finite(flame_light.omni_range))
	assert_gt(flame_light.omni_range, 0.0, "추진 광원의 범위는 유한한 양수입니다")

func test_missile_trails_share_a_bright_smoke_body_material() -> void:
	var trail_cases: Array[Dictionary] = [
		{"scene": preload("res://defense/missile_battery/homing_interceptor.tscn"), "path": "SmokeTrail"},
		{"scene": preload("res://enemy/cruise_missile/cruise_missile.tscn"), "path": "Body/ExhaustTrail"},
		{"scene": preload("res://effects/air_strike_munition/air_strike_munition.tscn"), "path": "SmokeTrail"},
	]
	for trail_case: Dictionary in trail_cases:
		var scene := trail_case.scene as PackedScene
		var case_label := "%s:%s" % [scene.resource_path, trail_case.path]
		var effect: Node = add_child_autofree(scene.instantiate())
		var trail := effect.get_node(trail_case.path as String) as LingeringSmokeTrail
		var material := trail.smoke_material
		var tint: Color = material.get_shader_parameter("tint")
		assert_gte(tint.r, 0.85, "%s red tint" % case_label)
		assert_gte(tint.g, 0.85, "%s green tint" % case_label)
		assert_gte(tint.b, 0.85, "%s blue tint" % case_label)

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

func test_transparent_trails_retire_gpu_work_and_resume_emission() -> void:
	var effect := add_child_autofree(preload("res://effects/falling_wreck/falling_wreck.tscn").instantiate()) as FallingWreckEffect
	var trail := effect.get_node("SmokeTrail") as LingeringSmokeTrail
	trail.emitting = true
	trail.sample_world_segment(Vector3.ZERO, Vector3(12, 0, 0))
	var count := trail.active_puff_count()
	var fade_end: float = trail.smoke_material.get_shader_parameter("trail_fade_end")
	assert_eq(trail.shadow_material.get_shader_parameter("trail_fade_end"), fade_end)
	trail._process(trail.lifetime * fade_end - 0.1)
	assert_eq(trail.active_puff_count(), count, "No puff retires while its shader can still produce alpha")
	trail._process(0.11)
	assert_eq(trail.active_puff_count(), 0)
	assert_eq(trail.multimesh.visible_instance_count, 0)
	assert_eq(trail.shadow_particles.multimesh.visible_instance_count, 0)
	trail.sample_world_segment(Vector3(12, 0, 0), Vector3(24, 0, 0))
	assert_gt(trail.active_puff_count(), 0)
	assert_gt(trail.multimesh.visible_instance_count, 0)
	assert_gt(trail.shadow_particles.multimesh.visible_instance_count, 0)

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
	assert_true((countermeasure.get_node("Flares") as MultiMeshInstance3D).multimesh.mesh is QuadMesh)

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

func test_laser_effects_retire_independently() -> void:
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

func test_laser_effect_stays_visible_when_sustained_and_flickers() -> void:
	var laser_scene := preload("res://effects/laser_pulse/laser_pulse.tscn")
	var effect := add_child_autofree(laser_scene.instantiate()) as LaserPulse
	effect.setup(Vector3.ZERO, Vector3(0.0, 20.0, 0.0))
	var initial_width := effect.beam.scale.x
	effect._process(effect.lifetime * 0.6)
	assert_ne(effect.beam.scale.x, initial_width, "지속광의 굵기는 미세하게 흔들립니다")
	effect.sustain(Vector3(5.0, 0.0, 0.0), Vector3(5.0, 35.0, 0.0))
	effect._process(effect.lifetime * 0.6)
	assert_false(effect.is_queued_for_deletion(), "조사를 갱신하면 기존 빔이 유지됩니다")
	assert_almost_eq(effect.global_position, Vector3(5.0, 17.5, 0.0), Vector3.ONE * 0.001)
	assert_almost_eq(effect.beam.scale.y, 35.0, 0.001)
	effect.stop()
	effect._process(effect.lifetime)
	assert_true(effect.is_queued_for_deletion(), "조사 중단 뒤에는 짧게 감쇠하고 사라집니다")

func test_field_pulse_can_be_replayed_at_world_scale() -> void:
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
	var definition := _threat(&"attack_uav") as AttackUavDefinition
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
	var definition := _threat(&"support_strike_uav") as AttackUavDefinition
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
	threat.gameplay_tick(1.0)
	assert_false(threat.try_defeat_seeker(0.0, 1.0, 0.5))
	assert_true(threat.try_defeat_seeker(0.0, 1.0, 0.3))
	assert_eq(threat.countermeasure_charges_remaining, 0)
	threat.gameplay_tick(1.0)
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

func test_pressure_waits_for_the_opening_raid_and_advances_at_fixed_steps() -> void:
	var director: ThreatDirector = autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	assert_eq(director.pressure_level_at(0.0), 1)
	assert_eq(director.pressure_level_at(10000.0), 1, "첫 공습 전 대기 시간은 단계를 올리지 않는다")
	director.opening_raid_started = true
	director.opening_raid_complete = true
	director.pressure_started_at = 200.0
	var pressure_step := SCENARIO.pressure_step_duration
	assert_eq(director.pressure_level_at(199.9), 1)
	assert_eq(director.pressure_level_at(200.0), 2)
	assert_eq(director.pressure_level_at(200.0 + pressure_step - 0.1), 2)
	assert_eq(director.pressure_level_at(200.0 + pressure_step), 3)

func test_raid_interval_and_budget_scale_with_pressure_but_remain_bounded() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	director.opening_raid_started = true
	assert_eq(director.automatic_raid_interval_at(0.0), 30.0)
	director.opening_raid_complete = true
	director.pressure_started_at = 200.0
	assert_eq(director.spawn_interval_at(0.0), 24.0)
	assert_lt(director.spawn_interval_at(450.0), director.spawn_interval_at(0.0))
	assert_gte(director.spawn_interval_at(10000.0), 14.0)
	assert_gt(director.threat_budget_at(240.0), director.threat_budget_at(0.0))

func test_threat_speed_growth_caps_at_the_scenario_maximum() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	assert_eq(director.speed_multiplier_at(0.0), 1.0)
	assert_eq(director.speed_multiplier_at(1200.0), 1.6)
	assert_eq(director.speed_multiplier_at(10000.0), 1.6)

func test_scenario_attack_window_and_initial_spawn_timing_are_authored() -> void:
	assert_eq(SCENARIO.initial_spawn_interval, 12.0)
	assert_eq(SCENARIO.opening_raid_interval, 30.0)
	assert_eq(SCENARIO.attack_window_duration, 75.0)
	assert_eq(SCENARIO.recovery_duration, 45.0)

func test_scenario_raid_archetypes_define_recon_sead_and_ballistic_strikes() -> void:
	var recon := _raid_archetype(&"recon_saturation_strike")
	assert_eq(recon.phase_entries.size(), 3)
	assert_eq(recon.phase_delays, [0.0, 4.0, 8.0])
	assert_eq(recon.total_cost(), 9.0)
	assert_eq(_raid_archetype(&"deception_sead_strike").total_cost(), 9.0)
	assert_not_null(_raid_archetype(&"mixed_ballistic_air_strike"))

func test_city_raid_shares_one_district_target_and_spawns_from_that_district() -> void:
	var scenario := SCENARIO.duplicate(true) as ScenarioDefinition
	scenario.world_seed = 2
	var battlefield := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	battlefield.build(scenario)
	var objective := add_child_autofree(scenario.objective_definition.scene.instantiate()) as ProtectedObjective
	var primary_center := battlefield.generator.primary_city_center()
	objective.global_position = Vector3(primary_center.x, battlefield.terrain_height(primary_center.x, primary_center.y), primary_center.y)
	objective.setup(1, scenario.objective_definition)
	battlefield.set_objective(objective)
	var threat_parent := add_child_autofree(Node3D.new()) as Node3D
	var defense_parent := add_child_autofree(Node3D.new()) as Node3D
	var enemy_knowledge := add_child_autofree(EnemyKnowledge.new()) as EnemyKnowledge
	var director := add_child_autofree(ThreatDirector.new()) as ThreatDirector
	var registry := ThreatRegistry.new()
	director.configure(scenario, battlefield, objective, registry, threat_parent, defense_parent, enemy_knowledge)
	var archetype: RaidArchetypeDefinition
	for candidate: RaidArchetypeDefinition in scenario.raid_archetypes:
		if candidate.id == &"recon_saturation_strike":
			archetype = candidate
			break
	assert_not_null(archetype)
	director.schedule_archetype(archetype, 0.75)
	var district_ids: Dictionary[StringName, bool] = {}
	for wave: Dictionary in director.pending_waves:
		var entry: ThreatSpawnEntry
		for candidate: ThreatSpawnEntry in scenario.threat_entries:
			if candidate.threat_definition.id == StringName(String(wave.definition_id)):
				entry = candidate
				break
		if entry != null and entry.threat_definition.shares_city_impact_target():
			district_ids[StringName(String(wave.target_district_id))] = true
	assert_eq(district_ids.size(), 1)
	var district := battlefield.city_district_by_id(district_ids.keys()[0])
	assert_not_null(district)
	director._tick_pending_waves(4.0)
	var city_threats: Array[AttackUav] = []
	for threat: ThreatUnit in registry.get_hostile_active():
		if threat.definition.id == &"swarm_uav":
			city_threats.append(threat as AttackUav)
	assert_eq(city_threats.size(), 4)
	var shared_target := city_threats[0].target_point
	for threat: AttackUav in city_threats:
		assert_eq(threat.target_point, shared_target)
		var spawn_distance := Vector2(threat.global_position.x, threat.global_position.z).distance_to(district.center)
		var expected_radius := scenario.battlefield_size * threat.definition.spawn_radius_multiplier()
		assert_gt(spawn_distance, expected_radius - 12.0)
		assert_lt(spawn_distance, expected_radius + 1.0)
	assert_lt(Vector2(shared_target.x, shared_target.z).distance_to(district.center), district.definition.size)

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
	director.opening_raid_started = true
	director.opening_raid_complete = true
	director.pressure_started_at = 0.0
	director.pressure_level = 2
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
	assert_eq(_defense(&"missile_battery").unlock_pressure_level, 1)
	assert_eq(_defense(&"tracking_radar").unlock_pressure_level, 2)
	assert_eq(_defense(&"high_energy_laser").unlock_pressure_level, 3)
	assert_eq(_defense(&"long_range_missile").unlock_pressure_level, 4)
	assert_eq(_defense(&"high_power_microwave").unlock_pressure_level, 5)

func test_close_in_gun_has_distinct_small_target_match_and_short_range() -> void:
	var definition := _defense(&"close_in_gun") as CloseInGunDefinition
	var gun: CloseInGun = autofree(definition.scene.instantiate()) as CloseInGun
	gun.setup(1, definition)
	var missile_definition := _defense(&"missile_battery") as MissileBatteryDefinition
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

func test_missile_layers_have_distinct_range_price_and_altitude() -> void:
	var medium := _defense(&"missile_battery") as MissileBatteryDefinition
	var long_range := _defense(&"long_range_missile") as MissileBatteryDefinition
	var short_range := _defense(&"short_range_missile") as MissileBatteryDefinition
	assert_gt(long_range.attack_range, medium.attack_range)
	assert_gt(medium.attack_range, short_range.attack_range)
	assert_gt(long_range.price, medium.price)
	assert_lt(short_range.price, medium.price)
	assert_gt(long_range.maximum_engagement_altitude, medium.maximum_engagement_altitude)
	assert_gt(medium.maximum_engagement_altitude, short_range.maximum_engagement_altitude)
	assert_gt(long_range.minimum_engagement_altitude, short_range.minimum_engagement_altitude)

func test_missile_layers_have_distinct_capacity_channels_and_cadence() -> void:
	var medium := _defense(&"missile_battery") as MissileBatteryDefinition
	var long_range := _defense(&"long_range_missile") as MissileBatteryDefinition
	var short_range := _defense(&"short_range_missile") as MissileBatteryDefinition
	var medium_standard := _munition(medium, &"standard")
	var short_quick_reaction := _munition(short_range, &"quick_reaction")
	var long_area_defense := _munition(long_range, &"area_defense")
	var long_high_speed := _munition(long_range, &"high_speed_interceptor")
	assert_eq(medium_standard.magazine_capacity, 6)
	assert_eq(short_quick_reaction.magazine_capacity, 4)
	assert_eq(long_area_defense.magazine_capacity + long_high_speed.magazine_capacity, 4)
	assert_eq(medium.engagement_channels, 6)
	assert_eq(short_range.engagement_channels, 4)
	assert_eq(short_range.maximum_interceptors_per_track, 1)
	assert_gt(short_quick_reaction.interceptor_speed, medium_standard.interceptor_speed)
	assert_gt(short_quick_reaction.proximity_radius, medium_standard.proximity_radius)
	assert_eq(long_range.engagement_channels, 4)
	assert_eq(medium.launch_interval, 0.56)
	assert_eq(short_range.launch_interval, 0.4)
	assert_eq(long_range.launch_interval, 0.7)
	assert_eq(long_range.munitions.size(), 2)

func test_missile_munitions_have_distinct_small_and_high_cost_preferences() -> void:
	var medium := _defense(&"missile_battery") as MissileBatteryDefinition
	var long_range := _defense(&"long_range_missile") as MissileBatteryDefinition
	var short_range := _defense(&"short_range_missile") as MissileBatteryDefinition
	var medium_standard := _munition(medium, &"standard")
	var short_quick_reaction := _munition(short_range, &"quick_reaction")
	var long_high_speed := _munition(long_range, &"high_speed_interceptor")
	assert_gt(short_quick_reaction.small_target_match, medium_standard.small_target_match)
	assert_true(long_high_speed.high_cost)
	assert_eq(long_high_speed.magazine_capacity, 2)
	assert_eq(long_high_speed.preferred_classes, [&"ballistic_missile", &"rocket", &"strike_aircraft"])

func test_missile_layer_scenes_expose_distinct_visual_roles() -> void:
	var medium := _defense(&"missile_battery") as MissileBatteryDefinition
	var long_range := _defense(&"long_range_missile") as MissileBatteryDefinition
	var short_range := _defense(&"short_range_missile") as MissileBatteryDefinition
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

func test_hpm_definition_has_valid_area_and_energy_cost() -> void:
	var hpm := _defense(&"high_power_microwave") as HighPowerMicrowaveDefinition
	assert_gt(hpm.effect_radius, 0.0)
	assert_gt(hpm.energy_per_pulse, 0.0)

func test_interceptor_drone_capacity_exceeds_channels_and_recharge_interval() -> void:
	var drones := _defense(&"interceptor_drone_defense") as InterceptorDroneDefenseDefinition
	var medium := _defense(&"missile_battery") as MissileBatteryDefinition
	assert_gt(drones.drone_count, drones.engagement_channels)
	assert_gt(drones.recharge_duration, drones.launch_interval)
	assert_gt(drones.attack_range, medium.attack_range)
	assert_lt(drones.maximum_target_speed, drones.drone_speed)
	assert_lt(drones.small_target_match, drones.missile_target_match)
	assert_lt(drones.missile_target_match, 1.0)

func test_impact_threats_compose_distinct_movement_and_mission_profiles() -> void:
	var attack := _threat(&"attack_uav") as AttackUavDefinition
	var swarm := _threat(&"swarm_uav") as AttackUavDefinition
	assert_not_null(attack.movement)
	assert_not_null(attack.mission)
	assert_eq(attack.mission.type, ThreatMissionDefinition.Type.IMPACT)
	assert_eq(attack.mission.target_role, ThreatMissionDefinition.TargetRole.CITY)
	assert_gt(swarm.movement.speed, attack.movement.speed)
	assert_lt(swarm.movement.cruise_altitude, attack.movement.cruise_altitude)
	assert_ne(swarm.movement, attack.movement)
	var cruise := _threat(&"cruise_missile") as AttackUavDefinition
	assert_eq(cruise.movement.mode, ThreatMovementDefinition.Mode.TERRAIN_FOLLOWING)
	assert_lt(cruise.movement.cruise_altitude, swarm.movement.cruise_altitude)
	assert_gt(cruise.movement.speed, swarm.movement.speed)
	var aircraft := _threat(&"strike_aircraft") as AttackUavDefinition
	assert_eq(aircraft.mission.type, ThreatMissionDefinition.Type.STRIKE_AND_EXIT)
	assert_gt(aircraft.movement.speed, attack.movement.speed * 3.0)
	assert_gt(aircraft.movement.terminal_altitude, 80.0)
	assert_gt(aircraft.movement.terminal_distance, 500.0)
	var jammer := _threat(&"electronic_warfare_uav") as AttackUavDefinition
	assert_gt(aircraft.movement.cruise_altitude, jammer.movement.cruise_altitude)

func test_specialized_threats_define_recon_jamming_and_suppression_roles() -> void:
	var decoy := _threat(&"decoy_uav") as AttackUavDefinition
	assert_eq(decoy.id, &"decoy_uav")
	assert_eq(decoy.mission.type, ThreatMissionDefinition.Type.RECONNAISSANCE)
	assert_eq(decoy.mission.damage, 0.0)
	assert_eq(decoy.false_echo_count, 2)
	var jammer := _threat(&"electronic_warfare_uav") as AttackUavDefinition
	assert_eq(jammer.id, &"electronic_warfare_uav")
	assert_gt(jammer.jamming_range, 0.0)
	assert_gt(jammer.jamming_strength, 0.0)
	var anti_radiation := _threat(&"anti_radiation_missile") as AttackUavDefinition
	assert_eq(anti_radiation.id, &"anti_radiation_missile")
	assert_eq(anti_radiation.mission.target_role, ThreatMissionDefinition.TargetRole.SENSOR)
	var support_strike := _threat(&"support_strike_uav") as AttackUavDefinition
	assert_true(support_strike.requires_role_knowledge)
	assert_eq(support_strike.adaptive_knowledge_role, &"support")

func test_enemy_names_identify_target_then_attack_form() -> void:
	var expected: Dictionary = {
		&"attack_uav": "도시 자폭 UAV",
		&"swarm_uav": "도시 자폭 소형 UAV",
		&"defense_strike_uav": "방공무장 자폭 UAV",
		&"small_defense_strike_uav": "방공무장 자폭 소형 UAV",
		&"weapon_saturation_uav": "방공무장 포화 소형 UAV",
		&"radar_saturation_uav": "레이더 포화 소형 UAV",
		&"battery_strike_uav": "방공무장 폭격 UAV",
		&"support_strike_uav": "지원시설 폭격 UAV",
		&"cruise_missile": "도시 타격 순항미사일",
		&"battery_strike_cruise": "방공무장 타격 순항미사일",
		&"support_strike_cruise": "지원시설 타격 순항미사일",
		&"anti_radiation_missile": "레이더 타격 미사일",
		&"strike_aircraft": "도시 타격기",
		&"battery_strike_aircraft": "방공무장 타격기",
		&"radar_strike_aircraft": "레이더 타격기",
		&"ballistic_missile": "도시 타격 탄도미사일",
		&"rocket": "도시 타격 로켓",
	}
	for id: StringName in expected:
		assert_eq(_threat(id).display_name, expected[id], String(id))

func test_asset_strikes_meet_visible_damage_floor() -> void:
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		var definition := entry.threat_definition as AttackUavDefinition
		if definition == null or definition.mission == null or definition.mission.type == ThreatMissionDefinition.Type.RECONNAISSANCE or definition.mission.target_role == ThreatMissionDefinition.TargetRole.CITY:
			continue
		assert_gte(definition.mission.damage, ThreatMissionDefinition.MINIMUM_ASSET_STRIKE_DAMAGE, String(definition.id))
		assert_eq(definition.validation_error(), "", String(definition.id))
	var underpowered := ThreatMissionDefinition.new()
	underpowered.target_role = ThreatMissionDefinition.TargetRole.WEAPON
	underpowered.damage = ThreatMissionDefinition.MINIMUM_ASSET_STRIKE_DAMAGE - 1.0
	assert_string_contains(underpowered.validation_error(), "손상 표시 기준")

func test_anti_radiation_direct_hit_disables_but_does_not_destroy_radar() -> void:
	var anti_radiation := _threat(&"anti_radiation_missile") as AttackUavDefinition
	var radar_definition := _defense(&"search_radar") as SearchRadarDefinition
	var radar := add_child_autofree(radar_definition.scene.instantiate()) as SearchRadar
	radar.setup(711, radar_definition)
	var mission := ThreatMissionRuntime.new()
	mission.setup(anti_radiation.mission, null, radar.global_position, radar, Vector3.ZERO)
	assert_eq(anti_radiation.mission.damage, 70.0)
	assert_true(mission.gameplay_tick(radar.global_position, 0.1))
	assert_false(radar.active)
	assert_eq(radar.integrity, 30.0, "직격 후에도 지원시설이 수리할 내구도가 남습니다")

func test_ballistic_and_rocket_threats_match_high_altitude_detection_envelope() -> void:
	var ballistic := _threat(&"ballistic_missile") as AttackUavDefinition
	var rockets := _threat_entry(&"rocket")
	assert_eq(ballistic.movement.mode, ThreatMovementDefinition.Mode.BALLISTIC_ARC)
	assert_gt(ballistic.movement.ballistic_apex, 900.0)
	assert_gte(ballistic.movement.spawn_radius_multiplier, 1.5)
	assert_lt(ballistic.movement.ballistic_boost_fraction, ballistic.movement.ballistic_reentry_fraction)
	assert_lte(ballistic.movement.maximum_speed_multiplier, 1.2)
	assert_eq(rockets.group_size, 4)
	assert_lte((rockets.threat_definition as AttackUavDefinition).movement.maximum_speed_multiplier, 1.2)
	var search_radar := _defense(&"search_radar") as SearchRadarDefinition
	var high_altitude_radar := _defense(&"tracking_radar") as SearchRadarDefinition
	assert_eq(search_radar.tracking_capacity, 12)
	assert_eq(high_altitude_radar.tracking_capacity, 20)
	assert_lt(search_radar.maximum_detection_altitude, high_altitude_radar.minimum_detection_altitude + 150.0)
	assert_gt(high_altitude_radar.maximum_detection_altitude, ballistic.movement.ballistic_apex)

func test_recon_and_strike_missions_act_then_egress() -> void:
	var objective: ProtectedObjective = autofree(ProtectedObjective.new()) as ProtectedObjective
	var objective_definition := load("res://world/objective/city/city_objective.tres") as ObjectiveDefinition
	objective.setup(1, objective_definition)
	var support: SupportFacility = add_child_autofree(SupportFacility.new()) as SupportFacility
	support.setup(2, _defense(&"support_facility"))
	support.global_position = Vector3(10.0, 0.0, 0.0)
	var strike_profile := ThreatMissionDefinition.new()
	strike_profile.type = ThreatMissionDefinition.Type.STRIKE_AND_EXIT
	strike_profile.target_role = ThreatMissionDefinition.TargetRole.SUPPORT
	strike_profile.damage = 25.0
	strike_profile.action_distance = 6.0
	var strike := ThreatMissionRuntime.new()
	strike.setup(strike_profile, objective, support.global_position, support, Vector3(100.0, 0.0, 0.0))
	assert_false(strike.gameplay_tick(support.global_position + Vector3.UP * 2.0, 0.1))
	assert_eq(support.integrity, 100.0, "임무는 투발만 확정하고 피해는 비행 중 탄이 처리합니다")
	assert_true(strike.effect_applied)
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
		var case_label := "explosion frame %d elapsed %.2f" % [index, effect.elapsed]
		assert_eq(effect.flash.visible, state.core_alpha > 0.0, "%s core" % case_label)
		assert_eq(effect.flash_halo.visible, state.halo_alpha > 0.0, "%s halo" % case_label)
		assert_eq(effect.pressure_ring.visible, state.pressure_alpha > 0.0, "%s pressure" % case_label)
		assert_eq(effect.shockwave.visible, state.ground_wave_alpha > 0.0, "%s ground wave" % case_label)
		assert_eq(effect.blast_light.visible, state.light_energy > 0.0, "%s light" % case_label)
		assert_almost_eq(effect.shockwave_material.albedo_color.a, state.ground_wave_alpha, 0.00001, "%s alpha" % case_label)
	assert_true(effect.smoke.emitting)
	assert_true(effect.sparks.emitting)
	assert_true(effect.visible)
	effect.setup(Color.CYAN, 12)
	assert_true(effect.flash.visible)
	assert_true(effect.blast_light.visible)
	assert_false(effect.pressure_ring.visible)
	effect._process(0.1)
	assert_true(effect.pressure_ring.visible)

func test_prepared_explosion_budget_reuses_buffers_without_limiting_overflow() -> void:
	var pool := add_child_autofree(CombatEffectPool.new()) as CombatEffectPool
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var effects: Array[ExplosionEffect] = []
	var prepared := pool.available.duplicate()
	for effect: ExplosionEffect in prepared:
		assert_false(effect.visible)
		assert_false(effect.is_processing())
	for index: int in CombatEffectPool.CAPACITY + 2:
		effects.append(pool.spawn_explosion(parent, Vector3(index, 0, 0), Color.ORANGE, 8))
		assert_true(effects.back().visible)
		if index < CombatEffectPool.CAPACITY:
			assert_true(prepared.has(effects.back()), "The entire retained budget exists before the first salvo")
	assert_eq(parent.get_child_count(), effects.size())
	var retained := effects[CombatEffectPool.CAPACITY - 1]
	var material := retained.flash_material
	retained._process(retained.duration)
	var reused := pool.spawn_explosion(parent, Vector3.ZERO, Color.WHITE, 10)
	assert_same(reused, retained)
	assert_same(reused.flash_material, material)
	assert_false(effects.back().reusable)

func test_city_smoke_configuration_is_stable_across_reactivation() -> void:
	var effect := add_child_autofree(preload("res://effects/damage_smoke/damage_smoke.tscn").instantiate()) as DamageSmokeEffect
	effect.set_city_scale(1.5, 45)
	var smoke_scale := effect.smoke.scale
	var fire_scale := effect.fire.scale
	var lifetime := effect.smoke.lifetime
	effect.set_damage_ratio(0.2)
	effect.deactivate()
	effect.set_city_scale(1.5, 45)
	assert_eq(effect.smoke.scale, smoke_scale)
	assert_eq(effect.fire.scale, fire_scale)
	assert_eq(effect.smoke.lifetime, lifetime)
	assert_true(effect.fire.emitting)
	assert_true(effect.smoke.emitting)
	assert_eq(effect.smoke.amount_ratio, 1.0)

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

func test_height_sampling_preserves_bilinear_surface_and_clamped_edges() -> void:
	var generator := WorldGenerator.new()
	generator.size = 20.0
	generator.resolution = 2
	generator.heights = PackedFloat32Array([0.0, 10.0, 20.0, 40.0])
	assert_eq(generator.height_at(-10, -10), 0.0)
	assert_eq(generator.height_at(10, 10), 40.0)
	assert_eq(generator.height_at(0, 0), 17.5)
	assert_eq(generator.height_at(-5, 5), 19.375)
	assert_eq(generator.height_at(-100, 0), 10.0)
	assert_eq(generator.height_at(100, 100), 40.0)

func test_city_shadow_receivers_share_equal_surfaces_but_preserve_variants() -> void:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	var surfaces: Array[MeshInstance3D] = []
	for index: int in 4:
		var visual := MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("aa9274") if index != 2 else Color("78838b")
		material.roughness = 0.85 if index != 3 else 0.5
		visual.material_override = material
		field.city_visuals.add_child(visual)
		surfaces.append(visual)
	field._configure_city_shadow_receivers()
	assert_same(surfaces[0].material_override, surfaces[1].material_override)
	assert_ne(surfaces[0].material_override, surfaces[2].material_override)
	assert_ne(surfaces[0].material_override, surfaces[3].material_override)
	assert_eq(field.smoke_shadow_materials.size(), 3)
	for index: int in surfaces.size():
		var material := surfaces[index].material_override as ShaderMaterial
		assert_eq(material.get_shader_parameter("base_color"), Color("aa9274") if index != 2 else Color("78838b"))
		assert_almost_eq(float(material.get_shader_parameter("surface_roughness")), 0.85 if index != 3 else 0.5, 0.000001)

func test_opening_raid_waits_for_every_member_and_delayed_group() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	director.enabled = true
	director.opening_raid_started = true
	director.opening_threat_ids.assign([1, 2])
	director.until_spawn = 10000.0
	var first := autofree(ThreatUnit.new()) as ThreatUnit
	first.setup(1, _threat(&"attack_uav"))
	var second := autofree(ThreatUnit.new()) as ThreatUnit
	second.setup(2, _threat(&"attack_uav"))
	director.bind_releases(first)
	director.bind_releases(second)
	director.gameplay_tick(600.0)
	assert_eq(director.pressure_level, 1)
	first.resolve_once(true)
	assert_false(director.opening_raid_complete)
	director.pending_waves.append({"definition_id": "attack_uav", "remaining": 10.0, "angle": 0.0, "opening_raid": true})
	second.resolve_once(false)
	assert_false(director.opening_raid_complete, "아직 출발하지 않은 첫 공습 그룹도 기다린다")
	director.pending_waves.clear()
	director.gameplay_tick(1.0)
	assert_true(director.opening_raid_complete)
	var start := director.pressure_started_at
	assert_eq(start, director.elapsed + SCENARIO.recovery_duration)
	director.gameplay_tick(SCENARIO.recovery_duration - 0.1)
	assert_eq(director.pressure_level, 1)
	director.gameplay_tick(0.1)
	assert_eq(director.pressure_level, 2, "기다린 시간만큼 단계를 몰아서 올리지 않는다")
	director.gameplay_tick(SCENARIO.pressure_step_duration)
	assert_eq(director.pressure_level, 3)
	assert_eq(director.pressure_started_at, start)
	director.reset()
	assert_false(director.opening_raid_started)
	assert_false(director.opening_raid_complete)
	assert_true(director.opening_threat_ids.is_empty())
	assert_eq(director.pressure_level_at(10000.0), 1)

func test_opening_raid_wait_and_rest_are_paused_with_director() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	director.opening_raid_started = true
	director.opening_raid_complete = true
	director.pressure_started_at = SCENARIO.recovery_duration
	director.gameplay_tick(1000.0)
	assert_eq(director.elapsed, 0.0)
	assert_eq(director.pressure_level, 1)

func test_opening_raid_includes_released_threats_but_not_unrelated_contacts() -> void:
	var director := autofree(ThreatDirector.new()) as ThreatDirector
	director.scenario = SCENARIO
	director.registry = ThreatRegistry.new()
	director.opening_raid_started = true
	director.next_runtime_id = 3
	var source := autofree(ThreatUnit.new()) as ThreatUnit
	source.setup(1, _threat(&"attack_uav"))
	director.opening_threat_ids.append(1)
	director.bind_releases(source)
	director.bind_releases(source)
	var released := autofree(ThreatUnit.new()) as ThreatUnit
	released.definition = source.definition
	source.threat_released.emit(released)
	assert_eq(director.opening_threat_ids, [1, 3])
	source.resolve_once(false)
	assert_false(director.opening_raid_complete)
	var unrelated := autofree(ThreatUnit.new()) as ThreatUnit
	unrelated.setup(99, source.definition)
	director.registry.add(unrelated)
	released.resolve_once(true)
	assert_true(director.opening_raid_complete, "다른 공습이나 환경 접촉은 첫 공습 종료를 막지 않는다")
	assert_eq(director.pressure_started_at, SCENARIO.recovery_duration)

func test_visual_warmup_reveals_authored_flashes_without_firing_live_weapons() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var prepared_flash_count := 0
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		var sample := CombatVfxSampleCatalog.create_content_sample(parent, definition) as DefenseUnit
		for child: Node in sample.find_children("*", "GeometryInstance3D", true, false):
			if not child.get_meta("warmup_visible", false):
				continue
			prepared_flash_count += 1
			var case_label := "definition %s node %s" % [definition.id, sample.get_path_to(child)]
			assert_true((child as GeometryInstance3D).visible, "%s warmup visibility" % case_label)
			var live := definition.scene.instantiate() as DefenseUnit
			parent.add_child(live)
			live.setup(1, definition)
			assert_false((live.get_node(sample.get_path_to(child)) as GeometryInstance3D).visible, "%s live visibility" % case_label)
			if sample is MissileBattery:
				assert_eq(
					(sample as MissileBattery).capture_content_state().munition_magazines,
					(live as MissileBattery).capture_content_state().munition_magazines,
					"definition %s 예열용 발사대는 실전 탄약 상태를 소비하지 않습니다" % definition.id
				)
			live.free()
		sample.free()
	assert_gt(prepared_flash_count, 0)

func test_transient_warmup_has_visible_world_space_trails_without_simulation() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var position := Vector3(400, 80, 200)
	var samples := CombatVfxSampleCatalog.create_transient_samples(parent, position)
	var trail_count := 0
	for sample: Node3D in samples:
		var sample_script := sample.get_script() as Script
		var sample_class := sample.get_class()
		if sample_script != null and not sample_script.get_global_name().is_empty():
			sample_class = String(sample_script.get_global_name())
		assert_eq(sample.process_mode, Node.PROCESS_MODE_DISABLED, "%s process mode" % sample_class)
		if sample is HomingInterceptor:
			assert_null((sample as HomingInterceptor).registry, "%s registry" % sample_class)
			assert_null((sample as HomingInterceptor).target_track, "%s target" % sample_class)
		for child: Node in sample.find_children("*", "MultiMeshInstance3D", true, false):
			if child is LingeringSmokeTrail:
				trail_count += 1
				var smoke := child as LingeringSmokeTrail
				var case_label := "%s trail %s" % [sample_class, sample.get_path_to(child)]
				assert_gt(smoke.active_puff_count(), 0, "%s visible puffs" % case_label)
				assert_gt(smoke.shadow_particles.multimesh.visible_instance_count, 0, "%s shadow puffs" % case_label)
				# Moving flares emit downstream; bounds must remain in the fixture's world region.
				assert_lt(smoke.multimesh.custom_aabb.get_center().distance_to(position), 150.0, "%s world bounds" % case_label)
				var preview_age := float(smoke.smoke_material.get_shader_parameter("trail_time"))
				assert_gt(preview_age, 0.0, "%s preview age lower bound" % case_label)
				assert_lt(preview_age, smoke.lifetime, "%s preview age upper bound" % case_label)
	assert_gt(trail_count, 0)

func test_world_prewarmer_retains_transient_materials_after_samples_are_removed() -> void:
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var samples := CombatVfxSampleCatalog.create_transient_samples(parent, Vector3(0, 80, 0))
	var materials: Array[Material] = []
	CombatVfxWorldPrewarmer.retain_sample_materials(samples, materials)
	var count := materials.size()
	assert_gt(count, 0)
	CombatVfxWorldPrewarmer.retain_sample_materials(samples, materials)
	assert_eq(materials.size(), count)
	for sample: Node3D in samples:
		sample.free()
	for material: Material in materials:
		assert_true(is_instance_valid(material))

func _defense(id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		if definition.id == id:
			return definition
	fail_test("missing defense definition %s" % id)
	return null

func _flat_battlefield(size: float, resolution: int) -> Battlefield:
	var field := add_child_autofree(preload("res://world/battlefield.tscn").instantiate()) as Battlefield
	field.battlefield_size = size
	field.generator.size = size
	field.generator.resolution = resolution
	field.generator.sea_level = 0.0
	field.generator.heights.resize(resolution * resolution)
	field.generator.heights.fill(0.0)
	return field

func _threat(id: StringName) -> ThreatDefinition:
	return _threat_entry(id).threat_definition

func _threat_entry(id: StringName) -> ThreatSpawnEntry:
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		if entry.threat_definition.id == id:
			return entry
	fail_test("missing threat definition %s" % id)
	return null

func _raid_archetype(id: StringName) -> RaidArchetypeDefinition:
	for archetype: RaidArchetypeDefinition in SCENARIO.raid_archetypes:
		if archetype.id == id:
			return archetype
	fail_test("missing raid archetype %s" % id)
	return null

func _munition(definition: MissileBatteryDefinition, id: StringName) -> MissileMunitionDefinition:
	for munition: MissileMunitionDefinition in definition.munitions:
		if munition.id == id:
			return munition
	fail_test("missing munition definition %s" % id)
	return null

func _test_objective() -> ProtectedObjective:
	var objective := add_child_autofree(ProtectedObjective.new()) as ProtectedObjective
	var definition := ObjectiveDefinition.new()
	definition.maximum_integrity = 100
	objective.setup(1, definition)
	return objective

func _has_property(instance: Object, property_name: StringName) -> bool:
	for property: Dictionary in instance.get_property_list():
		if StringName(property.name) == property_name:
			return true
	return false
