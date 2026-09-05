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

func test_ciws_barrel_cluster_tracks_elevation_and_spins_without_moving_the_muzzle() -> void:
	var definition := preload("res://defense/close_in_gun/close_in_gun.tres")
	var gun := add_child_autofree(definition.scene.instantiate()) as CloseInGun
	gun.setup(11, definition)
	assert_eq(gun.barrel_cluster.find_children("Barrel?", "MeshInstance3D", false, false).size(), 6)
	assert_not_null(gun.get_node("Turret/RadarDome"))
	assert_not_null(gun.get_node("Turret/AmmunitionDrum"))
	var target := Vector3(60, 45, -80)
	for index: int in 10:
		gun._aim_turret(target, 0.1)
	var muzzle_position := gun.muzzle.global_position
	var start_angle := gun.barrel_cluster.rotation.z
	gun._on_round_fired(muzzle_position)
	gun.gameplay_tick(0.1)
	assert_ne(gun.barrel_cluster.rotation.z, start_angle)
	assert_almost_eq(gun.muzzle.global_position, muzzle_position, Vector3.ONE * 0.001)
	assert_gt((-gun.barrel_cluster.global_basis.z).normalized().dot((-gun.muzzle.global_basis.z).normalized()), 0.999)
	var paused_angle := gun.barrel_cluster.rotation.z
	gun.gameplay_tick(0)
	assert_eq(gun.barrel_cluster.rotation.z, paused_angle)
	gun.gameplay_tick(1.0)
	assert_eq(gun.barrel_spin_speed, 0.0)
