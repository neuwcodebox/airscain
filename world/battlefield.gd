class_name Battlefield
extends Node3D

var generator := WorldGenerator.new()
var objective: ProtectedObjective
var occupied_positions: Array[Vector3] = []
var occupied_radii: Array[float] = []
var battlefield_size: float = 1800.0

@onready var terrain: MeshInstance3D = $Terrain
@onready var ocean: MeshInstance3D = $Ocean
@onready var city_visuals: Node3D = $CityVisuals

func build(scenario: ScenarioDefinition) -> void:
	battlefield_size = scenario.battlefield_size
	generator.generate(scenario.world_seed, scenario.battlefield_size, scenario.terrain_resolution, scenario.city_size)
	terrain.mesh = generator.create_terrain_mesh()
	terrain.create_trimesh_collision()
	var ocean_mesh := ocean.mesh as PlaneMesh
	ocean_mesh.size = Vector2(scenario.battlefield_size * 4.0, scenario.battlefield_size * 4.0)
	ocean.position.y = generator.sea_level
	_build_city_visuals(generator.building_transforms())

func set_objective(objective_value: ProtectedObjective) -> void:
	objective = objective_value

func placement_result(position: Vector3, profile: PlacementProfile) -> Dictionary:
	var half := battlefield_size * 0.5
	if absf(position.x) + profile.footprint_radius + profile.boundary_margin > half or absf(position.z) + profile.footprint_radius + profile.boundary_margin > half:
		return {"valid": false, "reason": "지도 경계 밖입니다"}
	if objective != null and objective.excludes_placement(position, profile.footprint_radius):
		return {"valid": false, "reason": "도시 내부에는 배치할 수 없습니다"}
	if generator.height_at(position.x, position.z) <= generator.sea_level + 1.0:
		return {"valid": false, "reason": "바다에는 배치할 수 없습니다"}
	if generator.slope_degrees_at(position.x, position.z, profile.footprint_radius) > profile.maximum_slope_degrees:
		return {"valid": false, "reason": "지형 경사가 너무 가파릅니다"}
	for index: int in occupied_positions.size():
		var flat_distance := Vector2(position.x - occupied_positions[index].x, position.z - occupied_positions[index].z).length()
		if flat_distance < profile.footprint_radius + occupied_radii[index]:
			return {"valid": false, "reason": "다른 방어 수단과 겹칩니다"}
	return {"valid": true, "reason": "배치 가능"}

func register_occupancy(position: Vector3, radius: float) -> void:
	occupied_positions.append(position)
	occupied_radii.append(radius)

func terrain_height(x: float, z: float) -> float:
	return generator.height_at(x, z)

func clear_occupancy() -> void:
	occupied_positions.clear()
	occupied_radii.clear()

func _build_city_visuals(transforms: Array[Transform3D]) -> void:
	for child: Node in city_visuals.get_children():
		child.queue_free()
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
