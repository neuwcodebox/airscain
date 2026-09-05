extends SceneTree
## Fixed query workload; use --headless --audio-driver Dummy.

class Endpoint:
	extends DefenseUnit
	func c2_roles() -> int:
		return C2Role.SENSOR | C2Role.COMMAND | C2Role.DEFENSE
	func c2_link_range() -> float:
		return 1000.0
	func local_sensor_ids() -> Array[int]:
		return [runtime_id]

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var coordinator := EngagementCoordinator.new()
	for index: int in 300:
		coordinator.try_reserve(index % 100 + 1, index + 1, 10, 10)
	for index: int in 100:
		coordinator.reserve_fire_support(index + 1, index + 301)
	var checksum := 0
	var samples: Array[float] = []
	for repeat: int in 100:
		var start := Time.get_ticks_usec()
		for track_id: int in range(1, 101):
			checksum += coordinator.reservation_count(track_id, EngagementCoordinator.INTERCEPTOR)
			checksum += coordinator.engagement_owner_ids(track_id).size()
			checksum += coordinator.fire_support_target(track_id + 300)
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	var total := 0.0
	for value: float in samples:
		total += value
	samples.sort()
	print("NETWORK_PERF query_avg_ms=", total / samples.size(), " p95_ms=", samples[95], " checksum=", checksum)
	coordinator.free()
	var network := C2Network.new()
	root.add_child(network)
	var endpoints: Array[Endpoint] = []
	for index: int in 40:
		var endpoint := Endpoint.new()
		root.add_child(endpoint)
		endpoint.runtime_id = index + 1
		endpoint.position = Vector3(index, 0, 0)
		network.register_asset(endpoint)
		endpoints.append(endpoint)
	var tracks: Array[PlayerTrack] = []
	for index: int in 200:
		var track := PlayerTrack.new()
		track.track_id = index + 1
		track.contributing_sensor_ids = [index % 40 + 1]
		tracks.append(track)
	checksum = 0
	var started := Time.get_ticks_usec()
	for repeat: int in 100:
		for endpoint: Endpoint in endpoints:
			checksum += network.available_tracks_for(endpoint, tracks).size()
	print("NETWORK_PERF c2_batch_avg_ms=", (Time.get_ticks_usec() - started) / 100000.0, " checksum=", checksum)
	network.free()
	for endpoint: Endpoint in endpoints:
		endpoint.free()
	quit()
