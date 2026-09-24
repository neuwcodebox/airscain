extends Node3D
## Airframe proportions are authored by each content scene, independent of AI.
## Part materials carry relative tone rather than final color: runtime paint
## multiplies it, so canopies, undersides, radomes and markings stay distinct
## under each threat's identifying color.

@export_enum("propeller", "jet", "delta", "cruise", "ballistic", "rocket") var shape: String = "propeller"
@export var armed: bool = false

static var _geometry: Dictionary[String, Array] = {}
static var _store_mesh: ArrayMesh
static var _store_material: StandardMaterial3D

var _skin: StandardMaterial3D
var _panel: StandardMaterial3D
var _underside: StandardMaterial3D
var _dark: StandardMaterial3D
var _glass: StandardMaterial3D
var _marking: StandardMaterial3D

func _ready() -> void:
	var variant := "%s|%s" % [shape, armed]
	if _geometry.has(variant):
		_install_geometry(_geometry[variant])
		_install_stores()
		return
	_skin = ModelGeometry.material(Color(0.92, 0.92, 0.92), 0.35, 0.55)
	_panel = ModelGeometry.material(Color(0.78, 0.78, 0.8), 0.35, 0.5)
	_underside = ModelGeometry.material(Color(0.56, 0.57, 0.6), 0.3, 0.6)
	_dark = ModelGeometry.material(Color(0.2, 0.21, 0.23), 0.45, 0.45)
	_glass = ModelGeometry.material(Color(0.1, 0.16, 0.21), 0.6, 0.15)
	_marking = ModelGeometry.material(Color(1.0, 0.98, 0.94), 0.0, 0.8)
	match shape:
		"jet":
			_build_jet()
		"delta":
			_build_delta()
		"cruise":
			_build_cruise()
		"ballistic":
			_build_ballistic()
		"rocket":
			_build_rocket()
		_:
			_build_propeller()
	if armed:
		for side: float in [-1.0, 1.0]:
			ModelGeometry.box(self, "WeaponPylon", Vector3(0.35, 0.8, 1.2), Vector3(side * 3.5, -0.5, 0.6), _dark)
	var parts: Array[MeshInstance3D] = []
	for child: Node in get_children():
		if child is MeshInstance3D:
			var part := child as MeshInstance3D
			var finish := part.get_active_material(0) as StandardMaterial3D
			if finish != null and not finish.emission_enabled:
				parts.append(part)
	var combined := ModelGeometry.combine_static_parts(parts)
	combined = [TintedMeshPalette.combine(combined)]
	_geometry[variant] = combined
	for part: MeshInstance3D in parts:
		part.free()
	_install_geometry(combined)
	_install_stores()

