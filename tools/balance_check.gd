extends SceneTree
## Fixed-sector balance probe: kind seed [--low|--swarm] [--baseline]
##   [--laser-heat=N] [--laser-price=N] [--laser-count=N].
## Kinds: gun, missile, short, energy, laser, hpm, drone, mixed.
## Uses real 30 Hz combat, legal placement, fixed spawns, no reinvestment/repair.
## --baseline changes only in-memory gun stock to 120+120, pack cost 6.
## Remaining budget includes regular support and kill rewards, not raid rewards.

const MAIN := preload("res://main/main.tscn")
const STEP := 1.0 / 30.0
var main: AirscainMain
var fired: Dictionary = {}
var blocked: Dictionary = {}
var projectile_outcomes: Dictionary = {}
var weapons: Array[DefenseUnit] = []
var candidates: Array[Vector3] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	# Diagnostic runs advance the simulation without modal phase briefings.
	PlayerSettings.instance().values.briefings = false
	var args := OS.get_cmdline_user_args()
	var kind := args[0] if args.size() > 0 else "gun"
	var world_seed := int(args[1]) if args.size() > 1 else 73129
	var low_only := args.has("--low")
	var swarm_only := args.has("--swarm")
	low_only = low_only or swarm_only
	var baseline := args.has("--baseline")
	var laser_count := 4
	AirscainMain.requested_seed = world_seed
	main = MAIN.instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.combat_audio.enabled = false
	main.combat_audio.stop_all()
	main.session.budget = 2000
	main.session.update_pressure(20)
	main.director.enabled = false
	if baseline:
		var gun_definition := _definition(&"close_in_gun") as CloseInGunDefinition
		gun_definition.magazine_capacity = 120
		gun_definition.reserve_ammunition = 120
		gun_definition.resupply_cost = 6
	for argument: String in args:
		if argument.begins_with("--fuze="):
			main.scenario.threat_entries[1].threat_definition.missile_fuze_response = float(argument.trim_prefix("--fuze="))
		if argument.begins_with("--rack="):
			(_definition(&"close_in_gun") as CloseInGunDefinition).magazine_capacity = int(argument.trim_prefix("--rack="))
		if argument.begins_with("--laser-heat="):
			(_definition(&"high_energy_laser") as HighEnergyLaserDefinition).heat_capacity = float(argument.trim_prefix("--laser-heat="))
		if argument.begins_with("--laser-price="):
			_definition(&"high_energy_laser").price = int(argument.trim_prefix("--laser-price="))
		if argument.begins_with("--laser-count="):
			laser_count = maxi(1, int(argument.trim_prefix("--laser-count=")))
	for x: int in range(260, 501, 25):
		for z: int in range(-225, 226, 25):
			candidates.append(Vector3(x, main.battlefield.terrain_height(x, z), z))
	if not buy(&"search_radar", Vector3(300,0,-60)) or not buy(&"tracking_radar", Vector3(300,0,60)):
		quit(2)
		return
	var support_count: int
	match kind:
		"energy", "laser", "hpm": support_count = 3
		"drone": support_count = 0
		_: support_count = 2
	for i: int in support_count:
		if not buy(&"support_facility", Vector3(350,0,-150 + i * 300.0 / maxf(1, support_count - 1))):
			quit(2)
			return
	var composition: Array[StringName]
	match kind:
		"gun": composition.assign([&"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun", &"close_in_gun"])
		"missile": composition.assign([&"missile_battery", &"missile_battery", &"short_range_missile", &"short_range_missile", &"long_range_missile"])
		"short": composition.assign([&"short_range_missile", &"short_range_missile", &"short_range_missile", &"short_range_missile", &"short_range_missile", &"short_range_missile", &"short_range_missile"])
		"energy": composition.assign([&"high_energy_laser", &"high_energy_laser", &"high_energy_laser", &"high_power_microwave"])
		"laser":
			for i: int in laser_count:
				composition.append(&"high_energy_laser")
		"hpm": composition.assign([&"high_power_microwave", &"high_power_microwave", &"high_power_microwave"])
		"drone": composition.assign([&"interceptor_drone_defense", &"interceptor_drone_defense", &"interceptor_drone_defense", &"interceptor_drone_defense", &"interceptor_drone_defense", &"interceptor_drone_defense", &"interceptor_drone_defense"])
		"mixed": composition.assign([&"close_in_gun", &"missile_battery", &"short_range_missile", &"long_range_missile", &"high_energy_laser"])
		_:
			push_error("UNKNOWN_BALANCE_KIND " + kind)
			quit(2)
			return
	for i: int in composition.size():
		if not buy(composition[i], Vector3(330 + (i % 2) * 55,0, -175 + 350.0 * i / maxf(1,composition.size()-1))):
			quit(2)
			return
	var initial_spending := 2000 - main.session.budget
	main.session.start_defense()
	main.director.enabled = false
	var sequence: Array = [[0,6],[1,12],[5,4],[0,8],[10,8],[1,16],[11,2],[9,2],[5,6],[0,8]]
	if low_only:
		sequence = []
		if swarm_only:
			for i: int in 15:
				sequence.append([1, 16])
		else:
			for i: int in 8:
				sequence.append_array([[0,8],[1,16],[5,6]])
	var wave := 0
	var spawned := 0
	for tick: int in (16200 if low_only else 10800):
		var time := float(tick) * STEP
		var wave_interval := 10.0 if swarm_only else (18.0 if low_only else 27.0)
		if wave < sequence.size() and time >= 5.0 + wave * wave_interval:
			var entry := main.scenario.threat_entries[int(sequence[wave][0])]
			main.director.rng.seed = world_seed * 100 + wave
			main.director.elapsed = 0.0
			var member_delay := (0.1 if swarm_only else 0.35) if entry.threat_definition.signature_class == &"small_uav" else 3.0
			for i: int in int(sequence[wave][1]):
				main.director._spawn_entry(entry, -0.4 + 0.8 * float(i) / maxf(1,int(sequence[wave][1])-1), float(i) * member_delay)
				spawned += 1
			wave += 1
		main.session.gameplay_delta(STEP)
		main._gameplay_step(STEP)
		for unit: DefenseUnit in weapons:
			var label := String(unit.definition.id)
			if unit.reload_display_magazine() != null:
				blocked[label] = float(blocked.get(label,0.0)) + STEP
			if unit is HighEnergyLaser and (unit as HighEnergyLaser).energy_state.overheated:
				blocked["laser_overheat"] = float(blocked.get("laser_overheat",0.0)) + STEP
		if main.session.phase == GameSession.Phase.GAME_OVER:
			break
		if tick % 30 == 0:
			await process_frame
	print("BALANCE_RESULT ", JSON.stringify({"kind":kind,"seed":world_seed,"low_only":low_only,"swarm_only":swarm_only,"swarm_fuze_response":main.scenario.threat_entries[1].threat_definition.missile_fuze_response,"baseline":baseline,"purchase":initial_spending,"time":main.session.survival_time,"city":main.objective.current_integrity,"spawned":spawned,"kills":main.session.neutralized_count,"by_type":main.session.neutralized_by_type,"fired":fired,"projectile_outcomes":projectile_outcomes,"reload_asset_seconds":blocked,"supply_cost":main.session.support_spending,"budget":main.session.budget,"active":main.registry.hostile_count(),"positions":weapons.map(func(u:DefenseUnit)->String:return str(u.global_position))}))
	main.free()
	main = null
	weapons.clear()
	await process_frame
	quit.call_deferred()

