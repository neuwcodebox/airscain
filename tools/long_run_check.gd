extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")
const TARGET_DURATION := 600.0
const STEP := 0.1

var main: AirscainMain
var placement_candidates: Array[Vector3] = []
var next_candidate: int = 0
var radar_placed: bool = false
var command_post_placed: bool = false
var tracking_radar_placed: bool = false
var support_facility_count: int = 0
var laser_count: int = 0
var next_layer_index: int = 0

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
			var ammunition := _ammunition_totals()
			_fail("game over at %.1f seconds; neutralized=%d defenses=%d active=%d tracks=%d ammo=%d+%d depleted=%d" % [main.session.survival_time, main.session.neutralized_count, main.session.defense_count, main.registry.count(), main.player_knowledge.get("tracks").size(), ammunition.rounds, ammunition.reserve, ammunition.depleted])
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
	if not radar_placed:
		var radar_definition := main.scenario.available_defenses[1]
		for position: Vector3 in placement_candidates:
			if main.session.budget < radar_definition.price:
				break
			var radar_result: Dictionary = main.session.request_placement(radar_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if radar_result.success:
				radar_placed = true
				break
	if not command_post_placed:
		var command_definition := main.scenario.available_defenses[2]
		for position: Vector3 in placement_candidates:
			if main.session.budget < command_definition.price:
				break
			var command_result: Dictionary = main.session.request_placement(command_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if command_result.success:
				command_post_placed = true
				break
	var required_support_count := 2 if main.session.defense_count >= 12 else 1
	if support_facility_count < required_support_count and main.session.defense_count >= 4:
		var support_definition := main.scenario.available_defenses[5]
		if main.session.budget < support_definition.price:
			_request_low_ammunition_resupply()
			return
		for position: Vector3 in placement_candidates:
			var support_result: Dictionary = main.session.request_placement(support_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if support_result.success:
				support_facility_count += 1
				break
	if not tracking_radar_placed and support_facility_count > 0:
		var tracking_definition := main.scenario.available_defenses[3]
		if main.session.budget < tracking_definition.price:
			_request_low_ammunition_resupply()
			return
		for position: Vector3 in placement_candidates:
			var tracking_result: Dictionary = main.session.request_placement(tracking_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if tracking_result.success:
				tracking_radar_placed = true
				break
	while next_candidate < placement_candidates.size():
		var layer_indices: Array[int] = [0, 4, 0, 6]
		var definition_index := layer_indices[next_layer_index]
		if definition_index == 6 and laser_count >= support_facility_count:
			next_layer_index = (next_layer_index + 1) % layer_indices.size()
			continue
		var definition: DefenseDefinition = main.scenario.available_defenses[definition_index]
		if main.session.budget < definition.price:
			break
		var position := placement_candidates[next_candidate]
		next_candidate += 1
		var result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
		if result.success:
			if definition_index == 6:
				laser_count += 1
			next_layer_index = (next_layer_index + 1) % layer_indices.size()
	_request_low_ammunition_resupply()

func _request_low_ammunition_resupply() -> void:
	for defense: DefenseUnit in main.defenses:
		if defense is ArmedDefenseUnit and (defense as ArmedDefenseUnit).uses_ammunition():
			var armed := defense as ArmedDefenseUnit
			if armed.magazine.reserve <= int(float(armed.magazine.reserve_capacity) * 0.25):
				armed.request_resupply()

func _fail(message: String) -> void:
	push_error("LONG_RUN_FAILED: %s" % message)
	quit(1)

func _ammunition_totals() -> Dictionary:
	var rounds := 0
	var reserve := 0
	var depleted := 0
	for defense: DefenseUnit in main.defenses:
		if defense is ArmedDefenseUnit and (defense as ArmedDefenseUnit).uses_ammunition():
			var armed := defense as ArmedDefenseUnit
			rounds += armed.magazine.rounds
			reserve += armed.magazine.reserve
			if armed.magazine.is_depleted():
				depleted += 1
	return {"rounds": rounds, "reserve": reserve, "depleted": depleted}
