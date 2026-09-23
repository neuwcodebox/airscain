class_name HarborPort
extends Node3D

const UNLOAD_SECONDS := 18.0
const EMERGENCY_REPAIR_SECONDS := 180.0
const IDENTITY_MARKER_SCENE := preload("res://effects/unit_identity_marker/unit_identity_marker.tscn")
const IDENTITY_ICON := preload("res://ui/icons/asset_harbor.svg")
const IDENTITY_COLOR := UnitIdentityMarker.SENSOR_COLOR

signal struck

var route: HarborRoute
var shipping_routes: Array[HarborRoute] = []
var maximum_inbound: float
var maximum_outbound: float
var haze_size: float
var session: GameSession
var ships: Dictionary[int, CargoShip] = {}
var crane_trolleys: Array[Node3D] = []
var crane_cables: Array[MeshInstance3D] = []
var crane_loads: Array[MeshInstance3D] = []
var crane_spreaders: Array[MeshInstance3D] = []
var repair_visual: HarborRepairVisual
var identity_marker: UnitIdentityMarker
var damage_point := Vector3(0, 4.3, -23)
var dispatch_shed: MeshInstance3D
var alarm_beacons: Array[MeshInstance3D] = []
var closed_from: float = INF
var closed_until: float = 0.0
var delivery_outcomes: Dictionary[int, bool] = {}

var operational: bool:
	get: return session == null or _operational_at(session.survival_time)

func configure(field: Battlefield, session_value: GameSession) -> bool:
	route = HarborRoute.plan(field)
	if route == null:
		return false
	shipping_routes = route.variants(field)
	haze_size = field.battlefield_size
	for shipping_route: HarborRoute in shipping_routes:
		maximum_inbound = maxf(maximum_inbound, shipping_route.inbound_duration)
		maximum_outbound = maxf(maximum_outbound, shipping_route.outbound_duration)
	session = session_value
	var orientation := Basis(Vector3(route.along_quay.x, 0.0, route.along_quay.y), Vector3.UP, Vector3(route.seaward.x, 0.0, route.seaward.y))
	global_transform = Transform3D(orientation, Vector3(route.berth.x, route.sea_level, route.berth.y))
	_build_port()
	identity_marker = IDENTITY_MARKER_SCENE.instantiate() as UnitIdentityMarker
	identity_marker.name = "HarborIdentityMarker"
	identity_marker.position = Vector3(0.0, 26.0, -25.0)
	add_child(identity_marker)
	identity_marker.configure(IDENTITY_ICON, 0, IDENTITY_COLOR)
	identity_marker.icon.scale = Vector3.ONE * 1.25
	repair_visual = HarborRepairVisual.new()
	add_child(repair_visual)
	session.regular_support_due.connect(_on_regular_support_due)
	update_at_time(session.survival_time)
	return true

