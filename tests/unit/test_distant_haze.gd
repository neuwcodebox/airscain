extends GutTest

func test_haze_is_world_based_and_preserves_close_materials() -> void:
	var contact := add_child_autofree(Node3D.new()) as Node3D
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.5, 0.7, 1.0)
	mesh.material_override = material
	contact.add_child(mesh)
	var haze := DistantContactHaze.new()
	contact.add_child(haze)
	contact.position = Vector3(5400, 100, 0)
	haze.configure(contact, 2400.0)
	assert_eq(haze.opacity, 0.0)
	assert_ne(mesh.material_override, material)
	assert_eq((mesh.material_override as StandardMaterial3D).albedo_color.a, 0.0)
	assert_eq(material.albedo_color.a, 1.0, "공유 원본을 바꾸지 않습니다")
	contact.position = Vector3(3500, 1000, 0)
	haze.refresh()
	assert_gt(haze.opacity, 0.0)
	assert_lt(haze.opacity, 1.0)
	contact.position = Vector3(100, 100, 0)
	haze.refresh()
	assert_same(mesh.material_override, material, "근거리에서는 원래 불투명 재질을 복원합니다")
	mesh.hide()
	contact.position = Vector3(3500, 100, 0)
	haze.refresh()
	assert_false(mesh.visible, "투발로 숨긴 무장을 다시 표시하지 않습니다")

func test_haze_follows_radius_independent_of_altitude_and_heading() -> void:
	for radius: float in [1900.0, 3500.0, 5400.0]:
		var expected := DistantContactHaze.opacity_at(Vector3(radius, 0, 0), 2400.0)
		assert_almost_eq(DistantContactHaze.opacity_at(Vector3(0, 1800, -radius), 2400.0), expected, 0.0001)
	assert_gt(DistantContactHaze.opacity_at(Vector3(3000, 0, 0), 2400.0), DistantContactHaze.opacity_at(Vector3(4000, 0, 0), 2400.0))