## Medium-altitude propeller UAV: bulged satcom nose, long tapered wing,
## V-tail with ventral fin, sensor ball and a three-blade pusher.
func _build_propeller() -> void:
	ModelGeometry.mesh(self, "Fuselage", ModelGeometry.hull([Vector3(0.03, 0.03, -6.9), Vector3(0.55, 0.5, -6.3), Vector3(0.85, 0.85, -5.1), Vector3(0.95, 1.05, -3.6), Vector3(0.9, 0.85, -1.0), Vector3(0.75, 0.7, 1.6), Vector3(0.45, 0.45, 3.9), Vector3(0.22, 0.24, 5.0), Vector3(0.03, 0.03, 5.2)], 10), Vector3.ZERO, _skin)
	ModelGeometry.mesh(self, "Belly", ModelGeometry.hull([Vector3(0.03, 0.03, -4.8), Vector3(0.7, 0.35, -3.6), Vector3(0.7, 0.35, 1.0), Vector3(0.03, 0.03, 2.4)]), Vector3(0.0, -0.55, 0.0), _underside)
	for side: float in [-1.0, 1.0]:
		var wing := ModelGeometry.mesh(self, "LongWing", ModelGeometry.wing(PackedVector2Array([Vector2(0.6, -0.9), Vector2(8.2, 0.25), Vector2(8.1, 1.25), Vector2(0.6, 1.6)]), 0.2), Vector3(0.0, 0.15, 0.0), _skin)
		wing.scale.x = side
		wing.rotation.z = side * deg_to_rad(3.0)
		var winglet := ModelGeometry.mesh(self, "Winglet", ModelGeometry.wing(PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.9, 0.8), Vector2(0.9, 1.25), Vector2(0.0, 1.25)]), 0.1), Vector3(side * 8.15, 0.55, 0.0), _panel)
		winglet.rotation.z = side * deg_to_rad(80.0)
		winglet.scale.x = side
		ModelGeometry.box(self, "WingMark", Vector3(0.9, 0.04, 1.0), Vector3(side * 5.6, 0.3, 0.6), _marking)
		ModelGeometry.box(self, "Aileron", Vector3(2.6, 0.05, 0.35), Vector3(side * 6.0, 0.28, 1.3), _panel)
		var tail := ModelGeometry.mesh(self, "Tailplane", ModelGeometry.wing(PackedVector2Array([Vector2(0.3, 3.8), Vector2(3.1, 4.9), Vector2(2.9, 5.7), Vector2(0.3, 5.3)]), 0.16), Vector3(0.0, 0.35, 0.0), _skin)
		tail.scale.x = side
		tail.rotation.z = side * deg_to_rad(40.0)
	var ventral := ModelGeometry.mesh(self, "VentralFin", ModelGeometry.wing(PackedVector2Array([Vector2(0.0, 3.6), Vector2(1.4, 4.7), Vector2(1.4, 5.2), Vector2(0.0, 5.0)]), 0.14), Vector3(0.0, -0.2, 0.0), _panel)
	ventral.rotation.z = -PI * 0.5
	ModelGeometry.box(self, "EngineIntake", Vector3(0.55, 0.35, 1.4), Vector3(0.0, 0.72, 1.9), _dark)
	ModelGeometry.cylinder(self, "SensorMount", 0.25, 0.4, Vector3(0.0, -0.95, -4.6), _dark)
	ModelGeometry.mesh(self, "OpticalTurret", _ball(0.5), Vector3(0.0, -1.25, -4.6), _glass)
	_propeller(Vector3(0.0, 0.0, 5.35), 1.7, 3)

