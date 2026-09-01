class_name ThreatRegistry
extends RefCounted

var _active: Array[ThreatUnit] = []

func add(threat: ThreatUnit) -> void:
	if not _active.has(threat):
		_active.append(threat)

func remove(threat: ThreatUnit) -> void:
	_active.erase(threat)

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

func clear() -> void:
	_active.clear()
