extends GutTest

const TURRET_AIMER := preload("res://defense/turret_aimer.gd")

func test_shared_turret_aiming_traverses_yaw_and_elevation_before_alignment() -> void:
	var root := add_child_autofree(Node3D.new()) as Node3D
	var yaw := Node3D.new()
	var elevation := Node3D.new()
	root.add_child(yaw)
	yaw.add_child(elevation)
	var target := Vector3(100.0, 100.0, 0.0)
	assert_false(TURRET_AIMER.aim(yaw, elevation, target, 45.0, 30.0, 2.0, 0.1))
	assert_lt(yaw.rotation.y, 0.0)
	assert_gt(elevation.rotation.x, 0.0)
	for frame: int in 60:
		TURRET_AIMER.aim(yaw, elevation, target, 45.0, 30.0, 2.0, 0.1)
	assert_true(TURRET_AIMER.aim(yaw, elevation, target, 45.0, 30.0, 2.0, 0.1))
	var aim_direction := -elevation.global_transform.basis.z.normalized()
	assert_gt(aim_direction.dot(elevation.global_position.direction_to(target)), 0.995)
