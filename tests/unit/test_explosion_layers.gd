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
