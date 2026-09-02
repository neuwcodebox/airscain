class_name Battlefield
extends Node3D

const OCEAN_SIZE_MULTIPLIER := 8.0

var generator := WorldGenerator.new()
var objective: ProtectedObjective
var occupied_positions: Array[Vector3] = []
var occupied_radii: Array[float] = []
var rooftop_pads: Array[Dictionary] = []
var battlefield_size: float = 2400.0
var city_block_surface_count: int = 0
var city_road_width: float = 11.0
var city_window_band_count: int = 0
var city_amenity_count: int = 0
var city_rooftop_detail_count: int = 0
var rooftop_pad_visuals: Array[MeshInstance3D] = []

@onready var terrain: MeshInstance3D = $Terrain
@onready var ocean: MeshInstance3D = $Ocean
@onready var city_visuals: Node3D = $CityVisuals

func build(scenario: ScenarioDefinition) -> void:
	battlefield_size = scenario.battlefield_size
	var layout := scenario.battlefield_layout()
	generator.generate(scenario.world_seed, scenario.battlefield_size, scenario.terrain_resolution, scenario.city_size, layout)
	for child: Node in terrain.get_children():
		child.free()
	terrain.mesh = generator.create_terrain_mesh()
	terrain.create_trimesh_collision()
	var ocean_mesh := ocean.mesh as PlaneMesh
	ocean_mesh.size = Vector2.ONE * scenario.battlefield_size * OCEAN_SIZE_MULTIPLIER
	ocean.position.y = generator.sea_level
	_build_city_ground(scenario.city_size, layout.city_blocks)
	_build_city_visuals(generator.building_transforms(), layout.rooftop_spacing, scenario.city_size, layout.city_blocks)

func set_objective(objective_value: ProtectedObjective) -> void:
	objective = objective_value

func placement_result(position: Vector3, profile: PlacementProfile) -> Dictionary:
	var half := battlefield_size * 0.5
	if absf(position.x) + profile.footprint_radius + profile.boundary_margin > half or absf(position.z) + profile.footprint_radius + profile.boundary_margin > half:
		return {"valid": false, "reason": "지도 경계 밖입니다"}
	var rooftop_index := _rooftop_index_at(position)
	if rooftop_index >= 0:
		if not profile.rooftop_allowed:
			return {"valid": false, "reason": "이 장비는 옥상에 배치할 수 없습니다"}
		if profile.footprint_radius > float(rooftop_pads[rooftop_index].radius):
			return {"valid": false, "reason": "옥상 공간이 부족합니다"}
		return _occupancy_result(rooftop_pads[rooftop_index].position, profile)
	if objective != null and objective.excludes_placement(position, profile.footprint_radius):
		return {"valid": false, "reason": "도시 내부에는 배치할 수 없습니다"}
	if generator.height_at(position.x, position.z) <= generator.sea_level + 1.0:
		return {"valid": false, "reason": "바다에는 배치할 수 없습니다"}
	if generator.slope_degrees_at(position.x, position.z, profile.footprint_radius) > profile.maximum_slope_degrees:
		return {"valid": false, "reason": "지형 경사가 너무 가파릅니다"}
	return _occupancy_result(position, profile)

func snap_placement_position(position: Vector3, profile: PlacementProfile) -> Vector3:
	if profile.rooftop_allowed:
		var rooftop_index := _rooftop_index_at(position, 4.0)
		if rooftop_index >= 0:
			return rooftop_pads[rooftop_index].position
	return Vector3(position.x, terrain_height(position.x, position.z), position.z)

func _occupancy_result(position: Vector3, profile: PlacementProfile) -> Dictionary:
	for index: int in occupied_positions.size():
		var flat_distance := Vector2(position.x - occupied_positions[index].x, position.z - occupied_positions[index].z).length()
		if flat_distance < profile.footprint_radius + occupied_radii[index]:
			return {"valid": false, "reason": "다른 방어 수단과 겹칩니다"}
	return {"valid": true, "reason": "배치 가능"}

func _rooftop_index_at(position: Vector3, height_tolerance: float = 2.0) -> int:
	for index: int in rooftop_pads.size():
		var pad_position: Vector3 = rooftop_pads[index].position
		if absf(position.y - pad_position.y) <= height_tolerance and Vector2(position.x - pad_position.x, position.z - pad_position.z).length() <= float(rooftop_pads[index].radius):
			return index
	return -1

