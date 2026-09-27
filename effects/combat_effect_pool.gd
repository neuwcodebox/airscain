class_name CombatEffectPool
extends Node3D
## World-local reusable explosion buffers.

const EXPLOSION := preload("res://effects/explosion/explosion.tscn")
const WORLD_PREWARMER := preload("res://effects/combat_vfx_world_prewarmer.gd")
const CAPACITY := 32

var available: Array[ExplosionEffect] = []
var prepared: bool = false
# Keep generated material variants alive for the operation.
var prepared_materials: Array[Material] = []

func _ready() -> void:
	add_to_group("combat_effect_pool")
	for index: int in CAPACITY:
		var effect := EXPLOSION.instantiate() as ExplosionEffect
		add_child(effect)
		effect.reusable = true
		effect.finished.connect(recycle)
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

func prepare(city_smoke: Array[DamageSmokeEffect], scenario: ScenarioDefinition = null, battlefield: Battlefield = null) -> void:
	if DisplayServer.get_name() == "headless":
		prepared = true
		return
	var prewarmer := WORLD_PREWARMER.new() as CombatVfxWorldPrewarmer
	var pooled_explosions: Array[ExplosionEffect] = available.duplicate()
	prepared_materials = await prewarmer.prepare(
		self,
		pooled_explosions,
		city_smoke,
		scenario,
		battlefield
	)
	var effect_to_recycle := prewarmer.effect_to_recycle
	if effect_to_recycle != null and not available.has(effect_to_recycle):
		recycle(effect_to_recycle)
	prepared = true

func recycle(effect: ExplosionEffect) -> void:
	effect.reparent(self, false)
	available.append(effect)
