extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")
const TARGET_DURATION := 600.0
const STEP := 0.1

var main: AirscainMain
var placement_candidates: Array[Vector3] = []
var next_candidate: int = 0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	await process_frame
	main.set_process(false)
	_build_candidates()
	_buy_available_defenses()
	if main.session.defense_count < 1 or not main.session.start_defense():
		_fail("could not enter running phase")
		return
	main.director.enabled = true
	var steps := int(TARGET_DURATION / STEP)
	for index: int in steps:
		_buy_available_defenses()
		main._process(STEP)
		if main.session.phase == GameSession.Phase.GAME_OVER:
			_fail("game over at %.1f seconds" % main.session.survival_time)
			return
		if index % 10 == 0:
			await process_frame
	if main.session.survival_time < TARGET_DURATION - STEP:
		_fail("simulation did not reach target duration")
		return
	print("LONG_RUN_OK time=%.1f neutralized=%d defenses=%d pressure=%d active=%d integrity=%d" % [main.session.survival_time, main.session.neutralized_count, main.session.defense_count, main.session.highest_pressure, main.registry.count(), main.objective.current_integrity])
	quit(0)

func _build_candidates() -> void:
	var definition := main.scenario.available_defenses[0]
	for ring_radius: float in [220.0, 280.0, 350.0, 430.0]:
		for index: int in 16:
			var angle := TAU * float(index) / 16.0
			var position := Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)
			position.y = main.battlefield.terrain_height(position.x, position.z)
			if main.battlefield.placement_result(position, definition.placement_profile).valid:
				placement_candidates.append(position)

func _buy_available_defenses() -> void:
	var definition := main.scenario.available_defenses[0]
	while main.session.budget >= definition.price and next_candidate < placement_candidates.size():
		var position := placement_candidates[next_candidate]
		next_candidate += 1
		var result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
		if not result.success:
			continue

func _fail(message: String) -> void:
	push_error("LONG_RUN_FAILED: %s" % message)
	quit(1)
