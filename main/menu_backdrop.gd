extends SubViewportContainer
## An isolated attract-mode world; never writes a player's operation or save.

const DEMO_SCENE := preload("res://main/main.tscn")
var _viewport: SubViewport
var _camera: Camera3D
var _elapsed: float = 0.0
var demo: AirscainMain
var controller: MenuDefenseDemo

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stretch_shrink = 1
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var previous_seed := AirscainMain.requested_seed
	var previous_mode := AirscainMain.requested_mode
	AirscainMain.requested_seed = 1847
	AirscainMain.requested_mode = AirscainMain.GameMode.SANDBOX
	demo = DEMO_SCENE.instantiate() as AirscainMain
	(demo.get_node("CombatAudio") as CombatAudio).enabled = false
	(demo.get_node("UiAudio") as UiAudio).enabled = false
	_viewport.add_child(demo)
	AirscainMain.requested_seed = previous_seed
	AirscainMain.requested_mode = previous_mode
	controller = MenuDefenseDemo.new()
	add_child(controller)
	controller.configure(demo)
	_camera = demo.camera_rig.camera
	_camera.fov = 42.0
	_camera.far = 18000.0
	_update_camera()
	visibility_changed.connect(_update_visibility)
	_update_visibility()

func _process(delta: float) -> void:
	_elapsed += delta
	_update_camera()

func _update_camera() -> void:
	var angle := 0.58 + sin(_elapsed * 0.025) * 0.06
	_camera.global_position = Vector3(sin(angle) * 1020.0, 535.0, cos(angle) * 1020.0)
	_camera.look_at(Vector3(-130, 0, 80))

func _update_visibility() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
