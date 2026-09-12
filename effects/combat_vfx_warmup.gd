class_name CombatVfxWarmup
extends SubViewport

signal completed
signal progress_changed(fraction: float)

const SAMPLE_CATALOG := preload("res://effects/combat_vfx_sample_catalog.gd")
# Diagnostics use these public aliases to instantiate individual warmup assets.
const INTERCEPTOR_SCENE := SAMPLE_CATALOG.INTERCEPTOR_SCENE
const EXPLOSION_SCENE := SAMPLE_CATALOG.EXPLOSION_SCENE
const LASER_SCENE := SAMPLE_CATALOG.LASER_SCENE
const FIELD_SHADER := SAMPLE_CATALOG.FIELD_SHADER
const DAMAGE_SCENE := SAMPLE_CATALOG.DAMAGE_SCENE
const COUNTERMEASURE_SCENE := SAMPLE_CATALOG.COUNTERMEASURE_SCENE
const MISS_SCENE := SAMPLE_CATALOG.MISS_SCENE
const WRECK_SCENE := SAMPLE_CATALOG.WRECK_SCENE
const STRIKE_SCENE := SAMPLE_CATALOG.STRIKE_SCENE
const DRONE_SCENE := SAMPLE_CATALOG.DRONE_SCENE
const SCENARIO := preload("res://main/first_scenario.tres")
const WARMUP_POSITION := Vector3(0.0, 0.0, -8.0)

func _init() -> void:
	name = "CombatVfxWarmup"
	size = Vector2i(64, 64)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _ready() -> void:
	_add_camera_and_light()
	_add_shadow_receiver()
	SAMPLE_CATALOG.add_initial_effect_samples(self, WARMUP_POSITION)
	await _render_samples()
	progress_changed.emit(0.2)
	SAMPLE_CATALOG.add_damage_and_countermeasure_samples(self, WARMUP_POSITION)
	await _render_samples()
	progress_changed.emit(0.4)
	SAMPLE_CATALOG.add_secondary_effect_samples(self, WARMUP_POSITION, SCENARIO)
	await _render_samples()
	progress_changed.emit(0.6)
	var definitions := SAMPLE_CATALOG.content_definitions(SCENARIO)
	for index: int in definitions.size():
		_add_content_sample(definitions[index])
		if index % 4 == 3 or index == definitions.size() - 1:
			await _render_samples()
			progress_changed.emit(0.6 + 0.4 * float(index + 1) / definitions.size())
	completed.emit()
	queue_free()

# Public creation helpers delegate to the shared sample catalog.
static func content_definitions(scenario: ScenarioDefinition) -> Array[Resource]:
	return SAMPLE_CATALOG.content_definitions(scenario)

static func create_content_sample(parent: Node, definition: Resource) -> Node3D:
	return SAMPLE_CATALOG.create_content_sample(parent, definition)

static func create_transient_samples(parent: Node3D, position_value: Vector3) -> Array[Node3D]:
	return SAMPLE_CATALOG.create_transient_samples(parent, position_value)

func _add_content_sample(definition: Resource) -> Node3D:
	var model := SAMPLE_CATALOG.create_content_sample(self, definition)
	model.position = WARMUP_POSITION
	model.scale = Vector3.ONE * 0.18
	return model

func _render_samples() -> void:
	for node: Node in get_children():
		if node.has_meta("warmup_fixture"):
			continue
		node.set_process(false)
		for child: Node in node.find_children("*", "GPUParticles3D", true, false):
			var particles := child as GPUParticles3D
			particles.preprocess = 0.2
			particles.emitting = true
			particles.restart()
	for frame: int in 3:
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	for node: Node in get_children():
		if not node.has_meta("warmup_fixture"):
			node.queue_free()
	await get_tree().process_frame

func _add_camera_and_light() -> void:
	var camera := Camera3D.new()
	camera.current = true
	camera.set_meta("warmup_fixture", true)
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	light.set_meta("warmup_fixture", true)
	add_child(light)
	var impact_light := OmniLight3D.new()
	impact_light.position = WARMUP_POSITION + Vector3.UP
	impact_light.omni_range = 40.0
	impact_light.light_energy = 2.0
	impact_light.set_meta("warmup_fixture", true)
	add_child(impact_light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.set_meta("warmup_fixture", true)
	add_child(environment)

func _add_shadow_receiver() -> void:
	var receiver := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	receiver.mesh = plane
	receiver.set_meta("warmup_fixture", true)
	receiver.position = WARMUP_POSITION + Vector3.DOWN * 3.0
	add_child(receiver)
