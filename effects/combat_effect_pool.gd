class_name CombatEffectPool
extends Node3D
## World-local reusable explosion buffers. Actual instances are rendered before play.

const EXPLOSION := preload("res://effects/explosion/explosion.tscn")
const CAPACITY := 8
const RETAINED_CAPACITY := 32
var retained_count: int = CAPACITY
var available: Array[ExplosionEffect] = []
var prepared: bool = false

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
		# Retain overflow buffers for later salvos without limiting visible effects.
		if retained_count < RETAINED_CAPACITY:
			retained_count += 1
			effect.reusable = true
			effect.finished.connect(_recycle)
	else:
		effect = available.pop_back()
		effect.reparent(parent, false)
	effect.global_position = position
	effect.setup(color, radius)
	return effect

func _recycle(effect: ExplosionEffect) -> void:
	effect.reparent(self, false)
	available.append(effect)

func prepare(city_smoke: Array[DamageSmokeEffect]) -> void:
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
	for node: Node3D in nodes:
		var original := node.transform
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
		for frame: int in 3:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		for child: Node in node.find_children("*", "GPUParticles3D", true, false):
			(child as GPUParticles3D).preprocess = 0.0
		if node is ExplosionEffect:
			(node as ExplosionEffect).deactivate()
		else:
			(node as DamageSmokeEffect).deactivate()
		node.transform = original
	impact_light.queue_free()
	prepared = true
