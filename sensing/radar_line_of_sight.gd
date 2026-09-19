class_name RadarLineOfSight
extends RefCounted

const SAMPLE_COUNT := 12
const TERRAIN_CLEARANCE := 2.0

static func is_clear(battlefield: Battlefield, from: Vector3, to: Vector3) -> bool:
	if battlefield.building_blocks_segment(from, to):
		return false
	for sample_index: int in range(1, SAMPLE_COUNT):
		var weight := float(sample_index) / float(SAMPLE_COUNT)
		var sample_position := from.lerp(to, weight)
		if battlefield.terrain_height(sample_position.x, sample_position.z) + TERRAIN_CLEARANCE > sample_position.y:
			return false
	return true
