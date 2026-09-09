class_name DistantContactHaze
extends Node
## Presentation only: the same world-radius haze band as the ocean.

const START_RATIO := 0.85
const END_RATIO := 2.2

class SurfaceFade:
	var mesh: MeshInstance3D
	var surface: int = -1
	var original: Material
	var faded: StandardMaterial3D
	var alpha: float
	var applied: bool = false

class LightFade:
	var light: Light3D
	var energy: float

var source: Node3D
var battlefield_size: float
var opacity: float = -1.0
var surfaces: Array[SurfaceFade] = []
var lights: Array[LightFade] = []

static func opacity_at(position: Vector3, size: float) -> float:
	return 1.0 - smoothstep(size * START_RATIO, size * END_RATIO, Vector2(position.x, position.z).length())

func configure(contact: Node3D, size: float) -> void:
	source = contact
	battlefield_size = size
	_collect(contact)
	refresh()

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null:
			if mesh.material_override != null:
				_add_surface(mesh, -1, mesh.material_override, mesh.material_override)
			else:
				for index: int in mesh.mesh.get_surface_count():
					_add_surface(mesh, index, mesh.get_surface_override_material(index), mesh.get_active_material(index))
	elif node is MultiMeshInstance3D:
		var mesh := node as MultiMeshInstance3D
		if mesh.multimesh != null and mesh.multimesh.mesh != null:
			for index: int in mesh.multimesh.mesh.get_surface_count():
				_configure_trail(mesh.multimesh.mesh.surface_get_material(index))
		_configure_trail(mesh.material_override)
	elif node is Light3D:
		var fade := LightFade.new()
		fade.light = node as Light3D
		fade.energy = fade.light.light_energy
		lights.append(fade)
	for child: Node in node.get_children():
		if child != self:
			_collect(child)

func _configure_trail(material: Material) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
		if uniform.name == "haze_end_radius":
			shader_material.set_shader_parameter("haze_start_radius", battlefield_size * START_RATIO)
			shader_material.set_shader_parameter("haze_end_radius", battlefield_size * END_RATIO)
			return

func _add_surface(mesh: MeshInstance3D, index: int, original: Material, active: Material) -> void:
	var standard := active as StandardMaterial3D
	if standard == null:
		return
	var fade := SurfaceFade.new()
	fade.mesh = mesh
	fade.surface = index
	fade.original = original
	fade.faded = standard.duplicate() as StandardMaterial3D
	fade.faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade.alpha = standard.albedo_color.a
	surfaces.append(fade)

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if not is_instance_valid(source):
		return
	apply_opacity(opacity_at(source.global_position, battlefield_size))

func apply_opacity(next_opacity: float) -> void:
	if is_equal_approx(opacity, next_opacity):
		return
	opacity = next_opacity
	var fading := opacity < 1.0
	for fade: SurfaceFade in surfaces:
		if not is_instance_valid(fade.mesh):
			continue
		if fading != fade.applied:
			var material: Material = fade.faded if fading else fade.original
			if fade.surface < 0:
				fade.mesh.material_override = material
			else:
				fade.mesh.set_surface_override_material(fade.surface, material)
			fade.applied = fading
		if fading:
			fade.faded.albedo_color.a = fade.alpha * opacity
	for fade: LightFade in lights:
		if is_instance_valid(fade.light):
			fade.light.light_energy = fade.energy * opacity
