class_name CombatEffectPool
extends Node3D
## World-local reusable explosion buffers. Actual instances are rendered before play.

const EXPLOSION := preload("res://effects/explosion/explosion.tscn")
const CAPACITY := 32
var available: Array[ExplosionEffect] = []
var prepared: bool = false
# Keep generated material variants alive after their sample nodes are removed.
var prepared_materials: Array[Material] = []

func _ready() -> void:
	add_to_group("combat_effect_pool")
	for index: int in CAPACITY:
		var effect := EXPLOSION.instantiate() as ExplosionEffect
		add_child(effect)
		effect.reusable = true
		effect.finished.connect(_recycle)
		effect.setup(Color.ORANGE, 12)
		effect.deactivate()
		available.append(effect)

func spawn_explosion(parent: Node3D, position: Vector3, color: Color, radius: float) -> ExplosionEffect:
	var effect: ExplosionEffect
	if available.is_empty():
		effect = EXPLOSION.instantiate() as ExplosionEffect
		parent.add_child(effect)
		# The retained budget is already prepared. Overflow never drops an effect.
	else:
		effect = available.pop_back()
		effect.reparent(parent, false)
	effect.global_position = position
	effect.setup(color, radius)
	return effect

func _recycle(effect: ExplosionEffect) -> void:
	effect.reparent(self, false)
	available.append(effect)

func prepare(city_smoke: Array[DamageSmokeEffect], scenario: ScenarioDefinition = null, battlefield: Battlefield = null) -> void:
	if DisplayServer.get_name() == "headless":
		prepared = true
		return
	# Lighting variants belong to receivers too: warm the real city/terrain
	# MultiMeshes under an impact light, behind the scene's loading cover.
	var impact_light := OmniLight3D.new()
	impact_light.position = Vector3(0, 80, 0)
	impact_light.omni_range = 2400.0
	impact_light.light_energy = 0.05
	add_child(impact_light)
	var nodes: Array[Node3D] = []
	for effect: ExplosionEffect in available:
		nodes.append(effect)
	nodes.append_array(city_smoke)
	# Small batches bound loading frame cost while preparing every retained buffer.
	for start: int in range(0, nodes.size(), 4):
		var batch: Array[Node3D] = nodes.slice(start, mini(start + 4, nodes.size()))
		var originals: Array[Transform3D] = []
		for node: Node3D in batch:
			originals.append(node.transform)
			node.global_position = Vector3(0, 35, 0)
			if node is ExplosionEffect:
				(node as ExplosionEffect).setup(Color.ORANGE, 12)
				node.set_process(false)
			else:
				(node as DamageSmokeEffect).set_city_scale(1.5)
			for child: Node in node.find_children("*", "GPUParticles3D", true, false):
				var particles := child as GPUParticles3D
				particles.preprocess = 0.2
				particles.emitting = true
				particles.restart()
		for local_light: bool in [true, false]:
			impact_light.visible = local_light
			for node: Node3D in batch:
				if node is ExplosionEffect:
					(node as ExplosionEffect).blast_light.visible = local_light
			for frame: int in 3:
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
		for index: int in batch.size():
			var node := batch[index]
			for child: Node in node.find_children("*", "GPUParticles3D", true, false):
				(child as GPUParticles3D).preprocess = 0.0
			if node is ExplosionEffect:
				(node as ExplosionEffect).deactivate()
			else:
				(node as DamageSmokeEffect).deactivate()
			node.transform = originals[index]
	if scenario != null:
		# Real viewport/environment variants are not interchangeable with the
		# app's small off-screen warmup viewport.
		var definitions := CombatVfxWarmup.content_definitions(scenario)
		for start: int in range(0, definitions.size(), 4):
			var models: Array[Node3D] = []
			var hazes: Array[DistantContactHaze] = []
			for definition: Resource in definitions.slice(start, mini(start + 4, definitions.size())):
				var model := CombatVfxWarmup.create_content_sample(self, definition)
				model.global_position = Vector3(0, 80, 0)
				models.append(model)
				if model is ThreatUnit:
					var haze := DistantContactHaze.new()
					model.add_child(haze)
					haze.configure(model, scenario.battlefield_size)
					hazes.append(haze)
					for surface: DistantContactHaze.SurfaceFade in haze.surfaces:
						prepared_materials.append(surface.faded)
			for local_light: bool in [true, false]:
				impact_light.visible = local_light
				for opacity: float in [1.0, 0.5]:
					for haze: DistantContactHaze in hazes:
						haze.apply_opacity(opacity)
					for frame: int in 3:
						await get_tree().process_frame
						await RenderingServer.frame_post_draw
			for model: Node3D in models:
				model.queue_free()
	# Transient effects use the real camera, local lights and smoke-shadow target.
	# Rendering only the app's tiny SubViewport leaves WebGL variants cold.
	var transients := CombatVfxWarmup.create_transient_samples(self, Vector3(0, 80, 0))
	_retain_sample_materials(transients)
	if battlefield != null and battlefield.smoke_shadow_projection != null:
		battlefield.smoke_shadow_projection.update_projection()
	for local_light: bool in [true, false]:
		impact_light.visible = local_light
		for model: Node3D in transients:
			for child: Node in model.find_children("*", "Light3D", true, false):
				(child as Light3D).visible = local_light
		for frame: int in 3:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	var fading := available.back() as ExplosionEffect
	var released_trails: Array[LingeringSmokeTrail] = []
	for model: Node3D in transients:
		if model is HomingInterceptor:
			released_trails.append(model.get_node("SmokeTrail") as LingeringSmokeTrail)
			(model as HomingInterceptor)._self_destruct()
		else:
			model.queue_free()
	impact_light.queue_free()
	# The real release/detonation path also changes the renderer's state as
	# the impact light ends. Prime that transition with no gameplay listeners.
	while fading.visible and fading.elapsed < ExplosionTimeline.LIGHT_DURATION + 0.5:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	fading.deactivate()
	if not available.has(fading):
		_recycle(fading)
	for trail: LingeringSmokeTrail in released_trails:
		if is_instance_valid(trail):
			trail.queue_free()
	prepared = true

func _retain_sample_materials(samples: Array[Node3D]) -> void:
	for sample: Node3D in samples:
		for child: Node in sample.find_children("*", "GeometryInstance3D", true, false):
			var meshes: Array[Mesh] = []
			var geometry := child as GeometryInstance3D
			_keep_material(geometry.material_override)
			if child is MeshInstance3D:
				meshes.append((child as MeshInstance3D).mesh)
			elif child is MultiMeshInstance3D:
				meshes.append((child as MultiMeshInstance3D).multimesh.mesh)
			elif child is GPUParticles3D:
				var particles := child as GPUParticles3D
				_keep_material(particles.process_material)
				for draw_pass: int in particles.draw_passes:
					meshes.append(particles.get_draw_pass_mesh(draw_pass))
			for mesh: Mesh in meshes:
				if mesh != null:
					for surface: int in mesh.get_surface_count():
						_keep_material(mesh.surface_get_material(surface))

func _keep_material(material: Material) -> void:
	if material != null and not prepared_materials.has(material):
		prepared_materials.append(material)