func update_at_time(time_seconds: float) -> void:
	if route == null or session == null:
		return
	var first := maxi(1, floori((time_seconds - maximum_outbound) / session.support_interval) - 1)
	var last := ceili((time_seconds + maximum_inbound + UNLOAD_SECONDS) / session.support_interval) + 1
	var active: Dictionary[int, bool] = {}
	var unloading_fraction := -1.0
	for index: int in range(first, last + 1):
		var voyage := shipping_routes[index % shipping_routes.size()]
		var delivery_time := float(index) * session.support_interval
		var arrival_time := delivery_time - UNLOAD_SECONDS
		var entry_time := arrival_time - voyage.inbound_duration
		var exit_time := delivery_time + voyage.outbound_duration
		if time_seconds < entry_time or time_seconds >= exit_time:
			continue
		active[index] = true
		var ship: CargoShip = ships.get(index)
		if ship == null:
			ship = CargoShip.new()
			ship.name = "Freighter%d" % index
			ship.top_level = true
			add_child(ship)
			ship.configure_haze(haze_size)
			ships[index] = ship
		var pose: Transform3D
		var underway := true
		var cargo_remaining := 1.0
		var delivery_available: bool = delivery_outcomes.get(index, _operational_at(delivery_time))
		if time_seconds < arrival_time:
			pose = voyage.inbound_pose(time_seconds - entry_time)
		elif time_seconds < delivery_time:
			pose = voyage.inbound_pose(voyage.inbound_duration)
			underway = false
			if _operational_at(time_seconds) and delivery_available:
				unloading_fraction = (time_seconds - arrival_time) / UNLOAD_SECONDS
				cargo_remaining = 1.0 - unloading_fraction
		else:
			pose = voyage.outbound_pose(time_seconds - delivery_time)
			cargo_remaining = 0.0 if delivery_available else 1.0
		ship.global_transform = pose
		ship.position.y += 0.35 * sin(time_seconds * 0.72 + float(index) * 1.7) if underway else 0.08 * sin(time_seconds * 0.4)
		ship.refresh_haze()
		ship.set_underway(underway)
		ship.set_cargo_remaining(cargo_remaining)
	for index: int in ships.keys():
		if active.has(index):
			continue
		ships[index].queue_free()
		ships.erase(index)
	for index: int in delivery_outcomes.keys():
		if index < first:
			delivery_outcomes.erase(index)
	repair_visual.update_at_time(time_seconds, closed_from, closed_until, damage_point, closed_until - EMERGENCY_REPAIR_SECONDS)
	var repairing := not _operational_at(time_seconds)
	identity_marker.set_condition(not repairing, false)
	identity_marker.set_progress((time_seconds - closed_from) / maxf(closed_until - closed_from, 0.001) if repairing else 0.0, repairing)
	_animate_crane(unloading_fraction)
	if dispatch_shed != null:
		(dispatch_shed.material_override as StandardMaterial3D).albedo_color = Color("c5b694") if _operational_at(time_seconds) else Color("6c5c57")
	for beacon: MeshInstance3D in alarm_beacons:
		beacon.visible = not _operational_at(time_seconds) and floori(time_seconds * 2.0) % 2 == 0

func _operational_at(time_seconds: float) -> bool:
	return time_seconds < closed_from or time_seconds >= closed_until

func strike_target() -> Vector3:
	return to_global(Vector3(0.0, 4.0, -23.0))

func try_apply_impact(amount: int, global_impact_position: Vector3) -> bool:
	var local := to_local(global_impact_position)
	if absf(local.x) > 88.0 or absf(local.y) > 30.0 or local.z < -58.0 or local.z > 8.0:
		return false
	if amount <= 0:
		return true
	if operational:
		closed_from = session.survival_time
	closed_until = maxf(closed_until, session.survival_time + EMERGENCY_REPAIR_SECONDS)
	damage_point = Vector3(clampf(local.x, -74, 74), 4.3, clampf(local.z, -34, -20))
	update_at_time(session.survival_time)
	struck.emit()
	return true

func capture_state() -> Dictionary:
	var outcomes: Array[Dictionary] = []
	var indices := delivery_outcomes.keys()
	indices.sort()
	for index: int in indices:
		outcomes.append({"index": index, "delivered": delivery_outcomes[index]})
	return {"closed_from": closed_from if is_finite(closed_from) else -1.0, "closed_until": closed_until, "deliveries": outcomes, "damage_point": [damage_point.x, damage_point.z]}

