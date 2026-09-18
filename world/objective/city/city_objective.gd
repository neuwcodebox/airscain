class_name CityObjective
extends ProtectedObjective

func initial_defense_mounts() -> Array[Dictionary]:
	var mount := $CommandMount as Marker3D
	return [{
		"definition_id": &"command_post",
		"position": mount.global_position,
		"rotation_y": mount.global_rotation.y,
	}]

func excludes_placement(world_position: Vector3, radius: float) -> bool:
	var hall := $CivicHall as MeshInstance3D
	var hall_mesh := hall.mesh as BoxMesh
	var hall_scale := hall.global_basis.get_scale()
	var hall_size := Vector2(hall_mesh.size.x * hall_scale.x, hall_mesh.size.z * hall_scale.z)
	var half_extents := hall_size * 0.5
	var offset := world_position - hall.global_position
	var hall_right := hall.global_basis.x.normalized()
	var hall_back := hall.global_basis.z.normalized()
	var local_candidate := Vector2(offset.dot(hall_right), offset.dot(hall_back))
	var closest := Vector2(
		clampf(local_candidate.x, -half_extents.x, half_extents.x),
		clampf(local_candidate.y, -half_extents.y, half_extents.y)
	)
	return closest.distance_squared_to(local_candidate) <= radius * radius
