extends SceneTree

const MAIN_SCENE := preload("res://main/main.tscn")
const TARGET_DURATION := 600.0
const STEP := 0.1

var main: AirscainMain
var placement_candidates: Array[Vector3] = []
var sensor_candidates: Array[Vector3] = []
var next_candidate: int = 0
var radar_count: int = 0
var command_post_count: int = 0
var tracking_radar_count: int = 0
var support_facility_count: int = 0
var laser_count: int = 0
var hpm_count: int = 0
var next_layer_index: int = 0
var spawned_by_type: Dictionary[String, int] = {}
var leaked_by_type: Dictionary[String, int] = {}
var process_samples_usec: Array[int] = []

func _init() -> void:
	AudioServer.set_bus_mute(0, true)
	call_deferred("run")

func run() -> void:
	_apply_requested_seed()
	main = MAIN_SCENE.instantiate() as AirscainMain
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.combat_audio.call("stop_all")
	main.director.threat_spawned.connect(_track_spawned_threat)
	_build_candidates()
	_buy_available_defenses()
	if main.session.defense_count < 1 or not main.session.start_defense():
		_fail("could not enter running phase")
		return
	main.director.enabled = true
	var steps := int(TARGET_DURATION / STEP)
	for index: int in steps:
		_buy_available_defenses()
		var started_at := Time.get_ticks_usec()
		main._process(STEP)
		process_samples_usec.append(Time.get_ticks_usec() - started_at)
		if main.session.phase == GameSession.Phase.GAME_OVER:
			var ammunition := _ammunition_totals()
			_fail("game over at %.1f seconds; neutralized=%d defenses=%d active=%d tracks=%d ammo=%d+%d depleted=%d deployed=%s munitions=%s spawned=%s leaked=%s" % [main.session.survival_time, main.session.neutralized_count, main.session.defense_count, main.registry.count(), main.player_knowledge.get("tracks").size(), ammunition.rounds, ammunition.reserve, ammunition.depleted, _deployed_by_type(), _munition_inventory(), spawned_by_type, leaked_by_type])
			return
		if index % 10 == 0:
			await process_frame
	if main.session.survival_time < TARGET_DURATION - STEP:
		_fail("simulation did not reach target duration")
		return
	process_samples_usec.sort()
	var total_usec := 0
	for sample: int in process_samples_usec:
		total_usec += sample
	var average_ms := float(total_usec) / float(process_samples_usec.size()) / 1000.0
	var p95_ms := float(process_samples_usec[mini(process_samples_usec.size() - 1, int(floor(float(process_samples_usec.size()) * 0.95)))]) / 1000.0
	print("LONG_RUN_OK time=%.1f neutralized=%d defenses=%d pressure=%d active=%d integrity=%d budget=%d support=%d windows=%d avg_ms=%.3f p95_ms=%.3f" % [main.session.survival_time, main.session.neutralized_count, main.session.defense_count, main.session.highest_pressure, main.registry.count(), main.objective.current_integrity, main.session.budget, main.session.support_payment_count, main.session.completed_attack_windows, average_ms, p95_ms])
	main.set_process(false)
	main.combat_audio.call("stop_all")
	main.free()
	main = null
	placement_candidates.clear()
	sensor_candidates.clear()
	for index: int in 3:
		await process_frame
	quit(0)

func _apply_requested_seed() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			AirscainMain.requested_seed = int(argument.trim_prefix("--seed="))

func _build_candidates() -> void:
	var definition := main.scenario.available_defenses[0]
	for ring_radius: float in [220.0, 280.0, 350.0, 430.0]:
		for index: int in 16:
			var angle := TAU * float(index) / 16.0
			var position := Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)
			position.y = main.battlefield.terrain_height(position.x, position.z)
			if main.battlefield.placement_result(position, definition.placement_profile).valid:
				placement_candidates.append(position)
	var radar_definition := main.scenario.available_defenses[1]
	for rooftop_pad: Dictionary in main.battlefield.rooftop_pads:
		var rooftop_position: Vector3 = rooftop_pad.position
		if main.battlefield.placement_result(rooftop_position, radar_definition.placement_profile).valid:
			sensor_candidates.append(rooftop_position)
	for angle: float in [0.0, PI, PI * 0.5, PI * 1.5, PI * 0.25, PI * 1.25, PI * 0.75, PI * 1.75]:
		for radius: float in [680.0, 620.0, 560.0]:
			var position := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			position.y = main.battlefield.terrain_height(position.x, position.z)
			if main.battlefield.placement_result(position, radar_definition.placement_profile).valid:
				sensor_candidates.append(position)
				break

