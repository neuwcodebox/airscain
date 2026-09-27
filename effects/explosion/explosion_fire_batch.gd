class_name ExplosionFireBatch
extends MultiMeshInstance3D
## One world-space draw submission for every pooled explosion fire card.

const CARDS_PER_EXPLOSION := 52
const FIRE_SHADER := preload("res://effects/explosion/explosion_fire_batch.gdshader")

var capacity: int = 32
var fire_material: ShaderMaterial
var _elapsed: float = 0.0
var _active_until := PackedFloat32Array()
var _burst_serial: int = 0

func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var card := QuadMesh.new()
	card.size = Vector2(2.0, 2.0)
	fire_material = ShaderMaterial.new()
	fire_material.shader = FIRE_SHADER
	fire_material.render_priority = 1
	fire_material.set_shader_parameter("core_texture", preload("res://effects/glow_card_texture.tres"))
	card.material = fire_material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = card
	batch.instance_count = capacity * CARDS_PER_EXPLOSION
	batch.custom_aabb = AABB(Vector3(-3200.0, -400.0, -3200.0), Vector3(6400.0, 2800.0, 6400.0))
	multimesh = batch
	_active_until.resize(capacity)
	for slot: int in capacity:
		clear_slot(slot)
	visible = false
	set_process(true)

func emit_burst(slot: int, world_position: Vector3, color: Color, radius: float) -> void:
	if slot < 0 or slot >= capacity or multimesh == null:
		return
	_burst_serial = (_burst_serial + 1) % 4096
	var radius_scale := maxf(0.85, radius / 9.0)
	var start := slot * CARDS_PER_EXPLOSION
	for local_index: int in CARDS_PER_EXPLOSION:
		var outer_layer := 1.0 if local_index >= 30 else 0.0
		var seed := float((_burst_serial * capacity + slot) * CARDS_PER_EXPLOSION + local_index + 1)
		var index := start + local_index
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, world_position))
		multimesh.set_instance_color(index, Color(color.r, color.g, color.b, 1.0))
		multimesh.set_instance_custom_data(index, Color(_elapsed, seed, radius_scale, outer_layer))
	_active_until[slot] = _elapsed + 1.3
	visible = true

func clear_slot(slot: int) -> void:
	if slot < 0 or slot >= capacity or multimesh == null:
		return
	var start := slot * CARDS_PER_EXPLOSION
	for local_index: int in CARDS_PER_EXPLOSION:
		multimesh.set_instance_custom_data(start + local_index, Color(-1000.0, 0.0, 0.0, 0.0))
	_active_until[slot] = 0.0

func slot_is_active(slot: int) -> bool:
	return slot >= 0 and slot < _active_until.size() and _active_until[slot] > _elapsed

func _process(delta: float) -> void:
	_elapsed += delta
	if fire_material != null:
		fire_material.set_shader_parameter("batch_time", _elapsed)
	var has_active := false
	for active_until: float in _active_until:
		if active_until > _elapsed:
			has_active = true
			break
	visible = has_active
