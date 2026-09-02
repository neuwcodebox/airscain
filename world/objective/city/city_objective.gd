class_name CityObjective
extends ProtectedObjective

func setup(id_value: int, definition_value: ObjectiveDefinition) -> void:
	super.setup(id_value, definition_value)
	var marker: MeshInstance3D = $CoreMarker
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("57c7ff")
	material.emission_enabled = true
	material.emission = Color("176a94")
	marker.material_override = material

func excludes_placement(world_position: Vector3, radius: float) -> bool:
	var hall := $CivicHall as MeshInstance3D
	var hall_mesh := hall.mesh as BoxMesh
	var hall_size := Vector2(hall_mesh.size.x, hall_mesh.size.z) * Vector2(hall.global_basis.get_scale().x, hall.global_basis.get_scale().z)
	var half_extents := hall_size * 0.5
	var local_center := Vector2(hall.global_position.x, hall.global_position.z)
	var footprint := Rect2(local_center - half_extents, hall_size)
	var candidate := Vector2(world_position.x, world_position.z)
	var closest := Vector2(
		clampf(candidate.x, footprint.position.x, footprint.end.x),
		clampf(candidate.y, footprint.position.y, footprint.end.y)
	)
	return closest.distance_squared_to(candidate) <= radius * radius
