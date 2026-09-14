class_name TacticalReloadController
extends RefCounted

const CONFIRMATION_DURATION := 5.0
const SAFETY_MARGIN := 3.0
const EVALUATION_INTERVAL := 0.5

var _clear_times: Dictionary[StringName, float] = {}
var _evaluation_remaining: float = 0.0
var _elapsed_since_evaluation: float = 0.0

func configure(runtime_id: int) -> void:
	_clear_times.clear()
	_elapsed_since_evaluation = 0.0
	_evaluation_remaining = _radical_inverse_base_two(maxi(0, runtime_id - 1)) * EVALUATION_INTERVAL

func take_evaluation_delta(delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	_elapsed_since_evaluation += delta
	_evaluation_remaining -= delta
	if _evaluation_remaining > 0.0:
		return 0.0
	var evaluation_delta := _elapsed_since_evaluation
	_elapsed_since_evaluation = 0.0
	_evaluation_remaining = fposmod(_evaluation_remaining, EVALUATION_INTERVAL)
	if is_zero_approx(_evaluation_remaining):
		_evaluation_remaining = EVALUATION_INTERVAL
	return evaluation_delta

func evaluate_magazine(magazine_id: StringName, magazine: WeaponMagazine, delta: float, origin: Vector3, tracks: Array[PlayerTrack], engagement_range: float, hold_fire: bool, target_filter: Callable) -> void:
	if not magazine.can_start_tactical_reload() or hold_fire:
		_clear_times[magazine_id] = 0.0
		return
	var horizon := magazine.reload_duration + SAFETY_MARGIN
	for track: PlayerTrack in tracks:
		if bool(target_filter.call(track)) and _track_reaches_range_within(track, origin, engagement_range, horizon):
			_clear_times[magazine_id] = 0.0
			return
	var clear_time := float(_clear_times.get(magazine_id, 0.0)) + delta
	if clear_time >= CONFIRMATION_DURATION:
		magazine.start_tactical_reload()
		clear_time = 0.0
	_clear_times[magazine_id] = clear_time

func _track_reaches_range_within(track: PlayerTrack, origin: Vector3, engagement_range: float, horizon: float) -> bool:
	var offset := track.estimated_position - origin
	if offset.length_squared() <= engagement_range * engagement_range:
		return true
	var speed_squared := track.estimated_velocity.length_squared()
	if speed_squared <= 0.000001:
		return false
	var closest_time := clampf(-offset.dot(track.estimated_velocity) / speed_squared, 0.0, horizon)
	return (offset + track.estimated_velocity * closest_time).length_squared() <= engagement_range * engagement_range

func _radical_inverse_base_two(index: int) -> float:
	var result := 0.0
	var place_value := 0.5
	while index > 0:
		result += float(index & 1) * place_value
		index >>= 1
		place_value *= 0.5
	return result
