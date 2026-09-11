extends SceneTree
## Identical legal layout, natural raids, 30 Hz combat for 15 minutes.
## Fixed policy: repair damaged assets every 5s; restore city below 75%.
## Advanced purchases are unlocked only during setup. No reinvestment.
const STEP := 1.0 / 30.0
var main: AirscainMain
var candidates: Array[Vector3] = []
var spawned: Dictionary = {}
var released: Dictionary = {}
var countermeasure_charges: Dictionary[int, int] = {}
var countermeasure_spent := 0
var damage := 0.0
var repair_spent := 0
var city_spent := 0
var repair_asset_seconds := 0.0
var jam_seconds := 0.0
var jam_peak := 0.0
var asset_missions := 0
var snapshots: Array[Dictionary] = []
var ew_records: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var world_seed := int(args[0]) if not args.is_empty() else 73129
	AirscainMain.requested_seed = world_seed
	main = preload("res://main/main.tscn").instantiate() as AirscainMain
	root.add_child(main)
	while not main.combat_effect_pool.prepared:
		await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.ui_audio.enabled = false
	main.combat_audio.enabled = false
	main.combat_audio.stop_all()
	main.session.update_pressure(20)
	if args.has("--ew"):
		await check_ew()
		return
	for x: int in range(260, 501, 20):
		for z: int in range(-220, 221, 20):
			candidates.append(Vector3(x, main.battlefield.terrain_height(x,z), z))
	for item: Array in [[1,-60],[3,60],[5,0],[0,-150],[0,150],[4,-80],[6,80],[7,0]]:
		if not buy(int(item[0]), Vector3(340,0,float(item[1]))):
			quit(2)
			return
	var purchase := main.session.defense_spending
	for unit: DefenseUnit in main.defenses:
		unit.damage_received.connect(func(_unit:DefenseUnit, amount:float, _ratio:float)->void: damage += amount)
	main.director.threat_spawned.connect(on_spawned)
	main.support_manager.task_requested.connect(func(kind:StringName, unit:DefenseUnit)->void:
		if kind == &"repair": repair_spent += unit.repair_cost())
	main.session.current_pressure = 1
	main.session.highest_pressure = 1
	main.session.start_defense()
	for tick: int in 27000:
		main.session.gameplay_delta(STEP)
		main._gameplay_step(STEP)
		if tick % 150 == 0:
			for unit: DefenseUnit in main.defenses:
				if unit.operational_ratio() < 0.75:
					main.support_manager.request_repair(unit)
			if main.objective.current_integrity < 75:
				var budget := main.session.budget
				main._on_city_restoration_requested()
				city_spent += budget - main.session.budget
		var jam := 0.0
		for unit: DefenseUnit in main.defenses:
			if (unit.c2_roles() & DefenseUnit.C2Role.SENSOR) != 0:
				jam = maxf(jam, main.registry.jamming_at(unit.global_position))
			if main.support_manager.task_status(unit).begins_with("수리"):
				repair_asset_seconds += STEP
		jam_peak = maxf(jam_peak, jam)
		if jam > 0.1: jam_seconds += STEP
		for threat: ThreatUnit in main.registry.get_active():
			if threat.definition.jamming_strength > 0.0:
				var record: Dictionary = ew_records[threat.runtime_id]
				record.last_seen = main.session.survival_time
				for unit: DefenseUnit in main.defenses:
					if (unit.c2_roles() & DefenseUnit.C2Role.SENSOR) != 0:
						record.closest_sensor = minf(float(record.closest_sensor), unit.global_position.distance_to(threat.global_position))
			if countermeasure_charges.has(threat.runtime_id):
				countermeasure_spent += maxi(0, countermeasure_charges[threat.runtime_id] - threat.countermeasure_charges_remaining)
				countermeasure_charges[threat.runtime_id] = threat.countermeasure_charges_remaining
		if tick % 2700 == 0:
			snapshots.append({"time":main.session.survival_time,"city":main.objective.current_integrity,"budget":main.session.budget,"pressure":main.session.current_pressure})
		if main.session.phase == GameSession.Phase.GAME_OVER: break
		if tick % 30 == 0: await process_frame
	print("COMBAT_ECONOMY_RESULT ", JSON.stringify({"seed":world_seed,"time":main.session.survival_time,"city":main.objective.current_integrity,"purchase":purchase,"budget":main.session.budget,"support_income":main.session.total_support_received,"kill_income":main.session.neutralized_reward_total,"maintenance_total":main.session.support_spending,"repair_cost":repair_spent,"resupply_cost":main.session.support_spending - repair_spent - city_spent,"city_restore_cost":city_spent,"asset_damage":damage,"asset_missions":asset_missions,"repair_asset_seconds":repair_asset_seconds,"jam_seconds_above_0_1":jam_seconds,"jam_peak":jam_peak,"countermeasure_spent":countermeasure_spent,"ew_records":ew_records,"spawned":spawned,"released":released,"kills":main.session.neutralized_count,"snapshots":snapshots,"positions":main.defenses.map(func(u:DefenseUnit)->String:return str(u.global_position))}))
	main.free()
	main = null
	await process_frame
	await process_frame
	quit()

