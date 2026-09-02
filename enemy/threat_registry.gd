class_name ThreatRegistry
extends RefCounted

signal threat_removed(threat: ThreatUnit)

var _active: Array[ThreatUnit] = []
var _jammers: Array[ThreatUnit] = []

func add(threat: ThreatUnit) -> void:
	if not _active.has(threat):
		_active.append(threat)
		if threat.definition.jamming_strength > 0.0:
			_jammers.append(threat)

func remove(threat: ThreatUnit) -> void:
	var was_registered := _active.has(threat)
	_active.erase(threat)
	_jammers.erase(threat)
	if was_registered:
		threat_removed.emit(threat)

func get_active() -> Array[ThreatUnit]:
	var result: Array[ThreatUnit] = []
	for threat: ThreatUnit in _active:
		if is_instance_valid(threat) and threat.is_targetable():
			result.append(threat)
	return result

func count() -> int:
	return get_active().size()

func get_hostile_active() -> Array[ThreatUnit]:
	var result: Array[ThreatUnit] = []
	for threat: ThreatUnit in get_active():
		if threat.definition.affiliation == ThreatDefinition.Affiliation.HOSTILE:
			result.append(threat)
	return result

func hostile_count() -> int:
	return get_hostile_active().size()

func jamming_at(position: Vector3) -> float:
	var strongest := 0.0
	for threat: ThreatUnit in _jammers:
		if not is_instance_valid(threat) or not threat.is_targetable():
			continue
		var definition := threat.definition
		if definition.affiliation != ThreatDefinition.Affiliation.HOSTILE or definition.jamming_strength <= 0.0 or definition.jamming_range <= 0.0:
			continue
		var distance := position.distance_to(threat.global_position)
		if distance >= definition.jamming_range:
			continue
		var falloff := 1.0 - distance / definition.jamming_range
		strongest = maxf(strongest, definition.jamming_strength * falloff)
	return strongest

func clear() -> void:
	_active.clear()
	_jammers.clear()
