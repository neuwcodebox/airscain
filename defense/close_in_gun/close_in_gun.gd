class_name CloseInGun
extends ArmedDefenseUnit

const TURRET_AIMER := preload("res://defense/turret_aimer.gd")

@export var turret_turn_speed_degrees: float = 120.0
@export var barrel_elevation_speed_degrees: float = 90.0
@export var firing_alignment_degrees: float = 3.0

var registry: ThreatRegistry
var cooldown: float = 0.0
var rng := RandomNumberGenerator.new()
var _definition: CloseInGunDefinition
var flash_remaining: float = 0.0
var gunfire: GunfireRuntime
var barrel_spin_speed: float = 0.0
var barrel_spin_remaining: float = 0.0

@onready var turret: Node3D = $Turret
@onready var elevation: Node3D = $Turret/Elevation
@onready var muzzle: Marker3D = $Turret/Elevation/Muzzle
@onready var barrel_cluster: Node3D = $Turret/Elevation/BarrelCluster
@onready var muzzle_flash: MeshInstance3D = $MuzzleFlash
@onready var muzzle_light: OmniLight3D = $MuzzleLight

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as CloseInGunDefinition
	rng.seed = id_value ^ 0x4C11DB7
	magazine.setup(_definition.magazine_capacity, _definition.reserve_ammunition, _definition.reload_duration)
	gunfire = GunfireRuntime.new()
	gunfire.name = "Gunfire"
	add_child(gunfire)
	gunfire.round_fired.connect(_on_round_fired)

func configure_combat(registry_value: ThreatRegistry, _projectile_parent_value: Node3D) -> void:
	registry = registry_value

func c2_link_range() -> float:
	return _definition.c2_range * operational_efficiency()

func gameplay_tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if gunfire != null:
		gunfire.registry = registry
		gunfire.battlefield = battlefield
		if not active or doctrine.hold_fire:
			gunfire.cancel_pending()
		flash_remaining = maxf(0, flash_remaining - delta)
		muzzle_flash.visible = flash_remaining > 0
		muzzle_light.visible = muzzle_flash.visible
		gunfire.gameplay_tick(delta)
	barrel_spin_remaining = maxf(0, barrel_spin_remaining - delta)
	barrel_spin_speed = move_toward(barrel_spin_speed, 28.0 if barrel_spin_remaining > 0 else 0.0, delta * 55.0)
	barrel_cluster.rotation.z = fposmod(barrel_cluster.rotation.z + barrel_spin_speed * delta, TAU)
	if not active or registry == null or player_knowledge == null or c2_network == null:
		maintain_fire_support(null, false)
		return
	magazine.gameplay_tick(delta)
	cooldown = maxf(0.0, cooldown - delta)
	var track := select_track(available_tracks(), battlefield.objective.global_position)
	var has_assignment := maintain_fire_support(track, magazine.can_fire())
	if track == null:
		return
	var flight_time := muzzle.global_position.distance_to(track.estimated_position) / _definition.muzzle_velocity
	var aim_position := track.estimated_position + track.estimated_velocity * flight_time - GunfireRuntime.GRAVITY * flight_time * flight_time * 0.5
	var is_aimed := _aim_turret(aim_position, delta)
	if is_aimed and cooldown <= 0.0 and magazine.can_fire() and has_assignment:
		magazine.consume()
		_fire_burst(track)
		cooldown = _definition.burst_interval

func _aim_turret(target_position: Vector3, delta: float) -> bool:
	return TURRET_AIMER.aim(turret, elevation, target_position, turret_turn_speed_degrees, barrel_elevation_speed_degrees, firing_alignment_degrees, delta, -8.0, 80.0)

func select_track(tracks: Array[PlayerTrack], protected_position: Vector3) -> PlayerTrack:
	var selected: PlayerTrack
	var selected_score := -INF
	for track: PlayerTrack in tracks:
		if not doctrine.allows(track) or weapon_match(track) <= 0:
			continue
		var distance := global_position.distance_to(track.estimated_position)
		if distance > _definition.attack_range * operational_efficiency():
			continue
		if track.track_id == doctrine.priority_track_id:
			return track
		var score := cooperative_target_score(track, protected_position, weapon_match(track))
		if score > selected_score:
			selected = track
			selected_score = score
	return selected

func weapon_match(track: PlayerTrack) -> float:
	return _definition.preferred_target_match if track.classification == _definition.preferred_class else _definition.other_target_match

func resupply_cost() -> int:
	return _definition.resupply_cost

func uses_ammunition() -> bool:
	return true

func resupply_work() -> float:
	return _definition.resupply_work

func _fire_burst(track: PlayerTrack) -> void:
	weapon_fired.emit(self, combat_resource_low())
	if enemy_knowledge != null:
		enemy_knowledge.record_engagement(self, &"gun")
	gunfire.enqueue(muzzle.global_position, track.estimated_position, track.estimated_velocity, track.track_quality, weapon_match(track), _definition, rng)

func _on_round_fired(position: Vector3) -> void:
	barrel_spin_remaining = 0.15
	flash_remaining = 0.014
	muzzle_flash.global_position = position
	muzzle_flash.scale = Vector3.ONE * (0.75 + float(gunfire.rounds.size() % 4) * 0.15)
	muzzle_flash.visible = true
	muzzle_light.global_position = position
	muzzle_light.visible = true

func capture_content_state() -> Dictionary:
	return {
		"cooldown": cooldown,
		"rng_state": str(rng.state),
		"magazine": magazine.capture_state(),
		"doctrine": capture_doctrine_state(),
		"gunfire": gunfire.capture_state(),
	}

func restore_content_state(state: Dictionary) -> void:
	cooldown = float(state.get("cooldown", 0.0))
	rng.state = int(state.get("rng_state", rng.state))
	magazine.restore_state(state.get("magazine", {}))
	restore_doctrine_state(state.get("doctrine", {}))
	gunfire.restore_state(state.get("gunfire", []))
