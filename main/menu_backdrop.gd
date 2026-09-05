extends SubViewportContainer
## A presentation-only world: no session, combat, input, or random gameplay state.

const BATTLEFIELD := preload("res://world/battlefield.tscn")
const SCENARIO := preload("res://main/first_scenario.tres")
var _viewport: SubViewport
var _camera: Camera3D
var _elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stretch_shrink = 1
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var world := BATTLEFIELD.instantiate() as Battlefield
	_viewport.add_child(world)
	var scenario := SCENARIO.duplicate() as ScenarioDefinition
	scenario.world_seed = 1847
	world.build(scenario)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("46616c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("98b4bd")
	environment.environment.ambient_light_energy = 0.7
	_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -38, 0)
	sun.light_color = Color("ffe2b2")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2300.0
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.far = 18000.0
	_viewport.add_child(_camera)
	_update_camera()
	visibility_changed.connect(_update_visibility)
	_update_visibility()

func _process(delta: float) -> void:
	_elapsed += delta
	_update_camera()

func _update_camera() -> void:
	var angle := 0.58 + sin(_elapsed * 0.025) * 0.06
	_camera.position = Vector3(sin(angle) * 870.0, 465.0, cos(angle) * 870.0)
	_camera.look_at(Vector3(-180, 0, 20))

func _update_visibility() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