static func state_validation_error(state: Dictionary) -> String:
	var from_value: Variant = state.get("closed_from")
	var until_value: Variant = state.get("closed_until")
	if not (from_value is int or from_value is float) or not (until_value is int or until_value is float):
		return "항구 복구 시간이 올바르지 않습니다"
	var start := float(from_value)
	var finish := float(until_value)
	if not is_finite(start) or not is_finite(finish) or (start != -1.0 and (start < 0.0 or finish <= start)) or finish < 0.0:
		return "항구 복구 시간이 올바르지 않습니다"
	if state.has("damage_point"):
		var point: Variant = state.damage_point
		if not point is Array or point.size() != 2:
			return "항구 피해 위치가 올바르지 않습니다"
		for value: Variant in point:
			if not (value is int or value is float) or not is_finite(float(value)):
				return "항구 피해 위치가 올바르지 않습니다"
		if absf(float(point[0])) > 74.0 or float(point[1]) < -34.0 or float(point[1]) > -20.0:
			return "항구 피해 위치가 올바르지 않습니다"
	var outcomes: Variant = state.get("deliveries")
	if not outcomes is Array or outcomes.size() > 32:
		return "항구 배송 기록이 올바르지 않습니다"
	var seen: Dictionary[int, bool] = {}
	for value: Variant in outcomes:
		if not value is Dictionary or not value.get("index") is int or not value.get("delivered") is bool:
			return "항구 배송 기록이 올바르지 않습니다"
		var index := int(value.index)
		if index < 1 or seen.has(index):
			return "항구 배송 기록이 올바르지 않습니다"
		seen[index] = true
	return ""

func restore_state(state: Dictionary) -> void:
	if not state_validation_error(state).is_empty():
		return
	var restored_from := float(state.closed_from)
	var restored_until := float(state.closed_until)
	closed_from = restored_from if restored_from >= 0.0 else INF
	closed_until = restored_until
	var point: Array = state.get("damage_point", [0.0, -23.0])
	damage_point = Vector3(float(point[0]), 4.3, float(point[1]))
	delivery_outcomes.clear()
	for value: Dictionary in state.deliveries:
		delivery_outcomes[int(value.index)] = bool(value.delivered)
	update_at_time(session.survival_time)

func _on_regular_support_due(amount: int, scheduled_time: float) -> void:
	var delivered := _operational_at(scheduled_time)
	delivery_outcomes[roundi(scheduled_time / session.support_interval)] = delivered
	if delivered:
		session.grant_regular_support(amount)

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.78
	return material

