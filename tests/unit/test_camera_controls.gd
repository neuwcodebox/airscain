extends GutTest

const CAMERA_SCENE := preload("res://camera/camera_rig.tscn")
const TACTICAL_SCREEN_OVERLAY := preload("res://ui/tactical_screen_overlay.gd")
const TEST_ACTIONS: Array[StringName] = [&"camera_right", &"camera_rotate_right"]

var rig: CameraRig
var previous_action_strengths: Dictionary[StringName, float] = {}

func before_each() -> void:
	previous_action_strengths.clear()
	for action: StringName in TEST_ACTIONS:
		previous_action_strengths[action] = Input.get_action_strength(action)
		Input.action_release(action)
	rig = add_child_autofree(CAMERA_SCENE.instantiate()) as CameraRig

func after_each() -> void:
	for action: StringName in TEST_ACTIONS:
		Input.action_release(action)
		if previous_action_strengths[action] > 0.0:
			Input.action_press(action, previous_action_strengths[action])

func test_wasd_action_moves_camera_rig() -> void:
	var initial_position := rig.global_position
	Input.action_press("camera_right")
	_advance_camera_input(0.5)
	Input.action_release("camera_right")
	assert_gt(rig.global_position.x, initial_position.x)

func test_lens_preserves_center_framing_and_reduces_near_far_size_difference() -> void:
	rig.configure_for_battlefield(2400.0)
	var lens := rig.camera.fov
	var center_width := _projected_width(0.0)
	var near_far_ratio := _projected_width(500.0) / _projected_width(-500.0)
	var distance := rig.camera.position.length()
	rig.camera.fov = 52.0
	_refresh_camera_geometry()
	assert_lt(lens, rig.camera.fov)
	assert_gt(distance, rig.camera.position.length())
	assert_almost_eq(center_width, _projected_width(0.0), 0.01)
	assert_lt(near_far_ratio, _projected_width(500.0) / _projected_width(-500.0))

func _projected_width(z: float) -> float:
	return rig.camera.unproject_position(Vector3(100, 0, z)).distance_to(rig.camera.unproject_position(Vector3(0, 0, z)))

func test_mouse_wheel_changes_zoom_within_limits() -> void:
	var initial_zoom := rig.zoom_distance
	var zoom_in := InputEventMouseButton.new()
	zoom_in.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_in.pressed = true
	_send_camera_input(zoom_in)
	assert_lt(rig.zoom_distance, initial_zoom)
	var zoom_out := InputEventMouseButton.new()
	zoom_out.button_index = MOUSE_BUTTON_WHEEL_DOWN
	zoom_out.pressed = true
	_send_camera_input(zoom_out)
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
	_send_camera_input(zoom_out)
	assert_eq(rig.zoom_distance, initial_zoom)

func test_middle_mouse_drag_rotates_both_axes_without_panning() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	_send_camera_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20.0, -10.0)
	_send_camera_input(motion)
	assert_eq(rig.global_position, Vector3.ZERO)
	assert_almost_eq(rig.yaw_radians, -20.0 * rig.rotation_drag_speed, 0.001)
	assert_lt(rig.pitch_radians, CameraRig.DEFAULT_PITCH)

func test_rotation_action_orbits_camera() -> void:
	var initial_camera_position := rig.camera.position
	Input.action_press("camera_rotate_right")
	_advance_camera_input(1.0)
	Input.action_release("camera_rotate_right")
	assert_almost_eq(rad_to_deg(rig.yaw_radians), rig.rotation_speed_degrees, 0.01)
	assert_ne(rig.camera.position, initial_camera_position)

func test_pan_remains_screen_relative_after_rotation() -> void:
	Input.action_press("camera_rotate_right")
	_advance_camera_input(1.0)
	Input.action_release("camera_rotate_right")
	var initial_rig_position := rig.global_position
	Input.action_press("camera_right")
	_advance_camera_input(0.25)
	Input.action_release("camera_right")
	assert_lt(rig.global_position.z, initial_rig_position.z)

func test_right_mouse_drag_does_not_rotate_camera() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	_send_camera_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(25.0, 4.0)
	_send_camera_input(motion)
	assert_eq(rig.yaw_radians, 0.0)
	assert_eq(rig.global_position, Vector3.ZERO)

func test_vertical_drag_clamps_at_both_pitch_limits() -> void:
	rig.rotating = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0, 10000)
	_send_camera_input(motion)
	assert_eq(rig.pitch_radians, PI / 2.0)
	assert_almost_eq(rig.camera.global_basis.z.dot(Vector3.UP), 1.0, 0.0001)
	motion.relative = Vector2(0, -10000)
	_send_camera_input(motion)
	assert_eq(rig.pitch_radians, CameraRig.MINIMUM_PITCH)

func test_top_down_view_remains_finite_and_yaw_relative() -> void:
	rig.pitch_radians = PI / 2.0
	for yaw: float in [0.0, 0.7, PI, TAU]:
		rig.yaw_radians = yaw
		_refresh_camera_geometry()
		assert_true(rig.camera.global_basis.is_finite(), "yaw %.3f의 top-down basis" % yaw)
		assert_almost_eq(rig.camera.global_basis.determinant(), 1.0, 0.0001, "yaw %.3f의 정규 직교 basis" % yaw)
		assert_almost_eq(rig.camera.global_basis.x.dot(Vector3.RIGHT.rotated(Vector3.UP, yaw)), 1.0, 0.0001, "yaw %.3f의 화면 오른쪽 축" % yaw)

