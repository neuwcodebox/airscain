extends GutTest

var camera: Camera3D
var parent: Node3D
var picker: PlacementController

func before_each() -> void:
	parent = add_child_autofree(Node3D.new()) as Node3D
	camera = Camera3D.new()
	parent.add_child(camera)
	camera.position = Vector3(0, 80, 120)
	camera.look_at(Vector3.ZERO)
	picker = PlacementController.new()
	parent.add_child(picker)
	picker.set_process(false)
	picker.camera = camera
	picker.defense_parent = parent

func _unit(position: Vector3) -> DefenseUnit:
	var unit := DefenseUnit.new()
	parent.add_child(unit)
	unit.position = position
	var model := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10, 18, 10)
	model.mesh = box
	model.position.y = 9
	unit.add_child(model)
	unit.pointer_target = AssetPointerTarget.new()
	unit.pointer_target.prepare(unit)
	return unit

func test_model_and_padded_margin_are_pickable_above_ground() -> void:
	var unit := _unit(Vector3(0, 35, 0))
	var rect := unit.pointer_target.screen_rect(unit, camera)
	assert_same(picker.asset_at_screen(rect.get_center()), unit)
	assert_same(picker.asset_at_screen(Vector2(rect.end.x + 7, rect.get_center().y)), unit)
	assert_null(picker.asset_at_screen(rect.end + Vector2.ONE * 30))

func test_distant_target_keeps_clickable_pixel_area_and_vertical_view() -> void:
	var unit := _unit(Vector3.ZERO)
	camera.position = Vector3(0, 1800, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var center := unit.pointer_target.screen_rect(unit, camera).get_center()
	assert_same(picker.asset_at_screen(center + Vector2(15, 0)), unit)

func test_nearby_assets_and_hover_do_not_change_selection() -> void:
	var first := _unit(Vector3(-10, 0, 0))
	var second := _unit(Vector3(10, 0, 0))
	watch_signals(picker)
	var center := second.pointer_target.screen_rect(second, camera).get_center()
	assert_same(picker.asset_at_screen(center), second)
	picker.set_hovered_asset(first)
	assert_true(first.pointer_target.hovered)
	picker.set_hovered_asset(second)
	assert_false(first.pointer_target.hovered)
	assert_true(second.pointer_target.hovered)
	assert_signal_not_emitted(picker, "asset_selected")
	picker.set_hovered_asset(null)
	assert_null(second.pointer_target.meshes[0].material_overlay)

func test_hidden_and_deleted_targets_are_not_picked() -> void:
	var unit := _unit(Vector3.ZERO)
	var center := unit.pointer_target.screen_rect(unit, camera).get_center()
	unit.hide()
	assert_null(picker.asset_at_screen(center))
	unit.show()
	picker.set_hovered_asset(unit)
	unit.queue_free()
	assert_null(picker.asset_at_screen(center))
	await get_tree().process_frame
	picker.set_hovered_asset(null)
	assert_null(picker.hovered_asset)

func test_rotated_model_uses_current_visible_bounds() -> void:
	var unit := _unit(Vector3.ZERO)
	var model := unit.pointer_target.meshes[0]
	model.position = Vector3(18, 9, 0)
	model.rotation.z = PI * 0.5
	var center := unit.pointer_target.screen_rect(unit, camera).get_center()
	assert_same(picker.asset_at_screen(center), unit)
