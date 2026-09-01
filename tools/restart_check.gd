extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var first := MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(first)
	current_scene = first
	await process_frame
	var original_seed := first.scenario.world_seed
	var original_height := first.battlefield.terrain_height(341.0, -219.0)
	first.hud.restart_requested.emit(true)
	await process_frame
	await process_frame
	var same_world := current_scene as AirscainMain
	if same_world == null or same_world.scenario.world_seed != original_seed:
		_fail("same-seed restart changed the seed")
		return
	if not is_equal_approx(same_world.battlefield.terrain_height(341.0, -219.0), original_height):
		_fail("same-seed restart changed terrain")
		return
	same_world.hud.restart_requested.emit(false)
	await process_frame
	await process_frame
	var new_world := current_scene as AirscainMain
	if new_world == null or new_world.scenario.world_seed == original_seed:
		_fail("new-world restart retained the old seed")
		return
	if is_equal_approx(new_world.battlefield.terrain_height(341.0, -219.0), original_height):
		_fail("new-world restart retained sampled terrain")
		return
	print("RESTART_OK same_seed=%d new_seed=%d" % [original_seed, new_world.scenario.world_seed])
	quit(0)

func _fail(message: String) -> void:
	push_error("RESTART_FAILED: %s" % message)
	quit(1)
