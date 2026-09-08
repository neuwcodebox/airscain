class_name ReconnaissanceFlight
extends RefCounted
## Search flight state, separate from attack/release missions.

const MAX_SECTORS := 8
const MAX_FLIGHT_SECONDS := 600.0
const SCAN_INTERVAL := 0.5
var elapsed: float = 0.0
var scan_remaining: float = 0.0
var completed_sectors: int = 0
var surveying: bool = false
var dwell_remaining: float = 0.0
var orbit_angle: float = 0.0

func advance(unit: AttackUav, delta: float) -> void:
	var knowledge := unit.enemy_knowledge
	var mission := unit.mission_runtime
	elapsed += delta
	if knowledge == null or elapsed >= MAX_FLIGHT_SECONDS:
		mission.phase = ThreatMissionRuntime.Phase.EGRESS
	if mission.phase != ThreatMissionRuntime.Phase.EGRESS:
		# Old saves may contain an omniscient asset waypoint. Replace it on entry.
		mission.target_asset = null
		mission.target_defense_id = 0
		mission.fixed_target = knowledge.search_target(unit.runtime_id, unit.global_position)
		mission.phase = ThreatMissionRuntime.Phase.ACTING
		var offset := mission.fixed_target - unit.global_position
		if not surveying and Vector2(offset.x, offset.z).length() <= 30.0:
			surveying = true
			dwell_remaining = 4.0
			orbit_angle = atan2(-offset.z, -offset.x)
		if surveying:
			dwell_remaining = maxf(0.0, dwell_remaining - delta)
			orbit_angle = fposmod(orbit_angle + delta * 0.85, TAU)
			if dwell_remaining <= 0.0:
				var cell := knowledge.search.assignments.get(unit.runtime_id, -1) as int
				if cell >= 0:
					knowledge.search.attempted[cell] = knowledge.simulation_time
				knowledge.search.release(unit.runtime_id)
				completed_sectors += 1
				surveying = false
				if completed_sectors >= MAX_SECTORS:
					mission.effect_applied = true
					mission.phase = ThreatMissionRuntime.Phase.EGRESS
				else:
					mission.fixed_target = knowledge.search_target(unit.runtime_id, unit.global_position)
	if knowledge != null and mission.phase == ThreatMissionRuntime.Phase.EGRESS:
		knowledge.search.release(unit.runtime_id)
	unit.target_point = mission.navigation_target()
	var navigation := unit.target_point
	if surveying and mission.phase != ThreatMissionRuntime.Phase.EGRESS:
		navigation += Vector3(cos(orbit_angle) * 45.0, 0.0, sin(orbit_angle) * 45.0)
	var previous := unit.global_position
	unit.mover.advance(unit, unit.body, navigation, unit.speed_multiplier, delta, true)
	unit._sample_exhaust(previous, unit.global_position)
	if knowledge != null:
		scan_remaining -= delta
		if scan_remaining <= 0.0:
			scan_remaining = SCAN_INTERVAL
			knowledge.record_recon_area(unit.global_position, mission.profile.action_distance, SCAN_INTERVAL)
	if mission.phase == ThreatMissionRuntime.Phase.EGRESS and unit.global_position.distance_to(mission.exit_point) <= maxf(85.0, unit.mover.profile.cruise_altitude * 1.5):
		unit.resolve_once(false)

func capture_state() -> Dictionary:
	return {"elapsed": elapsed, "scan_remaining": scan_remaining, "completed_sectors": completed_sectors, "surveying": surveying, "dwell_remaining": dwell_remaining, "orbit_angle": orbit_angle}

func restore_state(state: Dictionary) -> void:
	elapsed = float(state.get("elapsed", 0.0))
	scan_remaining = float(state.get("scan_remaining", 0.0))
	completed_sectors = int(state.get("completed_sectors", 0))
	surveying = bool(state.get("surveying", false))
	dwell_remaining = float(state.get("dwell_remaining", 0.0))
	orbit_angle = float(state.get("orbit_angle", 0.0))

static func validation_error(state: Dictionary) -> String:
	for key: String in ["elapsed", "scan_remaining", "dwell_remaining"]:
		var value := float(state.get(key, 0.0))
		if not is_finite(value) or value < 0.0:
			return "정찰 비행 시간이 올바르지 않습니다"
	if not state.get("surveying", false) is bool or not is_finite(float(state.get("orbit_angle", 0.0))) or float(state.get("dwell_remaining", 0.0)) > 4.0:
		return "정찰 체공 상태가 올바르지 않습니다"
	if float(state.get("scan_remaining", 0.0)) > SCAN_INTERVAL or int(state.get("completed_sectors", 0)) < 0 or int(state.get("completed_sectors", 0)) > MAX_SECTORS:
		return "정찰 구역 진행 상태가 올바르지 않습니다"
	return ""
