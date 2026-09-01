class_name WeaponMagazine
extends RefCounted

var capacity: int
var rounds: int
var reserve: int
var reserve_capacity: int
var reload_duration: float
var reload_remaining: float = 0.0

func setup(capacity_value: int, reserve_value: int, reload_duration_value: float) -> void:
	capacity = capacity_value
	rounds = capacity_value
	reserve = reserve_value
	reserve_capacity = reserve_value
	reload_duration = reload_duration_value
	reload_remaining = 0.0

func gameplay_tick(delta: float) -> void:
	if reload_remaining <= 0.0:
		return
	reload_remaining = maxf(0.0, reload_remaining - delta)
	if reload_remaining <= 0.0:
		var loaded := mini(capacity, reserve)
		rounds = loaded
		reserve -= loaded

func can_fire() -> bool:
	return rounds > 0 and reload_remaining <= 0.0

func consume() -> bool:
	if not can_fire():
		return false
	rounds -= 1
	if rounds == 0 and reserve > 0:
		reload_remaining = reload_duration
	return true

func is_reloading() -> bool:
	return reload_remaining > 0.0

func is_depleted() -> bool:
	return rounds <= 0 and reserve <= 0

func refill_reserve() -> void:
	reserve = reserve_capacity
	if rounds == 0 and reload_remaining <= 0.0 and reserve > 0:
		reload_remaining = reload_duration

func capture_state() -> Dictionary:
	return {
		"capacity": capacity,
		"rounds": rounds,
		"reserve": reserve,
		"reserve_capacity": reserve_capacity,
		"reload_duration": reload_duration,
		"reload_remaining": reload_remaining,
	}

func restore_state(state: Dictionary) -> void:
	capacity = int(state.get("capacity", capacity))
	rounds = int(state.get("rounds", rounds))
	reserve = int(state.get("reserve", reserve))
	reserve_capacity = int(state.get("reserve_capacity", reserve_capacity))
	reload_duration = float(state.get("reload_duration", reload_duration))
	reload_remaining = float(state.get("reload_remaining", 0.0))
	if rounds == 0 and reserve > 0 and reload_remaining <= 0.0:
		reload_remaining = reload_duration

static func validation_error(state: Variant) -> String:
	if not state is Dictionary:
		return "탄약 상태가 없습니다"
	var magazine_state := state as Dictionary
	var saved_capacity := int(magazine_state.get("capacity", 0))
	var saved_rounds := int(magazine_state.get("rounds", -1))
	var saved_reserve := int(magazine_state.get("reserve", -1))
	var saved_reserve_capacity := int(magazine_state.get("reserve_capacity", -1))
	var saved_reload_duration := float(magazine_state.get("reload_duration", 0.0))
	var saved_reload_remaining := float(magazine_state.get("reload_remaining", -1.0))
	if saved_capacity <= 0 or saved_rounds < 0 or saved_rounds > saved_capacity or saved_reserve < 0 or saved_reserve_capacity < 0 or saved_reserve > saved_reserve_capacity or saved_reload_duration <= 0.0 or saved_reload_remaining < 0.0 or saved_reload_remaining > saved_reload_duration:
		return "탄약 수량 또는 재장전 상태가 올바르지 않습니다"
	return ""
