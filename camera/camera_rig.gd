class_name CameraRig
extends Node3D

@export var pan_speed: float = 260.0
@export var zoom_step: float = 55.0
@export var minimum_zoom: float = 180.0
@export var maximum_zoom: float = 1200.0
@export var rotation_speed_degrees: float = 90.0
@export var rotation_drag_speed: float = 0.006

const DEFAULT_PITCH := atan(0.72)
const MINIMUM_PITCH := -PI / 3.0
const MINIMUM_ORBIT_PITCH := PI / 15.0
const MAXIMUM_PITCH := PI / 2.0
const TERRAIN_CLEARANCE := 12.0
const ORBIT_SCALE := sqrt(1.0 + 0.72 * 0.72)
const ZOOM_HALF_SPAN := ORBIT_SCALE * tan(deg_to_rad(26.0))

var rotating: bool = false
var zoom_distance: float = 680.0
var bounds: float = 810.0
var yaw_radians: float = 0.0
var pitch_radians: float = DEFAULT_PITCH
var default_zoom_distance: float = 680.0
var terrain_height: Callable
var wheel_input_exclusions: Array[Control] = []
var input_blocked: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var preferences: PlayerSettings = PlayerSettings.instance()

func _ready() -> void:
	_update_camera()

func configure_for_battlefield(battlefield_size: float, height_query: Callable = Callable()) -> void:
	terrain_height = height_query
	bounds = battlefield_size * 0.45
	maximum_zoom = battlefield_size * 0.67
	zoom_distance = clampf(battlefield_size * 0.38, minimum_zoom, maximum_zoom)
	default_zoom_distance = zoom_distance
	camera.far = battlefield_size * 6.0
	_update_camera()

func reset_view() -> void:
	rotating = false
	global_position = Vector3.ZERO
	yaw_radians = 0.0
	pitch_radians = DEFAULT_PITCH
	zoom_distance = default_zoom_distance
	_update_camera()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		rotating = false

func _input(event: InputEvent) -> void:
	# Release also reaches us over UI, where unhandled mouse events do not.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		rotating = false

func focus_on(world_position: Vector3) -> void:
	global_position.x = world_position.x
	global_position.z = world_position.z
	_clamp_position()

func exclude_wheel_input_over(control: Control) -> void:
	if control != null and not wheel_input_exclusions.has(control):
		wheel_input_exclusions.append(control)

func _process(delta: float) -> void:
	if input_blocked:
		rotating = false
		return
	var rotation_input := Input.get_axis("camera_rotate_left", "camera_rotate_right")
	if not is_zero_approx(rotation_input):
		yaw_radians += deg_to_rad(rotation_speed_degrees) * rotation_input * delta * float(preferences.values.rotation)
		_update_camera()
	var input_vector := Input.get_vector("camera_left", "camera_right", "camera_forward", "camera_back")
	if input_vector.length_squared() > 0.0:
		var motion := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, yaw_radians) * pan_speed * delta * (zoom_distance / 520.0)
		global_position += motion * float(preferences.values.pan)
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	if event.is_action_pressed("camera_reset"):
		reset_view()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = mouse_button.pressed
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and not _wheel_input_is_excluded(mouse_button.position):
			zoom_distance = maxf(minimum_zoom, zoom_distance - zoom_step * float(preferences.values.zoom))
			_update_camera()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _wheel_input_is_excluded(mouse_button.position):
			zoom_distance = minf(maximum_zoom, zoom_distance + zoom_step * float(preferences.values.zoom))
			_update_camera()
	elif event is InputEventMouseMotion and rotating:
		var rotation_motion := event as InputEventMouseMotion
		yaw_radians -= rotation_motion.relative.x * rotation_drag_speed * float(preferences.values.rotation)
		pitch_radians = clampf(pitch_radians + rotation_motion.relative.y * rotation_drag_speed * float(preferences.values.rotation), MINIMUM_PITCH, MAXIMUM_PITCH)
		_update_camera()
		get_viewport().set_input_as_handled()

func _update_camera() -> void:
	pitch_radians = clampf(pitch_radians, MINIMUM_PITCH, MAXIMUM_PITCH)
	var orbit_pitch := maxf(pitch_radians, MINIMUM_ORBIT_PITCH)
	var orbit_basis := Basis(Vector3.UP, yaw_radians) * Basis(Vector3.RIGHT, -orbit_pitch)
	# Zoom controls framing at the focus plane, independently of the lens angle.
	var orbit_distance := zoom_distance * ZOOM_HALF_SPAN / tan(deg_to_rad(camera.fov * 0.5))
	var offset := orbit_basis.z * orbit_distance
	if pitch_radians == MAXIMUM_PITCH:
		offset = Vector3.UP * orbit_distance
	camera.position = offset
	if terrain_height.is_valid():
		var floor_height := 0.0
		# Protect the near plane as well as the camera origin on a hillside.
		var margin := maxf(8.0, camera.near * 2.0)
		for x: float in [-margin, 0.0, margin]:
			for z: float in [-margin, 0.0, margin]:
				floor_height = maxf(floor_height, float(terrain_height.call(camera.global_position.x + x, camera.global_position.z + z)))
		camera.global_position.y = maxf(camera.global_position.y, floor_height + TERRAIN_CLEARANCE)
	# Near the horizon, orbiting stops lowering the camera but dragging keeps
	# tilting the view. Terrain correction fades out of the gaze, not the position.
	var safe_pitch := atan2(camera.position.y, Vector2(camera.position.x, camera.position.z).length())
	var view_pitch := pitch_radians + maxf(0.0, safe_pitch - orbit_pitch) * smoothstep(0.0, MINIMUM_ORBIT_PITCH, pitch_radians)
	# A yaw-relative basis is stable at an exact top-down view as well.
	camera.basis = Basis(Vector3.UP, yaw_radians) * Basis(Vector3.RIGHT, -view_pitch)

func _clamp_position() -> void:
	global_position.x = clampf(global_position.x, -bounds, bounds)
	global_position.z = clampf(global_position.z, -bounds, bounds)
	_update_camera()

func _wheel_input_is_excluded(screen_position: Vector2) -> bool:
	for control: Control in wheel_input_exclusions:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(screen_position):
			return true
	return false