## Twin-engine strike jet: dark radome, leading-edge extensions, twin canted fins.
func _build_jet() -> void:
	ModelGeometry.mesh(self, "Radome", ModelGeometry.hull([Vector3(0.02, 0.02, -10.3), Vector3(0.55, 0.48, -8.6), Vector3(0.9, 0.75, -6.0)], 10), Vector3.ZERO, _dark)
	ModelGeometry.mesh(self, "FacetedFuselage", ModelGeometry.hull([Vector3(0.9, 0.75, -6.0), Vector3(1.8, 1.3, -2.0), Vector3(2.1, 1.2, 4.0), Vector3(1.5, 0.85, 8.0), Vector3(0.02, 0.02, 8.1)], 10), Vector3.ZERO, _skin)
	ModelGeometry.mesh(self, "Belly", ModelGeometry.hull([Vector3(0.02, 0.02, -5.0), Vector3(1.6, 0.5, -2.0), Vector3(1.9, 0.5, 4.0), Vector3(0.02, 0.02, 7.0)]), Vector3(0.0, -0.75, 0.0), _underside)
	ModelGeometry.mesh(self, "Cockpit", ModelGeometry.hull([Vector3(0.02, 0.02, -6.0), Vector3(0.65, 0.9, -4.0), Vector3(0.7, 0.7, -1.5), Vector3(0.02, 0.02, -0.5)]), Vector3(0.0, 0.85, 0.0), _glass)
	ModelGeometry.box(self, "CanopyFrame", Vector3(1.3, 0.12, 0.18), Vector3(0.0, 1.62, -3.1), _dark)
	ModelGeometry.box(self, "DorsalSpine", Vector3(0.8, 0.35, 5.5), Vector3(0.0, 1.25, 2.0), _panel)
	for side: float in [-1.0, 1.0]:
		var wing := ModelGeometry.mesh(self, "SweptWing", ModelGeometry.wing(PackedVector2Array([Vector2(0.6, -2.8), Vector2(10.5, 3.0), Vector2(9.7, 5.4), Vector2(1.0, 3.3)]), 0.2), Vector3.ZERO, _skin)
		wing.scale.x = side
		var lex := ModelGeometry.mesh(self, "LeadingEdgeExtension", ModelGeometry.wing(PackedVector2Array([Vector2(0.8, -6.4), Vector2(2.3, -2.6), Vector2(2.3, -1.0), Vector2(0.8, -1.0)]), 0.14), Vector3(0.0, 0.25, 0.0), _skin)
		lex.scale.x = side
		ModelGeometry.box(self, "WingtipRail", Vector3(0.18, 0.18, 2.6), Vector3(side * 10.2, 0.0, 4.2), _dark)
		ModelGeometry.box(self, "Flap", Vector3(4.0, 0.05, 0.6), Vector3(side * 4.6, 0.12, 4.0), _panel)
		var tail := ModelGeometry.mesh(self, "Tailplane", ModelGeometry.wing(PackedVector2Array([Vector2(0.5, 4.0), Vector2(4.4, 6.0), Vector2(3.7, 7.4), Vector2(0.3, 6.5)]), 0.16), Vector3(0.0, 0.4, 0.0), _skin)
		tail.scale.x = side
		tail.rotation.z = side * deg_to_rad(5.0)
		ModelGeometry.box(self, "WingMark", Vector3(0.7, 0.035, 1.1), Vector3(side * 7.0, 0.13, 2.8), _marking)
		var intake := ModelGeometry.mesh(self, "AirIntake", ModelGeometry.hull([Vector3(0.02, 0.02, -3.3), Vector3(0.65, 0.65, -3.0), Vector3(0.7, 0.6, 4.0), Vector3(0.02, 0.02, 4.2)]), Vector3(side * 1.8, -0.65, 0.0), _underside)
		intake.scale = Vector3.ONE
		ModelGeometry.box(self, "IntakeMouth", Vector3(1.2, 1.1, 0.12), Vector3(side * 1.8, -0.65, -3.05), _dark)
		var fin := ModelGeometry.mesh(self, "TwinFin", ModelGeometry.wing(PackedVector2Array([Vector2(0.0, 3.8), Vector2(3.6, 6.0), Vector2(3.3, 7.6), Vector2(0.0, 7.3)]), 0.18), Vector3(side * 1.3, 0.7, 0.0), _skin)
		fin.rotation.z = side * deg_to_rad(73.0)
		fin.scale.x = side
		ModelGeometry.box(self, "FinMark", Vector3(0.05, 0.8, 1.0), Vector3(side * 2.2, 3.4, 6.6), _marking)
		var nozzle := ModelGeometry.cylinder(self, "ExhaustNozzle", 0.74, 1.3, Vector3(side * 1.25, 0.0, 7.9), _dark)
		nozzle.rotation.x = PI * 0.5

## Small delta-wing loitering munition with tip fins and a pusher propeller.
func _build_delta() -> void:
	ModelGeometry.mesh(self, "Fuselage", ModelGeometry.hull([Vector3(0.02, 0.02, -2.0), Vector3(0.3, 0.26, -1.6), Vector3(0.48, 0.4, -0.7), Vector3(0.48, 0.4, 1.0), Vector3(0.32, 0.3, 1.6), Vector3(0.05, 0.05, 1.8)], 8), Vector3.ZERO, _skin)
	ModelGeometry.mesh(self, "Warhead", ModelGeometry.hull([Vector3(0.02, 0.02, -2.05), Vector3(0.22, 0.2, -1.75), Vector3(0.3, 0.26, -1.6)], 8), Vector3.ZERO, _dark)
	for side: float in [-1.0, 1.0]:
		var wing := ModelGeometry.mesh(self, "DeltaWing", ModelGeometry.wing(PackedVector2Array([Vector2(0.3, -1.3), Vector2(2.1, 1.1), Vector2(2.1, 1.5), Vector2(0.3, 1.5)]), 0.08), Vector3.ZERO, _skin)
		wing.scale.x = side
		var tip := ModelGeometry.mesh(self, "TipFin", ModelGeometry.wing(PackedVector2Array([Vector2(-0.3, 0.8), Vector2(0.45, 1.3), Vector2(0.45, 1.55), Vector2(-0.3, 1.55)]), 0.05), Vector3(side * 2.1, 0.0, 0.0), _panel)
		tip.rotation.z = side * PI * 0.5
		tip.scale.x = side
		ModelGeometry.box(self, "WingMark", Vector3(0.45, 0.03, 0.4), Vector3(side * 1.3, 0.06, 0.9), _marking)
	ModelGeometry.box(self, "Belly", Vector3(0.5, 0.12, 1.8), Vector3(0.0, -0.38, 0.2), _underside)
	_propeller(Vector3(0.0, 0.0, 1.9), 0.7, 2)