func register_occupancy(position: Vector3, radius: float) -> void:
	occupied_positions.append(position)
	occupied_radii.append(radius)

func unregister_occupancy(position: Vector3, radius: float) -> void:
	for index: int in range(occupied_positions.size() - 1, -1, -1):
		if occupied_positions[index].distance_squared_to(position) < 0.01 and is_equal_approx(occupied_radii[index], radius):
			occupied_positions.remove_at(index)
			occupied_radii.remove_at(index)
			return

func terrain_height(x: float, z: float) -> float:
	return generator.height_at(x, z)

func flight_surface_height(x: float, z: float) -> float:
	return maxf(generator.height_at(x, z), generator.sea_level)

func clear_occupancy() -> void:
	occupied_positions.clear()
	occupied_radii.clear()

func set_rooftop_pads_visible(visible_value: bool) -> void:
	for pad: MeshInstance3D in rooftop_pad_visuals:
		if is_instance_valid(pad):
			pad.visible = visible_value

func _build_city_visuals(transforms: Array[Transform3D], rooftop_spacing: int, city_size: float, block_count: int) -> void:
	rooftop_pads.clear()
	rooftop_pad_visuals.clear()
	city_window_band_count = 0
	city_amenity_count = 0
	city_rooftop_detail_count = 0
	var palette: Array[Color] = [Color("8f7868"), Color("b8ad99"), Color("78838b"), Color("aa9274"), Color("c4c0b5"), Color("6f7a80")]
	var facade_bands: Array[Transform3D] = []
	for index: int in transforms.size():
		var building := MeshInstance3D.new()
		building.name = "Building%d" % index
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		building.mesh = box
		building.transform = transforms[index]
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[index % palette.size()]
		material.roughness = 0.85
		building.material_override = material
		city_visuals.add_child(building)
		_add_building_architecture(index, transforms[index], material, index % rooftop_spacing == 0)
		_append_facade_bands(transforms[index], facade_bands)
		if index % rooftop_spacing == 0:
			_build_rooftop_pad(index, transforms[index])
	_build_facade_multimesh(facade_bands)
	_build_city_amenities(transforms, city_size, block_count)

func _add_building_architecture(index: int, building_transform: Transform3D, facade_material: StandardMaterial3D, reserves_rooftop: bool) -> void:
	var building_size := building_transform.basis.get_scale()
	var ground_y := building_transform.origin.y - building_size.y * 0.5
	var podium_height := minf(7.0, building_size.y * 0.22)
	if index % 3 == 0:
		_add_city_box("Podium%d" % index, Vector3(building_size.x + 2.4, podium_height, building_size.z + 2.4), Vector3(building_transform.origin.x, ground_y + podium_height * 0.5, building_transform.origin.z), facade_material)
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = facade_material.albedo_color.darkened(0.24)
	roof_material.roughness = 0.88
	var roof_y := ground_y + building_size.y
	_add_city_box("RoofCap%d" % index, Vector3(building_size.x + 0.7, 0.6, building_size.z + 0.7), Vector3(building_transform.origin.x, roof_y + 0.3, building_transform.origin.z), roof_material)
	if reserves_rooftop:
		return
	if building_size.y >= 28.0 and index % 2 == 0:
		var crown_height := clampf(building_size.y * 0.12, 3.0, 7.0)
		_add_city_box("Penthouse%d" % index, Vector3(building_size.x * 0.5, crown_height, building_size.z * 0.48), Vector3(building_transform.origin.x, roof_y + crown_height * 0.5 + 0.6, building_transform.origin.z), roof_material)
		city_rooftop_detail_count += 1
	else:
		for unit_index: int in 2:
			var offset_x := (-0.22 if unit_index == 0 else 0.22) * building_size.x
			_add_city_box("Hvac%d_%d" % [index, unit_index], Vector3(3.0, 1.8, 2.4), Vector3(building_transform.origin.x + offset_x, roof_y + 1.2, building_transform.origin.z), roof_material)
			city_rooftop_detail_count += 1

