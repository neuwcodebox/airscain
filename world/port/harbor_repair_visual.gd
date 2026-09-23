class_name HarborRepairVisual
extends Node3D
## Reconstructed from operation time, including pause and save restoration.
var damage: Node3D
var crew: Node3D
var truck: Node3D
var smoke: Array[MeshInstance3D] = []
var sparks: Node3D
var arc: OmniLight3D

func _ready() -> void:
	damage = Node3D.new()
	add_child(damage)
	var debris := HarborGeometry.new()
	debris.cylinder(7.0, 0.04, Vector3(0, 0.03, 0), "343b37")
	for index: int in 13:
		var angle := float(index) * 2.4
		var radius := 1.0 + float(index % 4) * 1.5
		debris.box(Vector3(1.5 + index % 3, 0.5 + (index % 2) * 0.6, 1.1), Vector3(cos(angle) * radius, 0.5, sin(angle) * radius * 0.65), "66695d", Basis.from_euler(Vector3(0.1, angle, 0.22)))
	for side: float in [-1.0, 1.0]:
		debris.beam(Vector3(side * 4, 0.3, -2), Vector3(side * 1, 2.4, 1), 0.35, "424e4b")
	debris.instance(damage, "ScorchAndRubble")
	for index: int in 20:
		var puff := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		puff.mesh = mesh
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = preload("res://effects/smoke_card_texture.tres")
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		material.billboard_keep_scale = true
		material.roughness = 1.0
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		damage.add_child(puff)
		puff.top_level = true
		smoke.append(puff)
	crew = Node3D.new()
	add_child(crew)
	var work := HarborGeometry.new()
	for side: float in [-1.0, 1.0]:
		for x: float in [-5.0, 5.0]:
			work.box(Vector3(0.2, 1.6, 0.2), Vector3(x, 0.8, side * 5), "b8af87")
		work.box(Vector3(10.5, 0.5, 0.18), Vector3(0, 1.2, side * 5), "dcad50")
		for stripe: int in 6:
			work.box(Vector3(0.6, 0.52, 0.2), Vector3(-4.5 + stripe * 1.8, 1.2, side * 5), "414841")
	for x: float in [-3.0, 3.0]:
		for leg: float in [-0.22, 0.22]:
			work.box(Vector3(0.25, 0.85, 0.35), Vector3(x + leg, 0.45, 2), "3b5056")
		work.box(Vector3(0.85, 0.75, 0.45), Vector3(x, 1.2, 2), "d5a646")
		work.cylinder(0.3, 0.35, Vector3(x, 1.8, 2), "ddd0a4")
		work.beam(Vector3(x, 1.3, 2), Vector3(x * 0.75, 0.7, 0.7), 0.22, "847b61")
	work.box(Vector3(1.7, 1.4, 1.2), Vector3(5, 0.7, 1), "99774b")
	work.beam(Vector3(5, 0.15, 1), Vector3(2, 0.15, 0.7), 0.12, "303a38")
	work.instance(crew, "RepairCrewAndBarriers")
	truck = Node3D.new()
	add_child(truck)
	var vehicle := HarborGeometry.new()
	vehicle.box(Vector3(2.5, 0.6, 6.5), Vector3(0, 0.8, 0), "384747")
	vehicle.box(Vector3(2.4, 1.7, 2.0), Vector3(0, 1.9, -2), "c59b50")
	vehicle.box(Vector3(2.15, 0.7, 0.1), Vector3(0, 2.15, -3.04), "3e6068")
	vehicle.box(Vector3(2.3, 1.2, 3.7), Vector3(0, 1.65, 1.05), "b7b7a0")
	for side: float in [-1.0, 1.0]:
		for z: float in [-2.0, 2.0]:
			vehicle.box(Vector3(0.45, 1.1, 1.1), Vector3(side * 1.25, 0.65, z), "303a39")
	vehicle.box(Vector3(1.5, 0.25, 0.3), Vector3(0, 2.9, -2), "e0a444")
	vehicle.instance(truck, "MaintenanceTruck")
	sparks = Node3D.new()
	crew.add_child(sparks)
	var spark_geometry := HarborGeometry.new()
	for index: int in 9:
		var angle := float(index) * 2.4
		spark_geometry.beam(Vector3(2.0, 0.65, 0.7), Vector3(2.0 + cos(angle) * 1.8, 0.7 + float(index % 3) * 0.5, 0.7 + sin(angle)), 0.06, "ffe3a2")
	var rays := spark_geometry.instance(sparks, "WeldingSparks")
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffe6b3")
	glow.emission_enabled = true
	glow.emission = Color("ffd098")
	glow.emission_energy_multiplier = 4.0
	rays.material_override = glow
	arc = OmniLight3D.new()
	arc.position = Vector3(2, 1, 0.7)
	arc.light_color = Color("a4d9ff")
	arc.omni_range = 7.0
	sparks.add_child(arc)
	visible = false

func update_at_time(time: float, start: float, finish: float, point: Vector3, impact_time: float = -INF) -> void:
	visible = is_finite(start) and time >= start and time < finish
	if not visible:
		return
	var age := time - start
	var smoke_age := time - maxf(start, impact_time)
	var remaining := finish - time
	damage.position = point
	crew.position = point
	var activity := smoothstep(0.0, 8.0, remaining)
	var intensity := (1.0 - smoothstep(10.0, 100.0, smoke_age)) * activity
	for index: int in smoke.size():
		var puff := smoke[index]
		var phase := fposmod(smoke_age + float(index) * 0.9, 18.0) / 18.0
		puff.visible = smoke_age >= float(index) * 0.2 and intensity > 0.001
		puff.global_position = damage.to_global(Vector3(phase * 9 + sin(float(index) * 2.4) * 1.8, 1.5 + phase * 30, phase * 3))
		var size := lerpf(6.0, 16.0, phase)
		var camera := get_viewport().get_camera_3d()
		puff.global_basis = (camera.global_basis if camera != null else Basis.IDENTITY).scaled(Vector3.ONE * size)
		var material := puff.material_override as StandardMaterial3D
		material.albedo_color = Color(0.055 + phase * 0.06, 0.06 + phase * 0.06, 0.065 + phase * 0.06, sin(PI * phase) * 0.95 * intensity)
	var parking := Vector3(clampf(point.x + 9, -78, 78), point.y, -32)
	var corner := Vector3(0, point.y, -39)
	var turn_start := corner - Vector3(0, 0, 12)
	var origin := Vector3(0, point.y, -122)
	if age < 10.0:
		truck.position = origin.lerp(turn_start, smoothstep(0.0, 10.0, age))
		truck.rotation.y = PI
	else:
		var t := smoothstep(10.0, 20.0, age)
		truck.position = (1 - t) * (1 - t) * turn_start + 2 * (1 - t) * t * corner + t * t * parking
		var heading := (corner - turn_start) * (1 - t) + (parking - corner) * t
		truck.basis = Basis.looking_at(heading)
	crew.visible = age >= 20.0
	sparks.visible = crew.visible and remaining > 8.0 and sin(age * 13) > 0.1 and fposmod(age, 5.0) < 3.2
	arc.light_energy = 2.5
