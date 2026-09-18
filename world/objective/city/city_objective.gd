class_name CityObjective
extends ProtectedObjective

const REFERENCE_WIDTH := 34.0
const BLOCK_MARGIN := 4.0

func initial_defense_mounts() -> Array[Dictionary]:
	var mount := $CommandMount as Marker3D
	return [{
		"definition_id": &"command_post",
		"position": mount.global_position,
		"rotation_y": mount.global_rotation.y,
	}]

func fit_to_city_block(block_size: float) -> void:
	var horizontal_scale := maxf((block_size - BLOCK_MARGIN) / REFERENCE_WIDTH, 0.1)
	scale = Vector3(horizontal_scale, 1.0, horizontal_scale)

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
