class_name MenuDefenseDemo
extends Node
## Bounded attract-mode policy; normal sensing and weapons still resolve combat.

const SPAWN_INTERVAL := 10.0
const INITIAL_SPAWN_DELAY := 1.5
const MAX_HOSTILES := 2
const CITY_RECOVERY_DELAY := 12.0
const OFFSCREEN_SPAWN_MARGIN := 15.0
const SPAWN_RADIUS_STEP := 40.0
var main: AirscainMain
var elapsed: float = 0.0
var until_spawn: float = INITIAL_SPAWN_DELAY
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
	for unit: DefenseUnit in main.defenses:
		unit.identity_marker.hide()
		unit.status_marker.hide()
		unit.set_process(false)
	_place(&"search_radar", Vector3(230, 0, -110))
	_place(&"missile_battery", Vector3(230, 0, 10))
	_place(&"short_range_missile", Vector3(220, 0, -160))
	_place(&"close_in_gun", Vector3(220, 0, -50))
	_place(&"support_facility", Vector3(230, 0, 90))
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
	var angle := -0.4 + float(spawn_count % 3) * 0.22
	var threat := main.director._spawn_entry(entry, angle, 0.0) as AttackUav
	if threat == null:
		return
	var position := spawn_position_just_outside_camera(entry, angle)
	threat.global_position = position
	threat.configure_mission(main.objective, main.battlefield, threat.target_point, 0.55, null, position)
	spawn_count += 1

func spawn_position_just_outside_camera(entry: ThreatSpawnEntry, angle: float) -> Vector3:
	var camera := main.camera_rig.camera
	var maximum_radius := main.scenario.battlefield_size * entry.threat_definition.spawn_radius_multiplier()
	var radius := 0.0
	var position := _spawn_position_at(entry, angle, radius)
	while radius < maximum_radius and camera.is_position_in_frustum(position):
		radius = minf(maximum_radius, radius + SPAWN_RADIUS_STEP)
		position = _spawn_position_at(entry, angle, radius)
	var inside_radius := maxf(0.0, radius - SPAWN_RADIUS_STEP)
	var outside_radius := radius
	for _index: int in 8:
		var midpoint := (inside_radius + outside_radius) * 0.5
		if camera.is_position_in_frustum(_spawn_position_at(entry, angle, midpoint)):
			inside_radius = midpoint
		else:
			outside_radius = midpoint
	return _spawn_position_at(entry, angle, minf(maximum_radius, outside_radius + OFFSCREEN_SPAWN_MARGIN))

func _spawn_position_at(entry: ThreatSpawnEntry, angle: float, radius: float) -> Vector3:
	var position := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	position.y = main.battlefield.flight_surface_height(position.x, position.z) + entry.threat_definition.spawn_altitude()
	return position

func _schedule_city_recovery(_damage: int) -> void:
	city_recovery_remaining = CITY_RECOVERY_DELAY