func buy(index: int, preferred: Vector3) -> bool:
	var definition := main.scenario.available_defenses[index]
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a:Vector3,b:Vector3)->bool:return Vector2(a.x-preferred.x,a.z-preferred.z).length_squared() < Vector2(b.x-preferred.x,b.z-preferred.z).length_squared())
	for position: Vector3 in sorted:
		var result := main.session.request_placement(definition,position,main.battlefield,main.defense_parent,main.registry,main.projectile_parent)
		if result.success: return true
	push_error("PLACEMENT_FAILED " + definition.id + " budget=" + str(main.session.budget))
	return false

func on_spawned(threat: ThreatUnit) -> void:
	if threat.definition.jamming_strength > 0.0:
		ew_records[threat.runtime_id] = {"spawn":main.session.survival_time,"last_seen":0.0,"closest_sensor":100000.0,"target":str((threat as AttackUav).mission_runtime.fixed_target)}
	var id := String(threat.definition.id)
	spawned[id] = int(spawned.get(id,0)) + 1
	countermeasure_charges[threat.runtime_id] = threat.countermeasure_charges_remaining
	if threat is AttackUav and (threat as AttackUav).mission_runtime.target_defense_id > 0:
		asset_missions += 1
	threat.threat_released.connect(func(_child:ThreatUnit)->void: released[id] = int(released.get(id,0)) + 1)

func check_ew() -> void:
	for x: int in range(850, 1101, 20):
		for z: int in range(-150, 151, 20):
			candidates.append(Vector3(x, main.battlefield.terrain_height(x,z), z))
	if not buy(1, Vector3(900,0,0)):
		quit(2)
		return
	var radar: DefenseUnit = main.defenses.back()
	main.enemy_knowledge.record_emission(radar)
	var jammer := main.director._spawn_entry(main.scenario.threat_entries[7], 0.0, 0.0) as AttackUav
	jammer.global_position = radar.global_position + Vector3(650,180,0)
	var active_time := 0.0
	var covered := 0.0
	var strength := 0.0
	for tick: int in 7200:
		if not is_instance_valid(jammer) or jammer.is_queued_for_deletion(): break
		jammer.gameplay_tick(STEP)
		if jammer.mission_runtime.phase == ThreatMissionRuntime.Phase.ACTING:
			active_time += STEP
			var jam := main.registry.jamming_at(radar.global_position)
			if jam > 0.1: covered += STEP
			strength = maxf(strength, jam)
		if tick % 30 == 0: await process_frame
	print("EW_POSITION_RESULT ", JSON.stringify({"active_time":active_time,"covered_time":covered,"peak_strength":strength,"radar_position":str(radar.global_position)}))
	main.free()
	main = null
	await process_frame
	quit()
