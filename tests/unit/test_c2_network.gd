extends GutTest

class EndpointDouble:
	extends DefenseUnit
	var role_flags: int
	var link_range: float = 500.0
	var sensor_ids: Array[int] = []

	func c2_roles() -> int:
		return role_flags

	func c2_link_range() -> float:
		return link_range

	func local_sensor_ids() -> Array[int]:
		return sensor_ids

func test_command_path_shares_sensor_track_with_connected_defense() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	sensor.sensor_ids = [1]
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(100.0, 0.0, 0.0))
	var defense := _endpoint(3, DefenseUnit.C2Role.DEFENSE, Vector3(200.0, 0.0, 0.0))
	for endpoint: EndpointDouble in [sensor, command, defense]:
		network.register_asset(endpoint)
	var track := _track_from_sensor(1)
	var tracks: Array[PlayerTrack] = [track]
	assert_eq(network.local_tracks_for(sensor, tracks), tracks)
	assert_true(network.local_tracks_for(defense, tracks).is_empty())
	assert_eq(network.shared_tracks_for(defense, tracks), tracks)
	assert_eq(network.available_tracks_for(defense, tracks), tracks)

func test_direct_sensor_link_without_command_does_not_share_tracks() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var defense := _endpoint(2, DefenseUnit.C2Role.DEFENSE, Vector3(100.0, 0.0, 0.0))
	network.register_asset(sensor)
	network.register_asset(defense)
	var tracks: Array[PlayerTrack] = [_track_from_sensor(1)]
	assert_false(network.has_command_path(defense, 1))
	assert_true(network.available_tracks_for(defense, tracks).is_empty())

func test_disabled_or_disconnected_command_breaks_information_path() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(100.0, 0.0, 0.0))
	var defense := _endpoint(3, DefenseUnit.C2Role.DEFENSE, Vector3(200.0, 0.0, 0.0))
	for endpoint: EndpointDouble in [sensor, command, defense]:
		network.register_asset(endpoint)
	assert_true(network.has_command_path(defense, 1))
	command.active = false
	assert_false(network.has_command_path(defense, 1))
	command.active = true
	defense.global_position = Vector3(900.0, 0.0, 0.0)
	assert_false(network.has_command_path(defense, 1))

func test_jamming_reduces_effective_link_range_and_breaks_path() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var registry := ThreatRegistry.new()
	network.configure(registry)
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(200.0, 0.0, 0.0))
	var defense := _endpoint(3, DefenseUnit.C2Role.DEFENSE, Vector3(400.0, 0.0, 0.0))
	for endpoint: EndpointDouble in [sensor, command, defense]:
		network.register_asset(endpoint)
	assert_true(network.has_command_path(defense, 1))
	var jammer := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var jammer_definition := ThreatDefinition.new()
	jammer_definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	jammer_definition.jamming_range = 500.0
	jammer_definition.jamming_strength = 1.0
	jammer.setup(99, jammer_definition)
	jammer.global_position = command.global_position
	registry.add(jammer)
	network.gameplay_tick(2.0)
	assert_false(network.has_command_path(defense, 1))

func test_placement_preview_reports_complete_sensor_command_defense_component() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(100.0, 0.0, 0.0))
	network.register_asset(sensor)
	network.register_asset(command)
	var definition := MissileBatteryDefinition.new()
	definition.c2_range = 500.0
	var result := network.placement_preview(definition, Vector3(200.0, 0.0, 0.0))
	assert_true(result.ready)
	assert_eq((result.links as Array).size(), 2)

func test_placement_preview_marks_incomplete_and_disconnected_components() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	network.register_asset(sensor)
	var definition := MissileBatteryDefinition.new()
	definition.c2_range = 500.0
	var incomplete := network.placement_preview(definition, Vector3(100.0, 0.0, 0.0))
	assert_false(incomplete.ready)
	assert_eq((incomplete.links as Array).size(), 1)
	var disconnected := network.placement_preview(definition, Vector3(900.0, 0.0, 0.0))
	assert_false(disconnected.ready)
	assert_true((disconnected.links as Array).is_empty())

func test_placement_preview_ignores_an_asset_at_the_exact_candidate_position() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var existing := _endpoint(1, DefenseUnit.C2Role.DEFENSE, Vector3.ZERO)
	network.register_asset(existing)
	var definition := MissileBatteryDefinition.new()
	var result := network.placement_preview(definition, Vector3.ZERO)
	assert_false(result.ready)
	assert_true((result.links as Array).is_empty())

func _endpoint(id_value: int, roles: int, position: Vector3) -> EndpointDouble:
	var endpoint := add_child_autofree(EndpointDouble.new()) as EndpointDouble
	endpoint.runtime_id = id_value
	endpoint.role_flags = roles
	endpoint.global_position = position
	return endpoint

func test_available_track_query_preserves_local_first_order_and_live_observations() -> void:
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(100, 0, 0))
	var defense := _endpoint(3, DefenseUnit.C2Role.DEFENSE, Vector3(200, 0, 0))
	defense.sensor_ids = [3]
	for endpoint: EndpointDouble in [sensor, command, defense]:
		network.register_asset(endpoint)
	var shared := _track_from_sensor(1)
	var local := _track_from_sensor(3)
	var unknown := _track_from_sensor(99)
	var tracks: Array[PlayerTrack] = [shared, unknown, local]
	assert_eq(network.available_tracks_for(defense, tracks), [local, shared])
	unknown.contributing_sensor_ids.append(1)
	assert_eq(network.available_tracks_for(defense, tracks), [local, shared, unknown])
	command.active = false
	assert_eq(network.available_tracks_for(defense, tracks), [local])
	command.active = true
	assert_eq(network.available_tracks_for(defense, tracks), [local, shared, unknown])

func _track_from_sensor(sensor_id: int) -> PlayerTrack:
	var track := PlayerTrack.new()
	track.track_id = 1
	track.state = PlayerTrack.State.CONFIRMED
	track.contributing_sensor_ids = [sensor_id]
	return track
