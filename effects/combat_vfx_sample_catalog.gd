class_name CombatVfxSampleCatalog
extends RefCounted
## Creates inert content and transient samples used by both warmup render paths.

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

static func content_definitions(scenario: ScenarioDefinition) -> Array[Resource]:
	var definitions: Array[Resource] = []
	definitions.append_array(scenario.available_defenses)
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if not definitions.has(entry.threat_definition):
			definitions.append(entry.threat_definition)
	for definition: ThreatDefinition in scenario.ambient_contacts:
		if not definitions.has(definition):
			definitions.append(definition)
	# Released weapons also acquire runtime haze materials when registered.
	var index := 0
	while index < definitions.size():
		var threat := definitions[index] as ThreatDefinition
		if threat != null:
			for released: ThreatDefinition in threat.released_threat_definitions():
				if not definitions.has(released):
					definitions.append(released)
		index += 1
	return definitions

static func create_content_sample(parent: Node, definition: Resource) -> Node3D:
	if definition is DefenseDefinition:
		return _create_defense_sample(parent, definition as DefenseDefinition)
	if definition is ThreatDefinition:
		return _create_threat_sample(parent, definition as ThreatDefinition)
	push_error("Combat VFX warmup only accepts defense and threat definitions")
	return null

static func create_transient_samples(parent: Node3D, position_value: Vector3) -> Array[Node3D]:
	var samples: Array[Node3D] = []
	for scene: PackedScene in [INTERCEPTOR_SCENE, STRIKE_SCENE, DRONE_SCENE]:
		var model := scene.instantiate() as Node3D
		parent.add_child(model)
		model.global_position = position_value
		model.process_mode = Node.PROCESS_MODE_DISABLED
		for child: Node in model.find_children("*", "MultiMeshInstance3D", true, false):
			if child is LingeringSmokeTrail:
				var smoke := child as LingeringSmokeTrail
				smoke.sample_world_segment(position_value + Vector3.LEFT * 20, position_value + Vector3.RIGHT * 20)
				# Birth alpha is zero; render after fade-in, not invisible cards.
				smoke.prepare_preview(minf(1.0, smoke.lifetime * 0.25))
		samples.append(model)
	var laser := LASER_SCENE.instantiate() as LaserPulse
	parent.add_child(laser)
	laser.setup(position_value + Vector3.LEFT * 20, position_value + Vector3.RIGHT * 20)
	samples.append(laser)
	var miss := MISS_SCENE.instantiate() as InterceptorMissEffect
	parent.add_child(miss)
	miss.global_position = position_value
	miss.setup(Color.ORANGE, "지형 충돌 · 유도 상실 · 표적 소실 · 요격 실패")
	samples.append(miss)
	for kind: StringName in [&"flare", &"chaff"]:
		var burst := COUNTERMEASURE_SCENE.instantiate() as CountermeasureBurst
		parent.add_child(burst)
		burst.global_position = position_value
		burst.setup(kind, Vector3(90, 0, 0))
		# Include the last sequential flare and advance smoke past birth fade-in.
		var preview_age := CountermeasureBurst.RELEASE_INTERVAL * (CountermeasureBurst.HEAD_COUNT - 1) + 0.3
		burst.prepare_preview(preview_age)
		samples.append(burst)
	_prepare_inert_samples(samples)
	return samples

static func add_initial_effect_samples(parent: Node, position_value: Vector3) -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	interceptor.position = position_value
	parent.add_child(interceptor)
	var smoke := interceptor.get_node("SmokeTrail") as LingeringSmokeTrail
	smoke.sample_world_segment(position_value + Vector3.LEFT * 2.0, position_value + Vector3.RIGHT * 2.0)

	var explosion := EXPLOSION_SCENE.instantiate() as ExplosionEffect
	explosion.position = position_value + Vector3.RIGHT * 3.0
	parent.add_child(explosion)
	explosion.setup(Color(1.0, 0.35, 0.06), 2.0)
	explosion.prepare_preview(0.18)

	var laser := LASER_SCENE.instantiate() as LaserPulse
	parent.add_child(laser)
	laser.setup(position_value + Vector3.LEFT * 2.0, position_value + Vector3.RIGHT * 2.0)
	laser.set_process(false)
	var field := MeshInstance3D.new()
	field.mesh = SphereMesh.new()
	var material := ShaderMaterial.new()
	material.shader = FIELD_SHADER
	field.material_override = material
	field.position = position_value
	parent.add_child(field)

