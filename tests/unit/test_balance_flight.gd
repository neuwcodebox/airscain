extends GutTest

class FlatField:
	extends Battlefield
	func flight_surface_height(_x: float, _z: float) -> float:
		return 0.0

const STRIKE_PROFILE_PATHS: Array[String] = [
	"strike_aircraft",
	"battery_strike_aircraft",
	"radar_strike_aircraft",
]

func test_strike_egress_preserves_position_and_vertical_acceleration() -> void:
	var field := autofree(FlatField.new()) as FlatField
	var parent := add_child_autofree(Node3D.new()) as Node3D
	for path: String in STRIKE_PROFILE_PATHS:
		var definition := load("res://enemy/strike_aircraft/%s.tres" % path) as AttackUavDefinition
		var unit := Node3D.new()
		parent.add_child(unit)
		var body := Node3D.new()
		unit.add_child(body)
		unit.position = Vector3(500, definition.movement.cruise_altitude * 0.2, 0)
		var mover := ThreatMover.new()
		mover.setup(definition.movement, field, Vector3.LEFT)
		mover.velocity.y = -30.0
		var before := unit.position
		var speed := mover.velocity
		mover.advance(unit, body, Vector3(1800, definition.movement.cruise_altitude, 0), 1.0, 0.02, true)
		assert_lt(unit.position.distance_to(before), speed.length() * 0.03, "%s 이탈은 위치를 안전 고도로 순간 이동하지 않는다" % path)
		assert_lt(absf(mover.velocity.y - speed.y), definition.movement.maximum_climb_rate * 0.02, "%s 수직 가속은 상승률 한계를 지킨다" % path)
		assert_lt(mover.velocity.y, 0.0, "%s 하강 속도를 즉시 0으로 자르지 않는다" % path)

func test_strike_profiles_begin_actions_before_terminal_approach() -> void:
	for path: String in STRIKE_PROFILE_PATHS:
		var definition := load("res://enemy/strike_aircraft/%s.tres" % path) as AttackUavDefinition
		assert_lt(definition.mission.action_distance, definition.movement.terminal_distance, "%s 행동은 종말 접근 전에 시작한다" % path)

func test_flight_rules_run_without_scene_visuals_and_restore_continuously() -> void:
	var original := StrikeFlight.new()
	original.mode = StrikeFlight.Mode.BOMB
	original.velocity = Vector3(40, 0, 0)
	var position := Vector3(0, 100, 0)
	var target := Vector3(180, 0, 0)
	position = original.advance(position, target, null, 0.25)
	var restored := StrikeFlight.new()
	restored.restore_state(original.capture_state())
	for tick: int in 60:
		var expected := original.advance(position, target, null, StrikeFlight.MAXIMUM_STEP)
		var actual := restored.advance(position, target, null, StrikeFlight.MAXIMUM_STEP)
		assert_eq(actual, expected)
		assert_eq(restored.velocity, original.velocity)
		position = expected
	assert_false(original.powered())
	assert_lt(original.velocity.y, 0.0)


func test_low_altitude_missile_flies_level_before_terminal_descent() -> void:
	var flight := StrikeFlight.new()
	flight.mode = StrikeFlight.Mode.MISSILE
	flight.speed = 145.0
	flight.acceleration = 16.0
	flight.velocity = Vector3(-104.0, 0.0, 0.0)
	var position := Vector3(440.0, 65.0, 0.0)
	var target := Vector3.ZERO
	var highest_altitude := position.y
	var entered_terminal_descent := false
	for tick: int in 600:
		position = flight.advance(position, target, null, StrikeFlight.MAXIMUM_STEP)
		highest_altitude = maxf(highest_altitude, position.y)
		if Vector2(position.x, position.z).length() <= StrikeFlight.MISSILE_TERMINAL_DISTANCE:
			entered_terminal_descent = true
		if flight.result != StrikeFlight.Result.FLYING:
			break
	assert_lte(highest_altitude, 70.0, "저공 투발 직후 하늘로 솟지 않습니다")
	assert_true(entered_terminal_descent, "표적 가까이에서 종말 하강을 시작합니다")
	assert_eq(flight.result, StrikeFlight.Result.IMPACT)
