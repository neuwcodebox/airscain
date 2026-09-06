class_name AircraftStrikeRelease
extends RefCounted
## Aircraft weapon release geometry and construction, independent of navigation.

const BOMB_SCENE := preload("res://effects/air_strike_munition/air_strike_munition.tscn")
const HARDPOINT := Vector3(3.5, -1.5, 0.2)
const BOMB_RELEASE_TOLERANCE := 4.0

static func ready(profile: ThreatMissionDefinition, body_transform: Transform3D, target: Vector3, velocity: Vector3, delta: float) -> bool:
	var offset := target - body_transform * HARDPOINT
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	var forward := Vector3(velocity.x, 0.0, velocity.z)
	if forward.length_squared() < 1.0:
		return false
	if profile.released_missile != null:
		return horizontal.length() <= profile.action_distance and forward.normalized().dot(horizontal.normalized()) >= cos(deg_to_rad(profile.launch_cone_degrees))
	var gravity := StrikeFlight.GRAVITY
	var fall_time := (velocity.y + sqrt(maxf(0.0, velocity.y * velocity.y - 2.0 * gravity * offset.y))) / gravity
	# Leave margin inside the smallest asset's impact radius for the hardpoint
	# offset and the difference between target elevation and sloping terrain.
	return fall_time > 0.0 and (horizontal - forward * fall_time).length() <= maxf(BOMB_RELEASE_TOLERANCE, forward.length() * delta)

static func release(parent: Node, body_transform: Transform3D, mission: ThreatMissionRuntime, target: Vector3, velocity: Vector3, battlefield: Battlefield, objective: ProtectedObjective) -> Node3D:
	if parent == null:
		return null
	var profile := mission.profile
	var city := profile.target_role == ThreatMissionDefinition.TargetRole.CITY
	if profile.released_missile != null:
		var missile := profile.released_missile.scene.instantiate() as AirLaunchedMissile
		parent.add_child(missile)
		missile.global_position = body_transform * HARDPOINT
		missile.setup(0, profile.released_missile)
		missile.launch(target, objective, battlefield, roundi(profile.damage), mission.target_asset, city, velocity)
		return missile
	var bomb := BOMB_SCENE.instantiate() as AirStrikeMunition
	parent.add_child(bomb)
	bomb.global_position = body_transform * HARDPOINT
	bomb.setup(target, objective, roundi(profile.damage), mission.target_asset, city)
	bomb.configure_flight(StrikeFlight.Mode.BOMB, velocity, battlefield)
	return bomb
