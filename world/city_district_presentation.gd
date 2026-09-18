class_name CityDistrictPresentation
extends RefCounted
## Builds the visual identity shared by authored city districts.

const ROAD_WIDTH := 13.0
const ROAD_SEGMENT_LENGTH := 6.0
const ROAD_SURFACE_OFFSET := 0.55

var landmark_count: int = 0
var arterial_segment_count: int = 0

var _generator: WorldGenerator
var _boxes: CityBoxBatch

func build(districts: Array[CityDistrict], primary: CityDistrict, generator: WorldGenerator, boxes: CityBoxBatch) -> void:
	landmark_count = 0
	arterial_segment_count = 0
	_generator = generator
	_boxes = boxes
	if primary == null:
		return
	for district: CityDistrict in districts:
		_build_landmark(district)
		if district != primary:
			_build_arterial(primary, district)

func _build_arterial(from_district: CityDistrict, to_district: CityDistrict) -> void:
	var direction := to_district.center - from_district.center
	var distance := direction.length()
	if distance <= 0.0:
		return
	direction /= distance
	var start := from_district.center + direction * from_district.definition.size * 0.36
	var end := to_district.center - direction * to_district.definition.size * 0.36
	var connection_length := start.distance_to(end)
	if connection_length <= 1.0:
		return
	var road_material := _material(Color("3e4141"), 0.96)
	var segment_count := maxi(1, ceili(connection_length / ROAD_SEGMENT_LENGTH))
	var yaw := atan2(direction.x, direction.y)
	for segment_index: int in segment_count:
		var from_2d := start.lerp(end, float(segment_index) / float(segment_count))
		var to_2d := start.lerp(end, float(segment_index + 1) / float(segment_count))
		var midpoint := from_2d.lerp(to_2d, 0.5)
		var height := _generator.height_at(midpoint.x, midpoint.y)
		if height <= _generator.sea_level + 0.5:
			continue
		_add_box(Vector3(ROAD_WIDTH, 0.35, from_2d.distance_to(to_2d) + 0.8), Vector3(midpoint.x, height + ROAD_SURFACE_OFFSET, midpoint.y), road_material, yaw)
		arterial_segment_count += 1

func _build_landmark(district: CityDistrict) -> void:
	var center := Vector3(district.center.x, _generator.height_at(district.center.x, district.center.y), district.center.y)
	var yaw := deg_to_rad(district.definition.rotation_degrees)
	match district.definition.role:
		CityDistrictDefinition.Role.CORE:
			_add_box(Vector3(38.0, 0.4, 38.0), center + Vector3.UP * 0.2, _material(Color("aaa28e"), 0.9), yaw)
		CityDistrictDefinition.Role.RESIDENTIAL:
			_add_box(Vector3(38.0, 0.35, 32.0), center + Vector3.UP * 0.18, _material(Color("68805f"), 0.9), yaw)
			_add_box(Vector3(14.0, 5.0, 10.0), center + Vector3.UP * 2.7, _material(Color("d6c7a5"), 0.85), yaw)
		CityDistrictDefinition.Role.INDUSTRIAL:
			_add_box(Vector3(48.0, 0.4, 38.0), center + Vector3.UP * 0.2, _material(Color("575c5d"), 0.9), yaw)
			var industrial_material := _material(Color("765f4e"), 0.82)
			_add_box(Vector3(30.0, 8.0, 17.0), center + Vector3.UP * 4.2, industrial_material, yaw)
			var chimney_offset := Basis(Vector3.UP, yaw) * Vector3(18.0, 0.0, -9.0)
			_add_box(Vector3(3.5, 24.0, 3.5), center + chimney_offset + Vector3.UP * 12.2, industrial_material, yaw)
		CityDistrictDefinition.Role.TRANSPORT:
			_add_box(Vector3(72.0, 0.35, 20.0), center + Vector3.UP * 0.18, _material(Color("454b4f"), 0.9), yaw)
			var terminal_offset := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 16.0)
			_add_box(Vector3(44.0, 6.0, 12.0), center + terminal_offset + Vector3.UP * 3.2, _material(Color("82939a"), 0.78), yaw)
	landmark_count += 1

func _add_box(size: Vector3, position: Vector3, material: StandardMaterial3D, yaw: float) -> void:
	_boxes.add_box(Transform3D(Basis(Vector3.UP, yaw).scaled(size), position), material)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
