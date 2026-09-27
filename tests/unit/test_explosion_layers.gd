extends GutTest

const EXPLOSION := preload("res://effects/explosion/explosion.tscn")

func _explosion(color: Color) -> ExplosionEffect:
	var explosion := add_child_autofree(EXPLOSION.instantiate()) as ExplosionEffect
	explosion.setup(color, 10.0)
	return explosion

func test_thermal_body_tint_follows_each_explosion_color_independently() -> void:
	var orange := _explosion(Color("ff8c35"))
	var red := _explosion(Color("ff3b24"))
	var orange_tint: Vector3 = (orange.smoke.draw_pass_1.surface_get_material(0) as ShaderMaterial).get_shader_parameter("tint")
	var red_tint: Vector3 = (red.smoke.draw_pass_1.surface_get_material(0) as ShaderMaterial).get_shader_parameter("tint")
	assert_ne(orange_tint, red_tint)
	assert_gt(orange_tint.y, red_tint.y, "주황 폭발은 붉은 폭발보다 노란 화염을 유지합니다")

func test_setup_emits_thermal_body_and_debris() -> void:
	var explosion := _explosion(Color("ff8c35"))
	assert_true(explosion.smoke.emitting)
	assert_true(explosion.debris.emitting)

func test_deactivated_pooled_explosion_stops_body_and_debris() -> void:
	var explosion := _explosion(Color("ff8c35"))
	explosion.deactivate()
	assert_false(explosion.smoke.emitting)
	assert_false(explosion.debris.emitting)

func test_only_three_simultaneous_explosions_keep_environment_lights() -> void:
	var explosions: Array[ExplosionEffect] = []
	for index: int in 6:
		explosions.append(_explosion(Color.ORANGE))
	var active := 0
	for explosion: ExplosionEffect in explosions:
		if explosion.blast_light.visible:
			active += 1
	assert_lte(active, ExplosionEffect.MAX_LIGHTS)
	for explosion: ExplosionEffect in explosions:
		explosion.deactivate()
