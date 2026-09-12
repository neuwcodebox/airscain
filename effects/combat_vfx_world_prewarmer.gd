class_name CombatVfxWorldPrewarmer
extends RefCounted
## Renders retained and transient VFX against the actual battlefield environment.

const SAMPLE_CATALOG := preload("res://effects/combat_vfx_sample_catalog.gd")

var retained_materials: Array[Material] = []
var effect_to_recycle: ExplosionEffect

func prepare(
		host: Node3D,
		pooled_explosions: Array[ExplosionEffect],
		city_smoke: Array[DamageSmokeEffect],
		scenario: ScenarioDefinition,
		battlefield: Battlefield
) -> Array[Material]:
	assert(not pooled_explosions.is_empty(), "Combat VFX prewarm requires one retained explosion")
	retained_materials.clear()
	effect_to_recycle = null
	# Lighting variants belong to receivers too: warm the real city/terrain
	# MultiMeshes under an impact light, behind the scene's loading cover.
	var impact_light := OmniLight3D.new()
	impact_light.position = Vector3(0, 80, 0)
	impact_light.omni_range = 2400.0
	impact_light.light_energy = 0.05
	host.add_child(impact_light)
	await _prepare_retained_effects(host, impact_light, pooled_explosions, city_smoke)
	if scenario != null:
		await _prepare_content(host, impact_light, scenario)
	await _prepare_transients(host, impact_light, pooled_explosions, battlefield)
	return retained_materials

static func retain_sample_materials(samples: Array[Node3D], materials: Array[Material]) -> void:
	for sample: Node3D in samples:
		for child: Node in sample.find_children("*", "GeometryInstance3D", true, false):
			var meshes: Array[Mesh] = []
			var geometry := child as GeometryInstance3D
			_keep_material(geometry.material_override, materials)
			if child is MeshInstance3D:
				meshes.append((child as MeshInstance3D).mesh)
			elif child is MultiMeshInstance3D:
				meshes.append((child as MultiMeshInstance3D).multimesh.mesh)
			elif child is GPUParticles3D:
				var particles := child as GPUParticles3D
				_keep_material(particles.process_material, materials)
				for draw_pass: int in particles.draw_passes:
					meshes.append(particles.get_draw_pass_mesh(draw_pass))
			for mesh: Mesh in meshes:
				if mesh != null:
					for surface: int in mesh.get_surface_count():
						_keep_material(mesh.surface_get_material(surface), materials)

func _prepare_retained_effects(
		host: Node3D,
		impact_light: OmniLight3D,
		pooled_explosions: Array[ExplosionEffect],
		city_smoke: Array[DamageSmokeEffect]
) -> void:
	var nodes: Array[Node3D] = []
	for effect: ExplosionEffect in pooled_explosions:
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
			await _render_frames(host, 3)
		for index: int in batch.size():
			var node := batch[index]
			for child: Node in node.find_children("*", "GPUParticles3D", true, false):
				(child as GPUParticles3D).preprocess = 0.0
			if node is ExplosionEffect:
				(node as ExplosionEffect).deactivate()
			else:
				(node as DamageSmokeEffect).deactivate()
			node.transform = originals[index]

func _prepare_content(host: Node3D, impact_light: OmniLight3D, scenario: ScenarioDefinition) -> void:
	# Real viewport/environment variants are not interchangeable with the
	# app's small off-screen warmup viewport.
	var definitions := SAMPLE_CATALOG.content_definitions(scenario)
	for start: int in range(0, definitions.size(), 4):
		var models: Array[Node3D] = []
		var hazes: Array[DistantContactHaze] = []
		for definition: Resource in definitions.slice(start, mini(start + 4, definitions.size())):
			var model := SAMPLE_CATALOG.create_content_sample(host, definition)
			model.global_position = Vector3(0, 80, 0)
			models.append(model)
			if model is ThreatUnit:
				var haze := DistantContactHaze.new()
				model.add_child(haze)
				haze.configure(model, scenario.battlefield_size)
				hazes.append(haze)
				for surface: DistantContactHaze.SurfaceFade in haze.surfaces:
					retained_materials.append(surface.faded)
		for local_light: bool in [true, false]:
			impact_light.visible = local_light
			for opacity: float in [1.0, 0.5]:
				for haze: DistantContactHaze in hazes:
					haze.apply_opacity(opacity)
				await _render_frames(host, 3)
		for model: Node3D in models:
			model.queue_free()

func _prepare_transients(
		host: Node3D,
		impact_light: OmniLight3D,
		pooled_explosions: Array[ExplosionEffect],
		battlefield: Battlefield
) -> void:
	# Transient effects use the real camera, local lights and smoke-shadow target.
	# Rendering only the app's tiny SubViewport leaves WebGL variants cold.
	var transients := SAMPLE_CATALOG.create_transient_samples(host, Vector3(0, 80, 0))
	retain_sample_materials(transients, retained_materials)
	if battlefield != null and battlefield.smoke_shadow_projection != null:
		battlefield.smoke_shadow_projection.update_projection()
	for local_light: bool in [true, false]:
		impact_light.visible = local_light
		for model: Node3D in transients:
			for child: Node in model.find_children("*", "Light3D", true, false):
				(child as Light3D).visible = local_light
		await _render_frames(host, 3)
	var fading := pooled_explosions.back() as ExplosionEffect
	var released_trails: Array[LingeringSmokeTrail] = []
	for model: Node3D in transients:
		if model is HomingInterceptor:
			released_trails.append(model.get_node("SmokeTrail") as LingeringSmokeTrail)
			(model as HomingInterceptor).self_destruct()
		else:
			model.queue_free()
	impact_light.queue_free()
	# The real release/detonation path also changes the renderer's state as
	# the impact light ends. Prime that transition with no gameplay listeners.
	while fading.visible and fading.elapsed < ExplosionTimeline.LIGHT_DURATION + 0.5:
		await _render_frames(host, 1)
	fading.deactivate()
	effect_to_recycle = fading
	for trail: LingeringSmokeTrail in released_trails:
		if is_instance_valid(trail):
			trail.queue_free()

static func _render_frames(host: Node, count: int) -> void:
	for frame: int in count:
		await host.get_tree().process_frame
		await RenderingServer.frame_post_draw

static func _keep_material(material: Material, materials: Array[Material]) -> void:
	if material != null and not materials.has(material):
		materials.append(material)
