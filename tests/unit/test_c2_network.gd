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

func _observe(knowledge: PlayerKnowledge, sensor_id: int, position: Vector3) -> PlayerTrack:
	var observation := SensorObservation.new()
	observation.setup(sensor_id, knowledge.simulation_time, position, 0.9, 5.0, 0.8)
	return knowledge.submit_observation(observation)

func test_owned_track_views_preserve_local_order_and_immediate_changes() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var network := autofree(C2Network.new()) as C2Network
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(100, 0, 0))
	var first := _endpoint(3, DefenseUnit.C2Role.DEFENSE, Vector3(200, 0, 0))
	var second := _endpoint(4, DefenseUnit.C2Role.DEFENSE, Vector3(300, 0, 0))
	first.sensor_ids = [3]
	for endpoint: EndpointDouble in [sensor, command, first, second]:
		network.register_asset(endpoint)
	var shared := _observe(knowledge, 1, Vector3.ZERO)
	var hidden := _observe(knowledge, 99, Vector3(200, 0, 0))
	var local := _observe(knowledge, 3, Vector3(400, 0, 0))
	assert_eq(network.available_tracks_for_knowledge(first, knowledge), [local, shared])
	assert_eq(network.available_tracks_for_knowledge(second, knowledge), [shared])
	var returned := network.available_tracks_for_knowledge(first, knowledge)
	returned.clear()
	assert_eq(network.available_tracks_for_knowledge(first, knowledge), [local, shared], "callers cannot modify another weapon's view")
	assert_same(_observe(knowledge, 1, hidden.estimated_position), hidden)
	assert_eq(network.available_tracks_for_knowledge(first, knowledge), [local, shared, hidden])
	command.active = false
	assert_eq(network.available_tracks_for_knowledge(first, knowledge), [local])
	assert_true(network.available_tracks_for_knowledge(second, knowledge).is_empty())
	command.active = true
	first.sensor_ids.append(99)
	assert_eq(network.available_tracks_for_knowledge(first, knowledge), [hidden, local, shared])
	first.sensor_ids = [3]
	second.position = Vector3(2000, 0, 0)
	assert_true(network.available_tracks_for_knowledge(second, knowledge).is_empty())
	second.position = Vector3(300, 0, 0)
	for endpoint: EndpointDouble in [first, second]:
		assert_eq(network.available_tracks_for_knowledge(endpoint, knowledge), network.available_tracks_for(endpoint, knowledge.get_active_tracks()))

func test_owned_views_follow_prediction_reset_restore_and_lifecycle_callbacks() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var network := autofree(C2Network.new()) as C2Network
	var unit := _endpoint(1, DefenseUnit.C2Role.SENSOR | DefenseUnit.C2Role.COMMAND, Vector3.ZERO)
	network.register_asset(unit)
	for index: int in 3:
		_observe(knowledge, 1, Vector3(index * 300, 100, 0))
	var initial := network.available_tracks_for_knowledge(unit, knowledge)
	initial[0].estimated_velocity = Vector3(100, 0, 0)
	knowledge.gameplay_tick(0.1)
	assert_eq(network.available_tracks_for_knowledge(unit, knowledge)[0].estimated_position, Vector3(10, 100, 0), "cached membership still reads live kinematics")
	var saved := knowledge.capture_state()
	var callback_counts: Array[int] = []
	knowledge.track_state_changed.connect(func(_track: PlayerTrack, _previous: PlayerTrack.State) -> void:
		var result := network.available_tracks_for_knowledge(unit, knowledge)
		assert_eq(result, network.available_tracks_for(unit, knowledge.get_active_tracks()))
		callback_counts.append(result.size())
	)
	knowledge.gameplay_tick(knowledge.lost_after)
	assert_eq(callback_counts, [2, 1, 0], "each lifecycle callback sees all changes made so far")
	knowledge.gameplay_tick(knowledge.remove_after)
	assert_true(network.available_tracks_for_knowledge(unit, knowledge).is_empty())
	var restored_counts: Array[int] = []
	knowledge.track_created.connect(func(_track: PlayerTrack) -> void:
		restored_counts.append(network.available_tracks_for_knowledge(unit, knowledge).size())
	)
	knowledge.restore_state(saved)
	assert_eq(restored_counts, [1, 2, 3])
	assert_eq(network.available_tracks_for_knowledge(unit, knowledge), knowledge.get_active_tracks())
	knowledge.reset()
	assert_true(network.available_tracks_for_knowledge(unit, knowledge).is_empty())
	var other := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	_observe(other, 1, Vector3.ZERO)
	assert_eq(network.available_tracks_for_knowledge(unit, other).size(), 1)
	assert_true(network.available_tracks_for_knowledge(unit, knowledge).is_empty())

func test_owned_views_preserve_jamming_refresh_and_recovery() -> void:
	var knowledge := autofree(PlayerKnowledge.new()) as PlayerKnowledge
	var network := autofree(C2Network.new()) as C2Network
	var registry := ThreatRegistry.new()
	network.configure(registry)
	var sensor := _endpoint(1, DefenseUnit.C2Role.SENSOR, Vector3.ZERO)
	var command := _endpoint(2, DefenseUnit.C2Role.COMMAND, Vector3(200, 0, 0))
	var defense := _endpoint(3, DefenseUnit.C2Role.DEFENSE, Vector3(400, 0, 0))
	for endpoint: EndpointDouble in [sensor, command, defense]:
		network.register_asset(endpoint)
	_observe(knowledge, 1, Vector3.ZERO)
	assert_eq(network.available_tracks_for_knowledge(defense, knowledge).size(), 1)
	var jammer := add_child_autofree(ThreatUnit.new()) as ThreatUnit
	var definition := ThreatDefinition.new()
	definition.affiliation = ThreatDefinition.Affiliation.HOSTILE
	definition.jamming_range = 500.0
	definition.jamming_strength = 1.0
	jammer.setup(99, definition)
	jammer.position = command.position
	registry.add(jammer)
	assert_eq(network.available_tracks_for_knowledge(defense, knowledge).size(), 1, "jamming retains the existing refresh cadence")
	network.gameplay_tick(2.0)
	assert_true(network.available_tracks_for_knowledge(defense, knowledge).is_empty())
	registry.remove(jammer)
	network.gameplay_tick(2.0)
	assert_eq(network.available_tracks_for_knowledge(defense, knowledge).size(), 1)