func buy(definition_id: StringName, preferred: Vector3) -> bool:
	var definition := _definition(definition_id)
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a:Vector3,b:Vector3)->bool:return Vector2(a.x-preferred.x,a.z-preferred.z).length_squared() < Vector2(b.x-preferred.x,b.z-preferred.z).length_squared())
	for position: Vector3 in sorted:
		var result := main.session.request_placement(definition,position,main.battlefield,main.defense_parent,main.registry,main.projectile_parent)
		if result.success:
			var unit := result.unit as DefenseUnit
			if unit.supports_engagement_controls():
				weapons.append(unit)
				unit.projectile_launched.connect(_projectile_launched)
				if unit is CloseInGun:
					(unit as CloseInGun).gunfire.round_detonated.connect(_gun_round_ended)
				unit.weapon_fired.connect(func(source:DefenseUnit,_low:bool)->void:
					var key := String(source.definition.id)
					fired[key] = int(fired.get(key,0)) + 1)
			return true
	push_error("PLACEMENT_FAILED " + definition.id + " budget=" + str(main.session.budget))
	return false

func _definition(definition_id: StringName) -> DefenseDefinition:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id == definition_id:
			return definition
	return null

func _projectile_launched(_unit: DefenseUnit, projectile: Node) -> void:
	if projectile is HomingInterceptor:
		(projectile as HomingInterceptor).flight_ended.connect(_missile_ended)
		(projectile as HomingInterceptor).target_hit.connect(_missile_hit)

func _missile_hit(threat: ThreatUnit, nominal_damage: float) -> void:
	var key := "missile_hit_" + String(threat.definition.id)
	projectile_outcomes[key] = int(projectile_outcomes.get(key, 0)) + 1
	projectile_outcomes["missile_effective_damage"] = float(projectile_outcomes.get("missile_effective_damage", 0.0)) + minf(threat.health, nominal_damage)
	projectile_outcomes["missile_excess_damage"] = float(projectile_outcomes.get("missile_excess_damage", 0.0)) + maxf(0.0, nominal_damage - threat.health)

func _missile_ended(detonated: bool) -> void:
	# This signal also covers timeout/self-destruction, not only hits.
	var key := "missile_detonated" if detonated else "missile_ended"
	projectile_outcomes[key] = int(projectile_outcomes.get(key, 0)) + 1

func _gun_round_ended(_position: Vector3, reason: StringName) -> void:
	var key := "gun_" + String(reason)
	projectile_outcomes[key] = int(projectile_outcomes.get(key, 0)) + 1