## Subsonic cruise missile: seeker nose, mid-body wings, belly intake, cross tail.
func _build_cruise() -> void:
	ModelGeometry.mesh(self, "MissileBody", ModelGeometry.hull([Vector3(0.5, 0.5, -7.1), Vector3(0.85, 0.85, -6.3), Vector3(1.0, 1.0, -5.2), Vector3(1.0, 1.0, 4.2), Vector3(0.85, 0.85, 5.4), Vector3(0.6, 0.6, 5.8)], 12), Vector3.ZERO, _skin)
	ModelGeometry.mesh(self, "Seeker", ModelGeometry.hull([Vector3(0.02, 0.02, -7.65), Vector3(0.35, 0.35, -7.4), Vector3(0.52, 0.52, -7.08)], 12), Vector3.ZERO, _dark)
	ModelGeometry.mesh(self, "Belly", ModelGeometry.hull([Vector3(0.02, 0.02, -4.5), Vector3(0.9, 0.3, -3.0), Vector3(0.9, 0.3, 3.0), Vector3(0.02, 0.02, 4.4)]), Vector3(0.0, -0.8, 0.0), _underside)
	ModelGeometry.box(self, "Intake", Vector3(0.8, 0.55, 2.0), Vector3(0.0, -1.1, 2.6), _panel)
	ModelGeometry.box(self, "IntakeMouth", Vector3(0.62, 0.38, 0.1), Vector3(0.0, -1.1, 1.58), _dark)
	for side: float in [-1.0, 1.0]:
		var wing := ModelGeometry.mesh(self, "Wing", ModelGeometry.wing(PackedVector2Array([Vector2(0.8, -0.9), Vector2(4.3, 0.5), Vector2(4.2, 1.3), Vector2(0.8, 1.2)]), 0.14), Vector3(0.0, -0.3, 0.0), _skin)
		wing.scale.x = side
	for index: int in 4:
		var fin := ModelGeometry.mesh(self, "TailFin", ModelGeometry.wing(PackedVector2Array([Vector2(0.8, 3.7), Vector2(2.1, 4.8), Vector2(2.1, 5.4), Vector2(0.8, 5.5)]), 0.12), Vector3.ZERO, _panel)
		fin.rotation.z = PI * 0.25 + float(index) * PI * 0.5
	_band(-5.0, 1.02, 0.25)
	_band(0.2, 1.02, 0.18)
	var nozzle := ModelGeometry.cylinder(self, "Nozzle", 0.55, 0.5, Vector3(0.0, 0.0, 5.95), _dark)
	nozzle.rotation.x = PI * 0.5

## Short-range ballistic missile: reentry-vehicle cone, stage band, base fins.
func _build_ballistic() -> void:
	ModelGeometry.mesh(self, "MissileBody", ModelGeometry.hull([Vector3(1.1, 1.1, -3.6), Vector3(1.1, 1.1, 4.9), Vector3(1.0, 1.0, 5.5)], 12), Vector3.ZERO, _skin)
	ModelGeometry.mesh(self, "ReentryVehicle", ModelGeometry.hull([Vector3(0.05, 0.05, -8.0), Vector3(0.4, 0.4, -7.1), Vector3(0.8, 0.8, -5.4), Vector3(1.1, 1.1, -3.6)], 12), Vector3.ZERO, _dark)
	_band(-3.5, 1.13, 0.3)
	_band(0.6, 1.13, 0.22)
	_band(3.2, 1.13, 0.22)
	for index: int in 4:
		var fin := ModelGeometry.mesh(self, "BaseFin", ModelGeometry.wing(PackedVector2Array([Vector2(1.0, 3.4), Vector2(2.3, 4.6), Vector2(2.3, 5.4), Vector2(1.0, 5.4)]), 0.14), Vector3.ZERO, _panel)
		fin.rotation.z = float(index) * PI * 0.5
	ModelGeometry.mesh(self, "NozzleBell", ModelGeometry.hull([Vector3(0.55, 0.55, 5.4), Vector3(0.85, 0.85, 6.2)], 12), Vector3.ZERO, _dark)