func _box(name_value: String, size: Vector3, position_value: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var item := MeshInstance3D.new()
	item.name = name_value
	item.mesh = mesh
	item.material_override = material
	item.position = position_value
	(parent if parent != null else self).add_child(item)
	return item

func _build_port() -> void:
	var geometry := HarborGeometry.new()
	geometry.box(Vector3(170, 4, 28), Vector3(0, 2, -26), "92958a")
	geometry.box(Vector3(116, 4, 38), Vector3(0, 2, -59), "92958a")
	geometry.box(Vector3(24, 3, 110), Vector3(0, 1.8, -125), "92958a")
	geometry.box(Vector3(166, 0.15, 25), Vector3(0, 4.08, -26), "586362")
	geometry.box(Vector3(112, 0.15, 35), Vector3(0, 4.08, -59), "65716b")
	geometry.box(Vector3(20, 0.15, 98), Vector3(0, 3.36, -125), "586362")
	# Working quay: capstones, fenders, mooring bollards, crane rails and painted lanes.
	for index: int in 22:
		var x := -82.0 + index * 7.8
		geometry.box(Vector3(7.5, 0.35, 1.1), Vector3(x, 4.23, -12.5), "c3c0a8")
		if index % 2 == 0:
			geometry.box(Vector3(1.7, 3, 0.9), Vector3(x, 1.5, -11.5), "303d40")
			geometry.cylinder(0.48, 0.85, Vector3(x, 4.7, -14.1), "bca069")
			geometry.beam(Vector3(x - 0.8, 5.1, -14.1), Vector3(x + 0.8, 5.1, -14.1), 0.3, "bca069")
	for z: float in [-17.0, -33.0]:
		geometry.box(Vector3(154, 0.16, 0.2), Vector3(0, 4.25, z), "b4b8b0")
	for index: int in 17:
		geometry.box(Vector3(4, 0.03, 0.25), Vector3(-76 + index * 9, 4.18, -38), "d2bd80")
	for index: int in 11:
		geometry.box(Vector3(0.25, 0.03, 4), Vector3(0, 3.46, -80 - index * 8), "d2bd80")
	for side: float in [-1.0, 1.0]:
		for index: int in 8:
			var z := -82.0 - index * 12.0
			geometry.cylinder(0.9, 12, Vector3(side * 9, -3, z), "777f76")
			geometry.beam(Vector3(side * 11, 3.3, z), Vector3(side * 11, 4.8, z), 0.16, "bdc1b2")
		geometry.beam(Vector3(side * 11, 4.8, -78), Vector3(side * 11, 4.8, -177), 0.16, "bdc1b2")
		_build_crane(geometry, side * 19)
	# Yard stacks sit on the widened concrete apron, with space for the access lane.
	var container_mesh := HarborGeometry.container_mesh()
	for side: float in [-1.0, 1.0]:
		for row: int in 3:
			for lane: int in 4:
				for level: int in (2 if lane < 3 else 1):
					var at := Vector3(side * (18 + lane * 9), 5.5 + level * 2.65, -47 - row * 9)
					var tint: String = ["a26a4b", "607d82", "a9a083", "6a7b70"][(row + lane + level) % 4]
					for surface: int in container_mesh.get_surface_count():
						if not geometry.surfaces.has(tint):
							var buffer := SurfaceTool.new()
							buffer.begin(Mesh.PRIMITIVE_TRIANGLES)
							geometry.surfaces[tint] = buffer
						geometry.surfaces[tint].append_from(container_mesh, surface, Transform3D(Basis(Vector3.UP, PI / 2), at))
	# Dispatch office, roller doors, roof seams, vents and glazed frontage.
	dispatch_shed = _box("DispatchShed", Vector3(16, 6, 13), Vector3(0, 6.6, -145), _material(Color("c5b694")))
	geometry.box(Vector3(18, 0.45, 15), Vector3(0, 9.85, -145), "566c70")
	for index: int in 9:
		geometry.box(Vector3(0.12, 0.15, 15), Vector3(-8 + index * 2, 10.15, -145), "84928b")
	for x: float in [-4.5, 4.5]:
		geometry.box(Vector3(5, 3.8, 0.1), Vector3(x, 5.6, -138.4), "778783")
		for row: int in 6:
			geometry.box(Vector3(5, 0.06, 0.13), Vector3(x, 4.0 + row * 0.6, -138.3), "a3aaa0")
	geometry.box(Vector3(9, 1, 0.14), Vector3(0, 8.5, -138.4), "334c55")
	for x: float in [-3.0, 3.0]:
		geometry.box(Vector3(2, 1.2, 2.2), Vector3(x, 10.6, -146), "b4b8ac")
	# Yard floodlight poles and housings remain legible at tactical zoom.
	for x: float in [-73.0, 73.0]:
		geometry.beam(Vector3(x, 4, -32), Vector3(x, 19, -32), 0.35, "798d89")
		geometry.box(Vector3(4, 0.5, 1.4), Vector3(x, 19, -32), "d5d1b7")
	geometry.instance(self, "TerminalStructure")

func _build_crane(geometry: HarborGeometry, x: float) -> void:
	var paint := "b9a675"
	var dark := "596e70"
	for side: float in [-1.0, 1.0]:
		for z: float in [-17.0, -33.0]:
			geometry.box(Vector3(5.5, 1.5, 1.8), Vector3(x + side * 6, 5, z), dark)
			geometry.beam(Vector3(x + side * 6, 5.5, z), Vector3(x + side * 4, 28, z), 0.85, paint)
		geometry.beam(Vector3(x + side * 6, 8, -17), Vector3(x + side * 4, 27, -33), 0.4, paint)
		geometry.beam(Vector3(x + side * 6, 8, -33), Vector3(x + side * 4, 27, -17), 0.4, paint)
		geometry.beam(Vector3(x + side * 4, 28, -33), Vector3(x + side * 4, 40, -26), 0.6, paint)
		geometry.beam(Vector3(x + side * 4, 40, -26), Vector3(x + side * 4, 28, 9), 0.16, dark)
		geometry.beam(Vector3(x + side * 4, 40, -26), Vector3(x + side * 4, 28, -49), 0.16, dark)
		geometry.beam(Vector3(x + side * 4, 28, -49), Vector3(x + side * 4, 28, 10), 0.65, paint)
		geometry.beam(Vector3(x + side * 4, 30, -49), Vector3(x + side * 4, 30, 10), 0.45, paint)
		for segment: int in 12:
			var z := -49.0 + segment * 4.9
			geometry.beam(Vector3(x + side * 4, 28, z), Vector3(x + side * 4, 30, z + 4.9), 0.22, paint)
	for z: float in [-33.0, -17.0, 8.0]:
		geometry.beam(Vector3(x - 4, 28, z), Vector3(x + 4, 28, z), 0.75, paint)
	geometry.box(Vector3(7, 3.5, 8), Vector3(x, 30, -38), dark)
	geometry.box(Vector3(3, 3, 3.5), Vector3(x + 5, 26, -18), "cfcead")
	geometry.box(Vector3(3.1, 1.3, 0.12), Vector3(x + 5, 26.3, -16.2), "365463")
	var beacon := _box("CraneAlarm", Vector3(1.1, 1.0, 1.1), Vector3(x, 40, -26), _material(Color("ff5239")))
	var material := beacon.material_override as StandardMaterial3D
	material.emission_enabled = true
	material.emission = Color("ff5239")
	material.emission_energy_multiplier = 2.0
	beacon.visible = false
	alarm_beacons.append(beacon)
	var trolley := Node3D.new()
	trolley.position = Vector3(x, 27, -18)
	add_child(trolley)
	crane_trolleys.append(trolley)
	_box("Trolley", Vector3(7, 1.0, 2.5), Vector3.ZERO, _material(Color(dark)), trolley)
	var cable_geometry := HarborGeometry.new()
	for side: float in [-1.0, 1.0]:
		cable_geometry.beam(Vector3(side * 2.5, 0, 0), Vector3(side * 2.5, -1, 0), 0.08, "303e42")
	crane_cables.append(cable_geometry.instance(trolley, "HoistCables"))
	var spreader := _box("Spreader", Vector3(6.3, 0.45, 2.6), Vector3(0, -10, 0), _material(Color("c0a35a")), trolley)
	crane_spreaders.append(spreader)
	var load := MeshInstance3D.new()
	load.mesh = HarborGeometry.container_mesh()
	load.rotation.y = PI / 2
	load.position.y = -1.55
	spreader.add_child(load)
	crane_loads.append(load)

func _animate_crane(fraction: float) -> void:
	for index: int in crane_trolleys.size():
		var working := fraction >= 0.0 and operational
		var cycle := fposmod(fraction * 3.0 + float(index) * 0.5, 1.0) if working else 0.0
		var outward := smoothstep(0.2, 0.45, cycle)
		var returning := smoothstep(0.7, 0.95, cycle)
		crane_trolleys[index].position.z = lerpf(0, -45, outward - returning) if working else -18.0
		var height := 20.0
		if working:
			height -= 9.0 * (1.0 - smoothstep(0.0, 0.2, cycle))
			height -= 12.0 * sin(PI * clampf((cycle - 0.45) / 0.25, 0.0, 1.0))
		crane_cables[index].scale.y = 27.0 - height
		crane_spreaders[index].position.y = height - 27.0
		crane_loads[index].visible = working and cycle < 0.58
