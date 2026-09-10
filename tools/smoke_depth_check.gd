extends SceneTree
## Actual-render comparison against a finely tessellated sphere. Run without
## --headless: validates silhouettes and nearest depth, including transformed puffs.

const EXPERIMENT := preload("res://tools/smoke_shadow_experiment.gd")

var viewport: SubViewport
var camera: Camera3D
var casters: Array[MultiMeshInstance3D] = []
var impostors: Array[Mesh] = []
var spheres: Array[Mesh] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	root.add_child(viewport)
	camera = Camera3D.new()
	camera.cull_mask = SmokeShadowFactory.SMOKE_LAYER
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 80.0
	camera.near = 0.1
	camera.far = 300.0
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.WHITE
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 100)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.size = Vector2(640, 640)
	root.add_child(display)
	for index: int in 2:
		var source := QuadMesh.new()
		source.size = Vector2(20, 16)
		var source_material := StandardMaterial3D.new()
		source_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		source.material = source_material
		var proxy := SmokeShadowFactory.create(source)
		var sphere := SphereMesh.new()
		sphere.radius = (proxy.mesh as SphereMesh).radius
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 96
		sphere.rings = 48
		var material := ShaderMaterial.new()
		material.shader = SmokeShadowFactory.SHADOW_SHADER
		sphere.material = material
		var caster := MultiMeshInstance3D.new()
		caster.layers = SmokeShadowFactory.SMOKE_LAYER
		caster.multimesh = MultiMesh.new()
		caster.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		caster.multimesh.use_colors = true
		caster.multimesh.use_custom_data = true
		caster.multimesh.instance_count = 1
		caster.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
		caster.multimesh.set_instance_color(0, Color(0.9, 0.8, 0.65, 1.0))
		caster.multimesh.set_instance_custom_data(0, Color(0, 1, 0.8, 0))
		caster.multimesh.custom_aabb = AABB(Vector3.ONE * -50.0, Vector3.ONE * 100.0)
		viewport.add_child(caster)
		casters.append(caster)
		impostors.append(EXPERIMENT.make_impostor(proxy.mesh as SphereMesh))
		spheres.append(sphere)
	var cases: Array[String] = ["round", "rotated_scaled", "overlap", "low_sun", "trail_drift", "fading", "gone"]
	for label: String in cases:
		casters[0].basis = Basis.from_euler(Vector3(0.4, 0.8, 1.0)).scaled(Vector3(2.0, 0.45, 1.3)) if label == "rotated_scaled" else Basis.IDENTITY
		casters[1].visible = label == "overlap"
		casters[1].position = Vector3(4, 2, -3)
		camera.position = Vector3(60, 12, 90) if label == "low_sun" else Vector3(0, 0, 100)
		camera.look_at(Vector3.ZERO)
		for meshes: Array[Mesh] in [impostors, spheres]:
			for mesh: Mesh in meshes:
				var material := mesh.surface_get_material(0) as ShaderMaterial
				material.set_shader_parameter("opacity_ratio", 0.0 if label == "gone" else (0.2 if label == "fading" else 1.0))
				material.set_shader_parameter("trail_enabled", label == "trail_drift")
				material.set_shader_parameter("trail_time", 6.0)
				material.set_shader_parameter("trail_initial_scale", 1.0)
				material.set_shader_parameter("trail_final_scale", 1.8)
		var expected := await _capture(spheres)
		var actual := await _capture(impostors)
		if not _compare(label, expected, actual):
			quit(1)
			return
	print("SMOKE_DEPTH_OK cases=%d" % cases.size())
	viewport.free()
	quit(0)

func _capture(meshes: Array[Mesh]) -> Image:
	for index: int in casters.size():
		casters[index].multimesh.mesh = meshes[index]
	for frame: int in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _compare(label: String, expected: Image, actual: Image) -> bool:
	var covered := 0
	var mismatch := 0
	var maximum_depth_error := 0.0
	for y: int in expected.get_height():
		for x: int in expected.get_width():
			var reference := expected.get_pixel(x, y)
			var result := actual.get_pixel(x, y)
			var reference_covered := reference != Color.WHITE
			var result_covered := result != Color.WHITE
			if reference_covered:
				covered += 1
			if reference_covered != result_covered:
				mismatch += 1
			elif reference_covered:
				var reference_depth := reference.r + reference.g / 255.0 + reference.b / 65025.0
				var result_depth := result.r + result.g / 255.0 + result.b / 65025.0
				maximum_depth_error = maxf(maximum_depth_error, absf(reference_depth - result_depth))
	print("SMOKE_DEPTH %s covered=%d edge_mismatch=%d max_depth_error=%.8f" % [label, covered, mismatch, maximum_depth_error])
	# The captured map is RGBA8: bound the difference of two quantized RGB packs.
	var quantization_bound := 1.0 / 255.0 + 1.0 / 65025.0
	var valid := mismatch <= maxi(4, ceili(covered * 0.02)) and maximum_depth_error <= quantization_bound
	valid = valid and (covered == 0 if label == "gone" else covered > 100)
	if not valid:
		expected.save_png("/tmp/airscain_depth_expected.png")
		actual.save_png("/tmp/airscain_depth_actual.png")
		push_error("Smoke depth differs from the reference sphere: " + label)
	return valid
