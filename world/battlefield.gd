class_name Battlefield
extends Node3D

const OCEAN_SIZE_MULTIPLIER := 8.0

var generator := WorldGenerator.new()
var objective: ProtectedObjective
var occupied_positions: Array[Vector3] = []
var occupied_radii: Array[float] = []
var rooftop_pads: Array[Dictionary] = []
var battlefield_size: float = 2400.0

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
	_build_city_visuals(generator.building_transforms(), layout.rooftop_spacing)

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

func clear_occupancy() -> void:
	occupied_positions.clear()
	occupied_radii.clear()

func _build_city_visuals(transforms: Array[Transform3D], rooftop_spacing: int) -> void:
	for child: Node in city_visuals.get_children():
		child.free()
	rooftop_pads.clear()
	var palette: Array[Color] = [Color("8795a1"), Color("a6adb4"), Color("77828a"), Color("c0aa8d")]
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
		if index % rooftop_spacing == 0:
			_build_rooftop_pad(index, transforms[index])

func _build_rooftop_pad(index: int, building_transform: Transform3D) -> void:
	var building_size := building_transform.basis.get_scale()
	var radius := minf(building_size.x, building_size.z) * 0.5 - 2.5
	if radius < 8.0:
		return
	var position := building_transform.origin + Vector3.UP * (building_size.y * 0.5 + 0.35)
	rooftop_pads.append({"position": position, "radius": radius})
	var pad_visual := MeshInstance3D.new()
	pad_visual.name = "RooftopPad%d" % index
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = radius
	pad_mesh.bottom_radius = radius
	pad_mesh.height = 0.5
	pad_visual.mesh = pad_mesh
	pad_visual.position = position
	var pad_material := StandardMaterial3D.new()
	pad_material.albedo_color = Color(0.12, 0.55, 0.64, 1.0)
	pad_material.roughness = 0.7
	pad_visual.material_override = pad_material
	city_visuals.add_child(pad_visual)
	var body := StaticBody3D.new()
	body.name = "RooftopSurface%d" % index
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 2.0, 0.5, radius * 2.0)
	collision.shape = shape
	body.add_child(collision)
	city_visuals.add_child(body)
