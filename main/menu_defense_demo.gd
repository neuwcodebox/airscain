class_name MenuDefenseDemo
extends Node
## Bounded attract-mode policy; normal sensing and weapons still resolve combat.

const SPAWN_INTERVAL := 16.0
const MAX_HOSTILES := 2
const CITY_RECOVERY_DELAY := 12.0
var main: AirscainMain
var elapsed: float = 0.0
var until_spawn: float = 3.0
var spawn_count: int = 0
var city_recovery_remaining: float = 0.0

func configure(value: AirscainMain) -> void:
	main = value
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.camera_rig.set_process_unhandled_input(false)
	main.placement.set_process(false)
	main.placement.set_process_unhandled_input(false)
	main.combat_audio.enabled = false
	main.ui_audio.enabled = false
	(main.get_node("UI") as CanvasLayer).visible = false
	main.track_display.visible = false
	main.c2_overlay.visible = false
	(main.tactical_range_overlay as Node3D).visible = false
	_place(&"search_radar", Vector3(450, 0, -130))
	_place(&"command_post", Vector3(300, 0, 90))
	_place(&"missile_battery", Vector3(450, 0, 10))
	_place(&"short_range_missile", Vector3(300, 0, -180))
	_place(&"close_in_gun", Vector3(330, 0, -60))
	_place(&"support_facility", Vector3(380, 0, 30))
	main.session.start_defense()
	main.director.enabled = false
	main.objective.damage_received.connect(_schedule_city_recovery)

func _place(id: StringName, desired: Vector3) -> void:
	for definition: DefenseDefinition in main.scenario.available_defenses:
		if definition.id != id:
			continue
		for ring: int in 8:
			for spoke: int in 8:
				var angle := float(spoke) * TAU / 8.0
				var position := desired + Vector3(cos(angle), 0, sin(angle)) * float(ring * 20)
				var result := main.session.request_placement(definition, position, main.battlefield, main.defense_parent, main.registry, main.projectile_parent)
				if result.success:
					var unit := result.unit as DefenseUnit
					unit.identity_marker.visible = false
					unit.status_marker.visible = false
					unit.set_process(false)
					return
		return

func _process(delta: float) -> void:
	if not main.combat_effect_pool.prepared:
		return
	tick(minf(delta, 0.1))

func tick(delta: float) -> void:
	elapsed += delta
	if city_recovery_remaining > 0:
		city_recovery_remaining = maxf(0, city_recovery_remaining - delta)
		if city_recovery_remaining <= 0:
			main.objective.restore_integrity(main.objective.definition.maximum_integrity)
	until_spawn -= delta
	for unit: DefenseUnit in main.defenses:
		if unit.uses_ammunition() and unit.ammunition_needs_resupply():
			unit.complete_resupply()
		if unit.operational_ratio() < 1.0:
			unit.complete_repair()
	if until_spawn <= 0.0 and hostile_count() < MAX_HOSTILES:
		_spawn_small_attack()
		until_spawn = SPAWN_INTERVAL
	var steps := maxi(1, ceili(delta / AirscainMain.MAXIMUM_GAMEPLAY_STEP))
	for index: int in steps:
		main._gameplay_step(delta / steps)

func hostile_count() -> int:
	var count := 0
	for threat: ThreatUnit in main.registry.get_active():
		if threat.definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
			count += 1
	return count

func _spawn_small_attack() -> void:
	var entry := main.scenario.threat_entries[0]
	var threat := main.director._spawn_entry(entry, 0.0, 0.0) as AttackUav
	var angle := -0.4 + float(spawn_count % 3) * 0.22
	var position := Vector3(cos(angle), 0, sin(angle)) * 700.0
	position.y = main.battlefield.flight_surface_height(position.x, position.z) + 90.0
	threat.global_position = position
	threat.configure_mission(main.objective, main.battlefield, threat.target_point, 0.55, null, position)
	spawn_count += 1

func _schedule_city_recovery(_damage: int) -> void:
	city_recovery_remaining = CITY_RECOVERY_DELAY