func _append_facade_bands(building_transform: Transform3D, bands: Array[Transform3D]) -> void:
	var building_size := building_transform.basis.get_scale()
	var ground_y := building_transform.origin.y - building_size.y * 0.5
	var floor_count := clampi(floori(building_size.y / 6.0), 2, 12)
	for floor_index: int in floor_count:
		var y := ground_y + minf(building_size.y - 2.0, 3.5 + float(floor_index) * 5.5)
		bands.append(Transform3D(Basis.IDENTITY.scaled(Vector3(building_size.x * 0.72, 0.72, 0.12)), Vector3(building_transform.origin.x, y, building_transform.origin.z + building_size.z * 0.5 + 0.07)))
		bands.append(Transform3D(Basis.IDENTITY.scaled(Vector3(building_size.x * 0.72, 0.72, 0.12)), Vector3(building_transform.origin.x, y, building_transform.origin.z - building_size.z * 0.5 - 0.07)))
		bands.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.12, 0.72, building_size.z * 0.72)), Vector3(building_transform.origin.x + building_size.x * 0.5 + 0.07, y, building_transform.origin.z)))
		bands.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.12, 0.72, building_size.z * 0.72)), Vector3(building_transform.origin.x - building_size.x * 0.5 - 0.07, y, building_transform.origin.z)))

func _build_facade_multimesh(bands: Array[Transform3D]) -> void:
	if bands.is_empty():
		return
	var window_material := StandardMaterial3D.new()
	window_material.albedo_color = Color("263c48")
	window_material.metallic = 0.22
	window_material.roughness = 0.3
	window_material.emission_enabled = true
	window_material.emission = Color("102630")
	window_material.emission_energy_multiplier = 0.6
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3.ONE
	window_mesh.material = window_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = window_mesh
	multimesh.instance_count = bands.size()
	for index: int in bands.size():
		multimesh.set_instance_transform(index, bands[index])
	var windows := MultiMeshInstance3D.new()
	windows.name = "FacadeWindows"
	windows.multimesh = multimesh
	city_visuals.add_child(windows)
	city_window_band_count = bands.size()

func _build_city_amenities(buildings: Array[Transform3D], city_size: float, block_count: int) -> void:
	var block_step := city_size / float(block_count)
	var center := float(block_count - 1) * 0.5
	for bz: int in block_count:
		for bx: int in block_count:
			var block_center := Vector3((float(bx) - center) * block_step, 0.0, (float(bz) - center) * block_step)
			if _block_has_building(block_center, buildings, block_step * 0.42):
				continue
			block_center.y = generator.height_at(block_center.x, block_center.z) + 0.58
			if bx == int(center) and bz == int(center) or (bx + bz) % 2 == 0:
				_build_park("Park%d_%d" % [bx, bz], block_center, block_step - city_road_width - 4.0)
			else:
				_build_parking_lot("Parking%d_%d" % [bx, bz], block_center, block_step - city_road_width - 4.0)
			city_amenity_count += 1

func _block_has_building(block_center: Vector3, buildings: Array[Transform3D], radius: float) -> bool:
	for building: Transform3D in buildings:
		if Vector2(building.origin.x - block_center.x, building.origin.z - block_center.z).length() <= radius:
			return true
	return false

func _build_park(park_name: String, center: Vector3, size: float) -> void:
	var lawn_material := StandardMaterial3D.new()
	lawn_material.albedo_color = Color("446b43")
	lawn_material.roughness = 1.0
	_add_city_box(park_name, Vector3(size, 0.22, size), center, lawn_material)
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color("5b4532")
	var crown_material := StandardMaterial3D.new()
	crown_material.albedo_color = Color("355b39")
	crown_material.roughness = 0.95
	var offsets: Array[Vector2] = [Vector2(-0.27, -0.24), Vector2(0.25, -0.18), Vector2(-0.2, 0.26), Vector2(0.24, 0.25)]
	for tree_index: int in offsets.size():
		var tree_position := center + Vector3(offsets[tree_index].x * size, 0.0, offsets[tree_index].y * size)
		var trunk := MeshInstance3D.new()
		trunk.name = "%sTreeTrunk%d" % [park_name, tree_index]
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.45
		trunk_mesh.bottom_radius = 0.65
		trunk_mesh.height = 4.2
		trunk.mesh = trunk_mesh
		trunk.position = tree_position + Vector3.UP * 2.2
		trunk.material_override = trunk_material
		city_visuals.add_child(trunk)
		var crown := MeshInstance3D.new()
		crown.name = "%sTreeCrown%d" % [park_name, tree_index]
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 2.4
		crown_mesh.height = 4.8
		crown_mesh.radial_segments = 7
		crown_mesh.rings = 4
		crown.mesh = crown_mesh
		crown.position = tree_position + Vector3.UP * 5.2
		crown.material_override = crown_material
		city_visuals.add_child(crown)

