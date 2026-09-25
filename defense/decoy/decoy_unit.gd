class_name DecoyUnit
extends DefenseUnit

signal destroyed(unit: DecoyUnit)

var emission_remaining: float = 0.0

func gameplay_tick(delta: float) -> void:
	if not active or definition.enemy_knowledge_role() != &"sensor" or enemy_knowledge == null:
		return
	emission_remaining -= delta
	if emission_remaining <= 0.0:
		emission_remaining += 0.4
		enemy_knowledge.record_emission(self)

func receive_damage(amount: float) -> bool:
	if amount <= 0.0 or not active:
		return false
	integrity = 0.0
	active = false
	damage_received.emit(self, amount, 0.0)
	destroyed.emit(self)
	return true

func can_request_repair() -> bool:
	return false
