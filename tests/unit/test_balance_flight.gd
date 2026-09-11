extends GutTest

class FlatField:
	extends Battlefield
	func flight_surface_height(_x: float, _z: float) -> float:
		return 0.0

func test_strike_egress_preserves_position_and_vertical_acceleration() -> void:
	var field := autofree(FlatField.new()) as FlatField
	var parent := add_child_autofree(Node3D.new()) as Node3D
	for path: String in ["strike_aircraft", "battery_strike_aircraft", "radar_strike_aircraft", "command_strike_aircraft"]:
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
		assert_lt(unit.position.distance_to(before), speed.length() * 0.03, "이탈은 위치를 안전 고도로 순간 이동하지 않는다")
		assert_lt(absf(mover.velocity.y - speed.y), definition.movement.maximum_climb_rate * 0.02)
		assert_lt(mover.velocity.y, 0.0, "하강 속도를 즉시 0으로 자르지 않는다")
		assert_lt(definition.mission.action_distance, definition.movement.terminal_distance)
