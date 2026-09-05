class_name CombatVfxWarmup
extends SubViewport

signal completed
signal progress_changed(fraction: float)

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")
const EXPLOSION_SCENE := preload("res://effects/explosion/explosion.tscn")
const LASER_SCENE := preload("res://effects/laser_pulse/laser_pulse.tscn")
const FIELD_SHADER := preload("res://effects/field_pulse.gdshader")
const DAMAGE_SCENE := preload("res://effects/damage_smoke/damage_smoke.tscn")
const COUNTERMEASURE_SCENE := preload("res://effects/countermeasure_burst/countermeasure_burst.tscn")
const MISS_SCENE := preload("res://effects/interceptor_miss/interceptor_miss.tscn")
const WRECK_SCENE := preload("res://effects/falling_wreck/falling_wreck.tscn")
const STRIKE_SCENE := preload("res://effects/air_strike_munition/air_strike_munition.tscn")
const DRONE_SCENE := preload("res://defense/interceptor_drone/interceptor_drone.tscn")
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
	_add_interceptor_sample()
	_add_explosion_sample()
	_add_energy_samples()
	await _render_samples()
	progress_changed.emit(0.2)
	_add_damage_and_countermeasures()
	await _render_samples()
	progress_changed.emit(0.4)
	_add_secondary_effects()
	await _render_samples()
	progress_changed.emit(0.6)
	var scenes: Array[PackedScene] = []
	for definition: DefenseDefinition in SCENARIO.available_defenses:
		if not scenes.has(definition.scene):
			scenes.append(definition.scene)
	for entry: ThreatSpawnEntry in SCENARIO.threat_entries:
		if not scenes.has(entry.threat_definition.scene):
			scenes.append(entry.threat_definition.scene)
	for definition: ThreatDefinition in SCENARIO.ambient_contacts:
		if not scenes.has(definition.scene):
			scenes.append(definition.scene)
	for index: int in scenes.size():
		var model := scenes[index].instantiate() as Node3D
		model.position = WARMUP_POSITION
		model.scale = Vector3.ONE * 0.18
		add_child(model)
		model.process_mode = Node.PROCESS_MODE_DISABLED
		if index % 4 == 3 or index == scenes.size() - 1:
			await _render_samples()
			progress_changed.emit(0.6 + 0.4 * float(index + 1) / scenes.size())
	completed.emit()
	queue_free()

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

func _add_damage_and_countermeasures() -> void:
	var smoke := DAMAGE_SCENE.instantiate() as DamageSmokeEffect
	smoke.position = WARMUP_POSITION
	add_child(smoke)
	smoke.set_city_scale(0.12)
	for kind: StringName in [&"flare", &"chaff"]:
		var burst := COUNTERMEASURE_SCENE.instantiate() as Node3D
		burst.position = WARMUP_POSITION
		burst.scale = Vector3.ONE * 0.1
		add_child(burst)
		burst.call("setup", kind)

func _add_secondary_effects() -> void:
	var tracer := GunfireRuntime.new()
	add_child(tracer)
	var gun_definition := SCENARIO.available_defenses[4] as CloseInGunDefinition
	tracer.enqueue(WARMUP_POSITION, WARMUP_POSITION + Vector3.RIGHT * 100, Vector3.ZERO, 1, 1, gun_definition, RandomNumberGenerator.new())
	tracer.gameplay_tick(0.01)
	tracer._detonate(WARMUP_POSITION, &"timeout")
	tracer._sync_visuals()
	var miss := MISS_SCENE.instantiate() as InterceptorMissEffect
	miss.position = WARMUP_POSITION
	add_child(miss)
	miss.setup(Color.ORANGE, "지형 충돌 · 유도 상실 · 표적 소실")
	var wreck := WRECK_SCENE.instantiate() as FallingWreckEffect
	wreck.position = WARMUP_POSITION
	add_child(wreck)
	wreck.setup(Color.GRAY, Vector3.ZERO, -100)
	wreck.smoke.sample_world_segment(WARMUP_POSITION, WARMUP_POSITION + Vector3.RIGHT * 2)
	for scene: PackedScene in [STRIKE_SCENE, DRONE_SCENE]:
		var model := scene.instantiate() as Node3D
		model.position = WARMUP_POSITION
		add_child(model)
		model.set_process(false)

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

func _add_interceptor_sample() -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	interceptor.position = WARMUP_POSITION
	add_child(interceptor)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	smoke.sample_world_segment(WARMUP_POSITION + Vector3.LEFT * 2.0, WARMUP_POSITION + Vector3.RIGHT * 2.0)

func _add_explosion_sample() -> void:
	var explosion := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	explosion.position = WARMUP_POSITION + Vector3.RIGHT * 3.0
	add_child(explosion)
	explosion.setup(Color(1.0, 0.35, 0.06), 2.0)
	explosion._process(0.18)

func _add_energy_samples() -> void:
	var laser := LASER_SCENE.instantiate() as LaserPulse
	add_child(laser)
	laser.setup(WARMUP_POSITION + Vector3.LEFT * 2.0, WARMUP_POSITION + Vector3.RIGHT * 2.0)
	laser.set_process(false)
	var field := MeshInstance3D.new()
	field.mesh = SphereMesh.new()
	var material := ShaderMaterial.new()
	material.shader = FIELD_SHADER
	field.material_override = material
	field.position = WARMUP_POSITION
	add_child(field)
