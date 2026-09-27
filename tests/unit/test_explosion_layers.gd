extends GutTest

const EXPLOSION := preload("res://effects/explosion/explosion.tscn")

func _explosion(color: Color) -> ExplosionEffect:
	var explosion := add_child_autofree(EXPLOSION.instantiate()) as ExplosionEffect
	explosion.setup(color, 10.0)
	return explosion

func test_fire_body_tint_follows_each_explosion_color_independently() -> void:
	var orange := _explosion(Color("ff8c35"))
	var red := _explosion(Color("ff3b24"))
	var orange_tint: Color = (orange.fire_body.draw_pass_1.surface_get_material(0) as ShaderMaterial).get_shader_parameter("tint")
	var red_tint: Color = (red.fire_body.draw_pass_1.surface_get_material(0) as ShaderMaterial).get_shader_parameter("tint")
	assert_ne(orange_tint, red_tint)
	assert_gt(orange_tint.g, red_tint.g, "주황 폭발은 붉은 폭발보다 노란 화염을 유지합니다")

func test_setup_emits_fire_and_debris_layers() -> void:
	var explosion := _explosion(Color("ff8c35"))
	assert_true(explosion.fire_body.emitting)
	assert_true(explosion.debris.emitting)

func test_deactivated_pooled_explosion_stops_fire_and_debris_layers() -> void:
	var explosion := _explosion(Color("ff8c35"))
	explosion.deactivate()
	assert_false(explosion.fire_body.emitting)
	assert_false(explosion.debris.emitting)

func test_dense_explosions_keep_each_impact_and_smoke_then_restore_full_detail_on_reuse() -> void:
	var pool := add_child_autofree(CombatEffectPool.new()) as CombatEffectPool
	var parent := add_child_autofree(Node3D.new()) as Node3D
	var effects: Array[ExplosionEffect] = []
	for index: int in CombatEffectPool.DETAILED_EXPLOSION_LIMIT + 2:
		effects.append(pool.spawn_explosion(parent, Vector3(index * 20, 70, 0), Color.ORANGE, 12))
		var effect: ExplosionEffect = effects.back()
		assert_true(effect.visible, "폭발 %d의 본체가 표시됩니다" % index)
		assert_true(effect.flash.visible, "폭발 %d의 섬광이 표시됩니다" % index)
		assert_true(effect.smoke.visible, "폭발 %d의 잔연이 표시됩니다" % index)
		assert_true(effect.smoke.emitting, "폭발 %d의 잔연이 방출됩니다" % index)
		assert_eq(effect.fire_body.emitting, index < CombatEffectPool.DETAILED_EXPLOSION_LIMIT, "폭발 %d의 화염 밀도" % index)
		assert_eq(effect.smoke.shadow_particles.visible, index < CombatEffectPool.DETAILED_EXPLOSION_LIMIT, "폭발 %d의 연기 그림자 밀도" % index)
	var limited := effects[CombatEffectPool.DETAILED_EXPLOSION_LIMIT]
	for index: int in CombatEffectPool.DETAILED_EXPLOSION_LIMIT:
		effects[index]._process(effects[index].duration)
	limited._process(limited.duration)
	var reused := pool.spawn_explosion(parent, Vector3.ZERO, Color.CYAN, 12)
	assert_same(reused, limited)
	assert_true(reused.fire_body.visible)
	assert_true(reused.fire_body.emitting)
	assert_true(reused.sparks.emitting)
	assert_true(reused.smoke.shadow_particles.visible)
