extends GutTest

const CAMERA_SCENE := preload("res://camera/camera_rig.tscn")

var rig: CameraRig

func before_each() -> void:
	rig = add_child_autofree(CAMERA_SCENE.instantiate()) as CameraRig
	await get_tree().process_frame

func after_each() -> void:
	Input.action_release("camera_right")

func test_wasd_action_moves_camera_rig() -> void:
	var initial_position := rig.global_position
	Input.action_press("camera_right")
	rig._process(0.5)
	Input.action_release("camera_right")
	assert_gt(rig.global_position.x, initial_position.x)

func test_mouse_wheel_changes_zoom_within_limits() -> void:
	var initial_zoom := rig.zoom_distance
	var zoom_in := InputEventMouseButton.new()
	zoom_in.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_in.pressed = true
	rig._unhandled_input(zoom_in)
	assert_lt(rig.zoom_distance, initial_zoom)
	var zoom_out := InputEventMouseButton.new()
	zoom_out.button_index = MOUSE_BUTTON_WHEEL_DOWN
	zoom_out.pressed = true
	rig._unhandled_input(zoom_out)
	assert_eq(rig.zoom_distance, initial_zoom)

func test_middle_mouse_drag_pans_camera() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	rig._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20.0, -10.0)
	rig._unhandled_input(motion)
	assert_ne(rig.global_position, Vector3.ZERO)

func test_battlefield_configuration_keeps_distant_ocean_visible() -> void:
	rig.configure_for_battlefield(2400.0)
	assert_eq(rig.bounds, 1080.0)
	assert_eq(rig.camera.far, 14400.0)