func test_reset_restores_position_zoom_and_both_angles() -> void:
	rig.configure_for_battlefield(2400.0)
	var default_position := rig.camera.position
	rig.focus_on(Vector3(200, 0, -300))
	rig.zoom_distance = rig.minimum_zoom
	rig.yaw_radians = 1.3
	rig.pitch_radians = PI / 2.0
	var reset := InputEventKey.new()
	reset.physical_keycode = KEY_BACKSPACE
	reset.pressed = true
	_send_camera_input(reset)
	assert_eq(rig.global_position, Vector3.ZERO)
	assert_eq(rig.zoom_distance, rig.default_zoom_distance)
	assert_eq(rig.yaw_radians, 0.0)
	assert_eq(rig.pitch_radians, CameraRig.DEFAULT_PITCH)
	assert_almost_eq(rig.camera.position.distance_to(default_position), 0.0, 0.001)

func test_camera_clears_terrain_during_movement_rotation_and_zoom() -> void:
	rig.configure_for_battlefield(2400.0, func(x: float, z: float) -> float: return 180.0 + absf(x) * 0.1 + absf(z) * 0.1)
	for pitch: float in [CameraRig.MINIMUM_PITCH, CameraRig.DEFAULT_PITCH, PI / 2.0]:
		for yaw: float in [0.0, 1.2, PI]:
			rig.pitch_radians = pitch
			rig.yaw_radians = yaw
			rig.zoom_distance = rig.minimum_zoom
			rig.focus_on(Vector3(800, 0, -800))
			var position := rig.camera.global_position
			assert_gte(position.y, float(rig.terrain_height.call(position.x, position.z)) + CameraRig.TERRAIN_CLEARANCE)
			assert_true(rig.camera.global_basis.is_finite())

func test_sky_tilt_preserves_safe_position_and_crosses_horizon_continuously() -> void:
	rig.configure_for_battlefield(2400.0, func(_x: float, _z: float) -> float: return 240.0)
	rig.zoom_distance = rig.minimum_zoom
	rig.pitch_radians = CameraRig.MINIMUM_ORBIT_PITCH
	_refresh_camera_geometry()
	var safe_position := rig.camera.global_position
	var previous_direction := -rig.camera.global_basis.z
	var maximum_position_error := 0.0
	var maximum_direction_step := 0.0
	var lowest_height := INF
	for step: int in 150:
		rig.pitch_radians = lerpf(CameraRig.MINIMUM_ORBIT_PITCH, CameraRig.MINIMUM_PITCH, float(step + 1) / 150.0)
		_refresh_camera_geometry()
		var direction := -rig.camera.global_basis.z
		maximum_position_error = maxf(maximum_position_error, rig.camera.global_position.distance_to(safe_position))
		maximum_direction_step = maxf(maximum_direction_step, direction.angle_to(previous_direction))
		lowest_height = minf(lowest_height, rig.camera.global_position.y)
		previous_direction = direction
	assert_lt(maximum_position_error, 0.001, "지평선 위로 기울여도 안전한 카메라 위치를 유지합니다")
	assert_lt(maximum_direction_step, 0.04, "지평선 통과 중 시선 방향이 튀지 않습니다")
	assert_gte(lowest_height, 240.0 + CameraRig.TERRAIN_CLEARANCE)
	assert_gt(previous_direction.y, 0.8, "Middle drag can look well above the horizon")
	rig.pitch_radians = 0.0
	_refresh_camera_geometry()
	assert_almost_eq(rig.camera.global_basis.z.y, 0.0, 0.001)

func test_middle_release_over_ui_stops_rotation() -> void:
	rig.rotating = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	_send_ui_input(release)
	assert_false(rig.rotating)

func test_focus_loss_stops_rotation() -> void:
	rig.rotating = true
	rig.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_false(rig.rotating)

func test_blocked_camera_ignores_reset_and_rotation() -> void:
	rig.focus_on(Vector3(100, 0, 50))
	rig.input_blocked = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_BACKSPACE
	key.pressed = true
	_send_camera_input(key)
	assert_eq(rig.global_position, Vector3(100, 0, 50))

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
	assert_almost_eq(position.x, 1580.0, 0.01)

func _advance_camera_input(delta: float) -> void:
	# Camera actions consume frame delta; direct callback advancement keeps tests deterministic.
	rig._process(delta)

func _send_camera_input(event: InputEvent) -> void:
	# This is the engine-facing input boundary used for unhandled gameplay controls.
	rig._unhandled_input(event)

func _send_ui_input(event: InputEvent) -> void:
	# Releases over UI arrive through the general input callback.
	rig._input(event)

func _refresh_camera_geometry() -> void:
	# The public focus operation applies direct test changes to exported camera state.
	rig.focus_on(rig.global_position)
