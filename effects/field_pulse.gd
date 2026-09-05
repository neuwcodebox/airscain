class_name FieldPulse
extends MeshInstance3D

const DURATION := 0.65
var _elapsed: float = DURATION
var _radius: float = 1.0

func _ready() -> void:
	material_override = material_override.duplicate() as ShaderMaterial
	set_process(false)

func play(radius: float) -> void:
	_elapsed = 0.0
	_radius = radius
	visible = true
	set_process(true)
	_update_visual()

func _process(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, DURATION)
	_update_visual()
	if _elapsed >= DURATION:
		visible = false
		set_process(false)

func _update_visual() -> void:
	var progress := _elapsed / DURATION
	global_basis = Basis.IDENTITY.scaled(Vector3.ONE * (_radius / 10.0) * lerpf(0.45, 1.0, progress))
	(material_override as ShaderMaterial).set_shader_parameter("progress", progress)
