class_name ThreatSpawnEntry
extends Resource

enum RaidRole { STRIKE, RECON, DECEPTION, SUPPRESSION }
enum AttackLayer { LOW, HIGH }

@export var threat_definition: ThreatDefinition
@export var unlock_level: int = 1
@export var selection_weight: float = 1.0
@export var group_size: int = 1
@export var threat_cost: float = 1.0
@export var raid_role := RaidRole.STRIKE
@export var attack_layer := AttackLayer.LOW

func validation_error() -> String:
	if threat_definition == null:
		return "위협 spawn 항목에 Definition이 없습니다"
	if unlock_level < 1 or selection_weight <= 0.0 or group_size < 1 or threat_cost <= 0.0:
		return "위협 spawn 해금 단계 또는 가중치가 올바르지 않습니다"
	if raid_role not in RaidRole.values() or attack_layer not in AttackLayer.values():
		return "공습 역할 또는 고도 계층이 올바르지 않습니다"
	return threat_definition.validation_error()