func _buy_available_defenses() -> void:
	var required_sensor_count := 2 if main.session.defense_count >= 18 else 1
	if radar_count < required_sensor_count:
		var radar_definition := main.scenario.available_defenses[1]
		var radar_positions: Array[Vector3] = placement_candidates if radar_count == 0 or sensor_candidates.is_empty() else sensor_candidates
		for position: Vector3 in radar_positions:
			if main.session.budget < radar_definition.price:
				break
			var radar_result: Dictionary = main.session.request_placement(radar_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if radar_result.success:
				radar_count += 1
				break
	if command_post_count < 1:
		var command_definition := main.scenario.available_defenses[2]
		for position: Vector3 in placement_candidates:
			if main.session.budget < command_definition.price:
				break
			var command_result: Dictionary = main.session.request_placement(command_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if command_result.success:
				command_post_count += 1
				break
	var required_support_count := 1
	if main.session.defense_count >= 24:
		required_support_count = 3
	elif main.session.defense_count >= 12:
		required_support_count = 2
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
	var required_tracking_count := 2 if support_facility_count >= 2 else 1
	if tracking_radar_count < required_tracking_count and support_facility_count > 0:
		var tracking_definition := main.scenario.available_defenses[3]
		if tracking_definition.unlock_pressure_level > main.session.current_pressure:
			_request_low_ammunition_resupply()
			return
		if main.session.budget < tracking_definition.price:
			_request_low_ammunition_resupply()
			return
		for position: Vector3 in placement_candidates:
			var tracking_result: Dictionary = main.session.request_placement(tracking_definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
			if tracking_result.success:
				tracking_radar_count += 1
				break
	while next_candidate < placement_candidates.size():
		var layer_indices: Array[int] = [0, 4, 0, 6]
		if main.session.defense_count >= 16:
			layer_indices = [4, 7, 10, 4, 9, 8]
		var definition_index := layer_indices[next_layer_index]
		if (definition_index == 6 or definition_index == 9) and laser_count + hpm_count >= support_facility_count:
			next_layer_index = (next_layer_index + 1) % layer_indices.size()
			continue
		var definition: DefenseDefinition = main.scenario.available_defenses[definition_index]
		if definition.unlock_pressure_level > main.session.current_pressure:
			next_layer_index = (next_layer_index + 1) % layer_indices.size()
			continue
		if main.session.budget < definition.price:
			break
		var position := placement_candidates[next_candidate]
		next_candidate += 1
		var result: Dictionary = main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
		if result.success:
			if definition_index == 6:
				laser_count += 1
			elif definition_index == 9:
				hpm_count += 1
			next_layer_index = (next_layer_index + 1) % layer_indices.size()
	_request_low_ammunition_resupply()

func _request_low_ammunition_resupply() -> void:
	for defense: DefenseUnit in main.defenses:
		if defense is ArmedDefenseUnit and (defense as ArmedDefenseUnit).uses_ammunition():
			var armed := defense as ArmedDefenseUnit
			if armed.ammunition_reserve_ratio() <= 0.25:
				armed.request_resupply()

func _fail(message: String) -> void:
	push_error("LONG_RUN_FAILED: %s" % message)
	quit(1)

func _track_spawned_threat(threat: ThreatUnit) -> void:
	var threat_id := String(threat.definition.id)
	spawned_by_type[threat_id] = spawned_by_type.get(threat_id, 0) + 1
	threat.resolved.connect(func(_unit: ThreatUnit, neutralized: bool, _reward: int) -> void:
		if not neutralized:
			leaked_by_type[threat_id] = leaked_by_type.get(threat_id, 0) + 1
	)

func _deployed_by_type() -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	for defense: DefenseUnit in main.defenses:
		var defense_id := String(defense.definition.id)
		result[defense_id] = result.get(defense_id, 0) + 1
	return result

func _munition_inventory() -> Dictionary[String, Vector2i]:
	var result: Dictionary[String, Vector2i] = {}
	for defense: DefenseUnit in main.defenses:
		if not defense is MissileBattery:
			continue
		for munition_id: StringName in (defense as MissileBattery).magazines:
			var munition_magazine: WeaponMagazine = (defense as MissileBattery).magazines[munition_id]
			var current: Vector2i = result.get(String(munition_id), Vector2i.ZERO)
			result[String(munition_id)] = current + Vector2i(munition_magazine.rounds, munition_magazine.reserve)
	return result

func _ammunition_totals() -> Dictionary:
	var rounds := 0
	var reserve := 0
	var depleted := 0
	for defense: DefenseUnit in main.defenses:
		if defense is ArmedDefenseUnit and (defense as ArmedDefenseUnit).uses_ammunition():
			var magazines_to_count: Array[WeaponMagazine] = []
			if defense is MissileBattery:
				for munition_magazine: WeaponMagazine in (defense as MissileBattery).magazines.values():
					magazines_to_count.append(munition_magazine)
			else:
				magazines_to_count.append((defense as ArmedDefenseUnit).magazine)
			for weapon_magazine: WeaponMagazine in magazines_to_count:
				rounds += weapon_magazine.rounds
				reserve += weapon_magazine.reserve
				if weapon_magazine.is_depleted():
					depleted += 1
	return {"rounds": rounds, "reserve": reserve, "depleted": depleted}
