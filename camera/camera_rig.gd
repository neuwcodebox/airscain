class_name CameraRig
extends Node3D

@export var pan_speed: float = 260.0
@export var drag_speed: float = 0.65
@export var zoom_step: float = 55.0
@export var minimum_zoom: float = 180.0
@export var maximum_zoom: float = 1200.0

var dragging: bool = false
var zoom_distance: float = 680.0
var bounds: float = 810.0

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_update_camera()

func configure_for_battlefield(battlefield_size: float) -> void:
	bounds = battlefield_size * 0.45
	maximum_zoom = battlefield_size * 0.67
	zoom_distance = clampf(battlefield_size * 0.38, minimum_zoom, maximum_zoom)
	camera.far = battlefield_size * 6.0
	_update_camera()

func focus_on(world_position: Vector3) -> void:
	global_position.x = world_position.x
	global_position.z = world_position.z
	_clamp_position()

func _process(delta: float) -> void:
	var input_vector := Input.get_vector("camera_left", "camera_right", "camera_forward", "camera_back")
	if input_vector.length_squared() > 0.0:
		var motion := Vector3(input_vector.x, 0.0, input_vector.y) * pan_speed * delta * (zoom_distance / 520.0)
		global_position += motion
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mouse_button.pressed
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance = maxf(minimum_zoom, zoom_distance - zoom_step)
			_update_camera()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance = minf(maximum_zoom, zoom_distance + zoom_step)
			_update_camera()
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		global_position += Vector3(-motion.relative.x, 0.0, -motion.relative.y) * drag_speed * (zoom_distance / 520.0)
		_clamp_position()

func _update_camera() -> void:
	camera.position = Vector3(0.0, zoom_distance * 0.72, zoom_distance)
	camera.look_at(global_position, Vector3.UP)

func _clamp_position() -> void:
	global_position.x = clampf(global_position.x, -bounds, bounds)
	global_position.z = clampf(global_position.z, -bounds, bounds)
