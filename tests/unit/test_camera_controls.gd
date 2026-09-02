extends GutTest

const CAMERA_SCENE := preload("res://camera/camera_rig.tscn")
const TACTICAL_SCREEN_OVERLAY := preload("res://ui/tactical_screen_overlay.gd")

var rig: CameraRig

func before_each() -> void:
	rig = add_child_autofree(CAMERA_SCENE.instantiate()) as CameraRig
	await get_tree().process_frame

func after_each() -> void:
	Input.action_release("camera_right")
	Input.action_release("camera_rotate_right")

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

func test_mouse_wheel_does_not_zoom_over_registered_ui_region() -> void:
	var blocker := Control.new()
	blocker.position = Vector2(40.0, 30.0)
	blocker.size = Vector2(200.0, 160.0)
	add_child_autofree(blocker)
	rig.exclude_wheel_input_over(blocker)
	var initial_zoom := rig.zoom_distance
	var zoom_out := InputEventMouseButton.new()
	zoom_out.button_index = MOUSE_BUTTON_WHEEL_DOWN
	zoom_out.pressed = true
	zoom_out.position = Vector2(100.0, 100.0)
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

func test_rotation_actions_orbit_camera_and_keep_pan_screen_relative() -> void:
	var initial_camera_position := rig.camera.position
	Input.action_press("camera_rotate_right")
	rig._process(1.0)
	Input.action_release("camera_rotate_right")
	assert_almost_eq(rad_to_deg(rig.yaw_radians), rig.rotation_speed_degrees, 0.01)
	assert_ne(rig.camera.position, initial_camera_position)
	var initial_rig_position := rig.global_position
	Input.action_press("camera_right")
	rig._process(0.25)
	Input.action_release("camera_right")
	assert_lt(rig.global_position.z, initial_rig_position.z)

func test_right_mouse_drag_rotates_camera() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	rig._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(25.0, 4.0)
	rig._unhandled_input(motion)
	assert_almost_eq(rig.yaw_radians, -25.0 * rig.rotation_drag_speed, 0.001)
	assert_eq(rig.global_position, Vector3.ZERO)

func test_battlefield_configuration_keeps_distant_ocean_visible() -> void:
	rig.configure_for_battlefield(2400.0)
	assert_eq(rig.bounds, 1080.0)
	assert_eq(rig.camera.far, 14400.0)

func test_focus_moves_rig_to_clamped_world_position() -> void:
	rig.bounds = 500.0
	rig.focus_on(Vector3(720.0, 80.0, -240.0))
	assert_eq(rig.global_position, Vector3(500.0, 0.0, -240.0))

func test_offscreen_marker_stays_inside_viewport_margin() -> void:
	var position: Vector2 = TACTICAL_SCREEN_OVERLAY.marker_position(Vector2(1600.0, -200.0), Vector2(1280.0, 720.0), false, 42.0)
	assert_between(position.x, 42.0, 1238.0)
	assert_between(position.y, 42.0, 678.0)
	assert_almost_eq(position.y, 42.0, 0.01)

func test_tactical_marker_uses_the_full_viewport_edge() -> void:
	var viewport_size := Vector2(1600.0, 900.0)
	var position: Vector2 = TACTICAL_SCREEN_OVERLAY.tactical_marker_position(Vector2(2200.0, 500.0), viewport_size, false)
	assert_lte(position.x, viewport_size.x - TACTICAL_SCREEN_OVERLAY.EDGE_MARGIN)
	assert_between(position.y, TACTICAL_SCREEN_OVERLAY.EDGE_MARGIN, viewport_size.y - TACTICAL_SCREEN_OVERLAY.EDGE_MARGIN)
	assert_almost_eq(position.x, 1558.0, 0.01)
