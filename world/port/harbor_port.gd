class_name HarborPort
extends Node3D

const UNLOAD_SECONDS := 18.0
const EMERGENCY_REPAIR_SECONDS := 180.0

signal struck

var route: HarborRoute
var session: GameSession
var ships: Dictionary[int, CargoShip] = {}
var crane_hook: Node3D
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
	session = session_value
	var orientation := Basis(Vector3(route.along_quay.x, 0.0, route.along_quay.y), Vector3.UP, Vector3(route.seaward.x, 0.0, route.seaward.y))
	global_transform = Transform3D(orientation, Vector3(route.berth.x, route.sea_level, route.berth.y))
	_build_port()
	session.regular_support_due.connect(_on_regular_support_due)
	update_at_time(session.survival_time)
	return true

func update_at_time(time_seconds: float) -> void:
	if route == null or session == null:
		return
	var first := maxi(1, floori((time_seconds - route.outbound_duration) / session.support_interval) - 1)
	var last := ceili((time_seconds + route.inbound_duration + UNLOAD_SECONDS) / session.support_interval) + 1
	var active: Dictionary[int, bool] = {}
	var unloading_fraction := -1.0
	for index: int in range(first, last + 1):
		var delivery_time := float(index) * session.support_interval
		var arrival_time := delivery_time - UNLOAD_SECONDS
		var entry_time := arrival_time - route.inbound_duration
		var exit_time := delivery_time + route.outbound_duration
		if time_seconds < entry_time or time_seconds >= exit_time:
			continue
		active[index] = true
		var ship: CargoShip = ships.get(index)
		if ship == null:
			ship = CargoShip.new()
			ship.name = "Freighter%d" % index
			ship.top_level = true
			add_child(ship)
			ships[index] = ship
		var pose: Transform3D
		var underway := true
		var cargo_remaining := 1.0
		var delivery_available: bool = delivery_outcomes.get(index, _operational_at(delivery_time))
		if time_seconds < arrival_time:
			pose = route.inbound_pose(time_seconds - entry_time)
		elif time_seconds < delivery_time:
			pose = route.inbound_pose(route.inbound_duration)
			underway = false
			if _operational_at(time_seconds) and delivery_available:
				unloading_fraction = (time_seconds - arrival_time) / UNLOAD_SECONDS
				cargo_remaining = 1.0 - unloading_fraction
		else:
			pose = route.outbound_pose(time_seconds - delivery_time)
			cargo_remaining = 0.0 if delivery_available else 1.0
		ship.global_transform = pose
		ship.position.y += 0.35 * sin(time_seconds * 0.72 + float(index) * 1.7) if underway else 0.08 * sin(time_seconds * 0.4)
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
	struck.emit()
	return true

func capture_state() -> Dictionary:
	var outcomes: Array[Dictionary] = []
	var indices := delivery_outcomes.keys()
	indices.sort()
	for index: int in indices:
		outcomes.append({"index": index, "delivered": delivery_outcomes[index]})
	return {"closed_from": closed_from if is_finite(closed_from) else -1.0, "closed_until": closed_until, "deliveries": outcomes}

static func state_validation_error(state: Dictionary) -> String:
	var from_value: Variant = state.get("closed_from")
	var until_value: Variant = state.get("closed_until")
	if not (from_value is int or from_value is float) or not (until_value is int or until_value is float):
		return "항구 복구 시간이 올바르지 않습니다"
	var start := float(from_value)
	var finish := float(until_value)
	if not is_finite(start) or not is_finite(finish) or (start != -1.0 and (start < 0.0 or finish <= start)) or finish < 0.0:
		return "항구 복구 시간이 올바르지 않습니다"
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
	var concrete := _material(Color("9c9d93"))
	var asphalt := _material(Color("505c5b"))
	var steel := _material(Color("667b7d"), 0.32)
	var cream := _material(Color("c5b694"))
	_box("Quay", Vector3(170.0, 4.0, 26.0), Vector3(0.0, 2.0, -25.0), concrete)
	_box("AccessPier", Vector3(24.0, 3.0, 148.0), Vector3(0.0, 1.8, -102.0), concrete)
	_box("Apron", Vector3(150.0, 0.3, 21.0), Vector3(0.0, 4.1, -25.0), asphalt)
	for side: int in [-1, 1]:
		var x := float(side) * 72.0
		_box("Bollard%d" % side, Vector3(2.4, 2.2, 2.4), Vector3(x, 5.2, -12.0), steel)
		_box("CraneTower%d" % side, Vector3(5.2, 33.0, 5.2), Vector3(x * 0.64, 20.5, -29.0), steel)
		_box("CraneBoom%d" % side, Vector3(3.2, 2.7, 56.0), Vector3(x * 0.64, 37.0, -4.0), steel)
		_box("CraneCab%d" % side, Vector3(5.0, 4.0, 6.0), Vector3(x * 0.64, 35.0, -27.0), cream)
		var beacon := _box("CraneAlarm%d" % side, Vector3(3.6, 2.8, 3.6), Vector3(x * 0.64, 39.9, -29.0), _material(Color("ff5239")))
		var alarm_material := beacon.material_override as StandardMaterial3D
		alarm_material.emission_enabled = true
		alarm_material.emission = Color("ff5239")
		alarm_material.emission_energy_multiplier = 2.0
		beacon.visible = false
		alarm_beacons.append(beacon)
	dispatch_shed = _box("DispatchShed", Vector3(18.0, 7.0, 15.0), Vector3(0.0, 7.2, -145.0), cream)
	_box("DispatchRoof", Vector3(20.0, 0.8, 17.0), Vector3(0.0, 11.1, -145.0), steel)
	for index: int in 8:
		var x := -51.0 + float(index % 4) * 18.0
		var z := -54.0 - float(index / 4) * 10.0
		_box("YardContainer%d" % index, Vector3(13.0, 3.0, 5.0), Vector3(x, 5.8, z), _material(Color("a87d55") if index % 2 == 0 else Color("597e85")))
	crane_hook = Node3D.new()
	crane_hook.name = "MovingCargoHook"
	add_child(crane_hook)
	_box("SuspendedContainer", Vector3(8.0, 2.8, 4.0), Vector3.ZERO, _material(Color("b46548")), crane_hook)
	crane_hook.visible = false

func _animate_crane(fraction: float) -> void:
	if crane_hook == null:
		return
	crane_hook.visible = fraction >= 0.0 and operational
	if not crane_hook.visible:
		return
	var cycle := fposmod(fraction * 3.0, 1.0)
	var progress := smoothstep(0.05, 0.45, cycle)
	var retreat := smoothstep(0.55, 0.95, cycle)
	crane_hook.position = Vector3(-46.0, 14.0 + 8.0 * sin(cycle * PI), lerpf(9.0, -22.0, progress - retreat))
