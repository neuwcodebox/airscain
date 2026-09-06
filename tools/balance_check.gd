extends SceneTree
## Fixed-sector balance probe: kind seed [--low] [--baseline].
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
	var args := OS.get_cmdline_user_args()
	var kind := args[0] if args.size() > 0 else "gun"
	var world_seed := int(args[1]) if args.size() > 1 else 73129
	var low_only := args.has("--low")
	var baseline := args.has("--baseline")
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
		var gun_definition := main.scenario.available_defenses[4] as CloseInGunDefinition
		gun_definition.magazine_capacity = 120
		gun_definition.reserve_ammunition = 120
		gun_definition.resupply_cost = 6
	for argument: String in args:
		if argument.begins_with("--fuze="):
			main.scenario.threat_entries[1].threat_definition.missile_fuze_response = float(argument.trim_prefix("--fuze="))
		if argument.begins_with("--rack="):
			(main.scenario.available_defenses[4] as CloseInGunDefinition).magazine_capacity = int(argument.trim_prefix("--rack="))
	for x: int in range(260, 501, 25):
		for z: int in range(-225, 226, 25):
			candidates.append(Vector3(x, main.battlefield.terrain_height(x, z), z))
	if not buy(1, Vector3(300,0,-60)) or not buy(3, Vector3(300,0,60)):
		quit(2)
		return
	var support_count := 4 if kind == "energy" else (3 if kind == "mixed" else 2)
	for i: int in support_count:
		if not buy(5, Vector3(350,0,-150 + i * 300.0 / maxf(1, support_count - 1))):
			quit(2)
			return
	var composition: Array
	match kind:
		"gun": composition = [4,4,4,4,4,4,4,4,4,4,4,4,4]
		"missile": composition = [0,0,0,0,8,8,7]
		"energy": composition = [6,6,6,6,6,9]
		_: composition = [4,4,0,0,8,7,6]
	for i: int in composition.size():
		if not buy(int(composition[i]), Vector3(330 + (i % 2) * 55,0, -175 + 350.0 * i / maxf(1,composition.size()-1))):
			quit(2)
			return
	var initial_spending := 2000 - main.session.budget
	main.session.start_defense()
	main.director.enabled = false
	var sequence: Array = [[0,6],[1,12],[5,4],[0,8],[10,8],[1,16],[11,2],[9,2],[5,6],[0,8]]
	if low_only:
		sequence = []
		for i: int in 8:
			sequence.append_array([[0,8],[1,16],[5,6]])
	var wave := 0
	var spawned := 0
	for tick: int in (16200 if low_only else 10800):
		var time := float(tick) * STEP
		if wave < sequence.size() and time >= 5.0 + wave * (18.0 if low_only else 27.0):
			var entry := main.scenario.threat_entries[int(sequence[wave][0])]
			main.director.rng.seed = world_seed * 100 + wave
			main.director.elapsed = 0.0
			for i: int in int(sequence[wave][1]):
				main.director._spawn_entry(entry, -0.4 + 0.8 * float(i) / maxf(1,int(sequence[wave][1])-1), float(i)*3.0)
				spawned += 1
			wave += 1
		main.session.gameplay_delta(STEP)
		main._gameplay_step(STEP)
		for effect: Node in main.threat_parent.get_children():
			if not effect.is_queued_for_deletion() and effect.get_script() != null and effect.get_script().resource_path == "res://effects/air_strike_munition/air_strike_munition.gd":
				effect.call("_process", STEP)
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
	print("BALANCE_RESULT ", JSON.stringify({"kind":kind,"seed":world_seed,"low_only":low_only,"swarm_fuze_response":main.scenario.threat_entries[1].threat_definition.missile_fuze_response,"baseline":baseline,"purchase":initial_spending,"time":main.session.survival_time,"city":main.objective.current_integrity,"spawned":spawned,"kills":main.session.neutralized_count,"by_type":main.session.neutralized_by_type,"fired":fired,"projectile_outcomes":projectile_outcomes,"reload_asset_seconds":blocked,"supply_cost":main.session.support_spending,"budget":main.session.budget,"active":main.registry.hostile_count(),"positions":weapons.map(func(u:DefenseUnit)->String:return str(u.global_position))}))
	main.free()
	main = null
	weapons.clear()
	await process_frame
	quit.call_deferred()

func buy(index: int, preferred: Vector3) -> bool:
	var definition := main.scenario.available_defenses[index]
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
