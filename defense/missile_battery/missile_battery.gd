class_name MissileBattery
extends DefenseUnit

const INTERCEPTOR_SCENE := preload("res://defense/missile_battery/homing_interceptor.tscn")

var registry: ThreatRegistry
var projectile_parent: Node3D
var cooldown: float = 0.0
var _definition: MissileBatteryDefinition

@onready var turret: Node3D = $Turret
@onready var launch_point: Marker3D = $Turret/LaunchPoint

func setup(id_value: int, definition_value: DefenseDefinition) -> void:
	super.setup(id_value, definition_value)
	_definition = definition_value as MissileBatteryDefinition

func configure_combat(registry_value: ThreatRegistry, projectile_parent_value: Node3D) -> void:
	registry = registry_value
	projectile_parent = projectile_parent_value

func gameplay_tick(delta: float) -> void:
	if not active or registry == null:
		return
	cooldown = maxf(0.0, cooldown - delta)
	var target := select_target(registry.get_active())
	if target == null:
		return
	var flat_target := Vector3(target.global_position.x, turret.global_position.y, target.global_position.z)
	if turret.global_position.distance_squared_to(flat_target) > 0.01:
		turret.look_at(flat_target, Vector3.UP)
	if cooldown <= 0.0:
		_launch(target)
		cooldown = _definition.fire_interval

func select_target(threats: Array[ThreatUnit]) -> ThreatUnit:
	var selected: ThreatUnit = null
	var selected_urgency := -INF
	var selected_distance := INF
	for threat: ThreatUnit in threats:
		if not threat.is_targetable():
			continue
		var distance := global_position.distance_to(threat.get_aim_position())
		if distance > _definition.attack_range:
			continue
		var urgency := threat.get_urgency()
		if urgency > selected_urgency or (is_equal_approx(urgency, selected_urgency) and distance < selected_distance):
			selected = threat
			selected_urgency = urgency
			selected_distance = distance
	return selected

func _launch(target: ThreatUnit) -> void:
	var interceptor := INTERCEPTOR_SCENE.instantiate() as HomingInterceptor
	projectile_parent.add_child(interceptor)
	interceptor.global_position = launch_point.global_position
	var initial_direction := launch_point.global_position.direction_to(target.get_aim_position())
	interceptor.configure(target, _definition, initial_direction)
	$MuzzleFlash.visible = true
	get_tree().create_timer(0.08).timeout.connect(func() -> void: $MuzzleFlash.visible = false)