static func add_damage_and_countermeasure_samples(parent: Node, position_value: Vector3) -> void:
	var smoke := DAMAGE_SCENE.instantiate() as DamageSmokeEffect
	smoke.position = position_value
	parent.add_child(smoke)
	smoke.set_city_scale(0.12)
	for kind: StringName in [&"flare", &"chaff"]:
		var burst := COUNTERMEASURE_SCENE.instantiate() as CountermeasureBurst
		burst.position = position_value
		burst.scale = Vector3.ONE * 0.1
		parent.add_child(burst)
		burst.setup(kind)

static func add_secondary_effect_samples(parent: Node, position_value: Vector3, scenario: ScenarioDefinition) -> void:
	var tracer := GunfireRuntime.new()
	parent.add_child(tracer)
	var gun_definition := _close_in_gun_definition(scenario)
	if gun_definition != null:
		tracer.enqueue(position_value, position_value + Vector3.RIGHT * 100, Vector3.ZERO, 1, 1, gun_definition, RandomNumberGenerator.new())
		tracer.gameplay_tick(0.01)
	tracer.prepare_airburst_preview(position_value)
	var miss := MISS_SCENE.instantiate() as InterceptorMissEffect
	miss.position = position_value
	parent.add_child(miss)
	miss.setup(Color.ORANGE, "지형 충돌 · 유도 상실 · 표적 소실")
	var wreck := WRECK_SCENE.instantiate() as FallingWreckEffect
	wreck.position = position_value
	parent.add_child(wreck)
	wreck.setup(Color.GRAY, Vector3.ZERO, -100)
	wreck.smoke.sample_world_segment(position_value, position_value + Vector3.RIGHT * 2)
	for scene: PackedScene in [STRIKE_SCENE, DRONE_SCENE]:
		var model := scene.instantiate() as Node3D
		model.position = position_value
		parent.add_child(model)
		model.set_process(false)
		if scene == STRIKE_SCENE:
			wreck.use_airframe(model)

static func _create_defense_sample(parent: Node, definition: DefenseDefinition) -> DefenseUnit:
	var unit := definition.scene.instantiate() as DefenseUnit
	parent.add_child(unit)
	unit.setup(1, definition)
	_prepare_content_sample(unit)
	return unit

static func _create_threat_sample(parent: Node, definition: ThreatDefinition) -> ThreatUnit:
	var unit := definition.scene.instantiate() as ThreatUnit
	parent.add_child(unit)
	unit.setup(1, definition)
	_prepare_content_sample(unit)
	return unit

static func _close_in_gun_definition(scenario: ScenarioDefinition) -> CloseInGunDefinition:
	for definition: DefenseDefinition in scenario.available_defenses:
		if definition is CloseInGunDefinition:
			return definition as CloseInGunDefinition
	return null

static func _prepare_content_sample(model: Node3D) -> void:
	model.process_mode = Node.PROCESS_MODE_DISABLED
	for visual: Node in model.find_children("*", "GeometryInstance3D", true, false):
		if visual.get_meta("warmup_visible", false):
			(visual as GeometryInstance3D).visible = true

static func _prepare_inert_samples(samples: Array[Node3D]) -> void:
	for sample: Node3D in samples:
		sample.process_mode = Node.PROCESS_MODE_DISABLED
		for child: Node in sample.find_children("*", "GPUParticles3D", true, false):
			var particles := child as GPUParticles3D
			particles.process_mode = Node.PROCESS_MODE_ALWAYS
			particles.preprocess = 0.2
			particles.restart()