## Artillery rocket: slender tube, dark nose, wrap-around tail fins.
func _build_rocket() -> void:
	ModelGeometry.mesh(self, "MissileBody", ModelGeometry.hull([Vector3(0.58, 0.58, -3.5), Vector3(0.58, 0.58, 4.6), Vector3(0.5, 0.5, 5.1)], 10), Vector3.ZERO, _skin)
	ModelGeometry.mesh(self, "Nose", ModelGeometry.hull([Vector3(0.03, 0.03, -5.3), Vector3(0.3, 0.3, -4.6), Vector3(0.58, 0.58, -3.5)], 10), Vector3.ZERO, _dark)
	_band(-3.4, 0.6, 0.18)
	_band(3.3, 0.6, 0.12)
	for index: int in 4:
		var fin := ModelGeometry.mesh(self, "TailFin", ModelGeometry.wing(PackedVector2Array([Vector2(0.5, 3.6), Vector2(1.5, 4.2), Vector2(1.5, 5.0), Vector2(0.5, 5.0)]), 0.08), Vector3.ZERO, _panel)
		fin.rotation.z = PI * 0.25 + float(index) * PI * 0.5

func _band(z: float, radius: float, width: float) -> void:
	var band := ModelGeometry.cylinder(self, "Band", radius, width, Vector3(0.0, 0.0, z), _marking)
	band.rotation.x = PI * 0.5

func _propeller(hub: Vector3, radius: float, blades: int) -> void:
	ModelGeometry.mesh(self, "Spinner", ModelGeometry.hull([Vector3(0.22, 0.22, hub.z - 0.2), Vector3(0.2, 0.2, hub.z + 0.1), Vector3(0.02, 0.02, hub.z + 0.45)]), Vector3(hub.x, hub.y, 0.0), _dark)
	for index: int in blades:
		var blade := ModelGeometry.box(self, "PropellerBlade", Vector3(0.22, radius, 0.06), Vector3.ZERO, _dark)
		var angle := TAU * float(index) / float(blades) + 0.3
		blade.basis = Basis(Vector3.BACK, angle) * Basis(Vector3.UP, 0.35)
		blade.position = hub + Basis(Vector3.BACK, angle) * Vector3(0.0, radius * 0.5, 0.0)

func _ball(radius: float) -> SphereMesh:
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	return ball

func _install_stores() -> void:
	if not armed:
		return
	if _store_mesh == null:
		_store_mesh = ModelGeometry.hull([Vector3(0.02, 0.02, -2.6), Vector3(0.4, 0.4, -1.5), Vector3(0.4, 0.4, 1.8), Vector3(0.1, 0.1, 2.1)])
		_store_material = ModelGeometry.material(Color("414b48"), 0.3)
	for side: float in [-1.0, 1.0]:
		ModelGeometry.mesh(self, "ReleasedStore" if side > 0.0 else "ReserveStore", _store_mesh, Vector3(side * 3.5, -1.1, 0.2), _store_material)

func set_weapon_released(released: bool) -> void:
	var store := get_node_or_null("ReleasedStore") as MeshInstance3D
	if store != null:
		store.visible = not released

func _install_geometry(shapes: Array) -> void:
	for index: int in shapes.size():
		var geometry := shapes[index] as ArrayMesh
		ModelGeometry.mesh(self, "Airframe" if index == 0 else "Airframe%d" % index, geometry, Vector3.ZERO, geometry.surface_get_material(0))