func _build_parking_lot(lot_name: String, center: Vector3, size: float) -> void:
	var lot_material := StandardMaterial3D.new()
	lot_material.albedo_color = Color("45494b")
	lot_material.roughness = 0.95
	_add_city_box(lot_name, Vector3(size, 0.18, size), center, lot_material)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = Color("d8d5c6")
	for stripe_index: int in 7:
		var x := center.x - size * 0.38 + float(stripe_index) * size * 0.125
		_add_city_box("%sStripe%d" % [lot_name, stripe_index], Vector3(0.22, 0.05, size * 0.38), Vector3(x, center.y + 0.13, center.z), stripe_material)

func _build_city_ground(city_size: float, block_count: int) -> void:
	for child: Node in city_visuals.get_children():
		child.free()
	city_block_surface_count = 0
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("343a40")
	asphalt.roughness = 0.96
	_add_city_box("RoadNetwork", Vector3(city_size + 18.0, 0.35, city_size + 18.0), Vector3(0.0, generator.height_at(0.0, 0.0) + 0.08, 0.0), asphalt)
	var block_step := city_size / float(block_count)
	var block_size := block_step - city_road_width
	var center := float(block_count - 1) * 0.5
	var pavement_palette: Array[Color] = [Color("777a78"), Color("85847f"), Color("6f7472")]
	for bz: int in block_count:
		for bx: int in block_count:
			var x := (float(bx) - center) * block_step
			var z := (float(bz) - center) * block_step
			var material := StandardMaterial3D.new()
			material.albedo_color = pavement_palette[(bx + bz * block_count) % pavement_palette.size()]
			material.roughness = 0.9
			_add_city_box("CityBlock%d_%d" % [bx, bz], Vector3(block_size, 0.55, block_size), Vector3(x, generator.height_at(x, z) + 0.24, z), material)
			city_block_surface_count += 1
	_build_road_markings(city_size, block_count, block_step)

func _build_road_markings(city_size: float, block_count: int, block_step: float) -> void:
	var marking_material := StandardMaterial3D.new()
	marking_material.albedo_color = Color("d7c46a")
	marking_material.roughness = 0.82
	var center := float(block_count - 1) * 0.5
	for boundary: int in block_count - 1:
		var offset := (float(boundary) - center + 0.5) * block_step
		_add_city_box("LaneX%d" % boundary, Vector3(city_size, 0.06, 0.38), Vector3(0.0, generator.height_at(0.0, offset) + 0.31, offset), marking_material)
		_add_city_box("LaneZ%d" % boundary, Vector3(0.38, 0.06, city_size), Vector3(offset, generator.height_at(offset, 0.0) + 0.31, 0.0), marking_material)

func _add_city_box(node_name: String, box_size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = box_size
	visual.mesh = mesh
	visual.position = position
	visual.material_override = material
	city_visuals.add_child(visual)
	return visual

func _build_rooftop_pad(index: int, building_transform: Transform3D) -> void:
	var building_size := building_transform.basis.get_scale()
	var radius := minf(building_size.x, building_size.z) * 0.5 - 2.5
	if radius < 8.0:
		return
	var position := building_transform.origin + Vector3.UP * (building_size.y * 0.5 + 0.35)
	rooftop_pads.append({"position": position, "radius": radius})
	var pad_visual := MeshInstance3D.new()
	pad_visual.name = "RooftopPad%d" % index
	var pad_mesh := TorusMesh.new()
	pad_mesh.inner_radius = maxf(1.0, radius - 1.1)
	pad_mesh.outer_radius = radius
	pad_mesh.rings = 8
	pad_mesh.ring_segments = 32
	pad_visual.mesh = pad_mesh
	pad_visual.position = position + Vector3.UP * 0.65
	var pad_material := StandardMaterial3D.new()
	pad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_material.albedo_color = Color(0.12, 0.78, 0.9, 0.72)
	pad_material.emission_enabled = true
	pad_material.emission = Color(0.04, 0.34, 0.42)
	pad_material.roughness = 0.7
	pad_visual.material_override = pad_material
	pad_visual.visible = false
	city_visuals.add_child(pad_visual)
	rooftop_pad_visuals.append(pad_visual)
	var body := StaticBody3D.new()
	body.name = "RooftopSurface%d" % index
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 2.0, 0.5, radius * 2.0)
	collision.shape = shape
	body.add_child(collision)
	city_visuals.add_child(body)
