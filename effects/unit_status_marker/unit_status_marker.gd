class_name UnitStatusMarker
extends Node3D

const SUPPLY_TEXTURES: Dictionary[StringName, Texture2D] = {
	&"resupply_waiting": preload("res://effects/unit_status_marker/resupply_waiting.svg"),
	&"resupply_active": preload("res://effects/unit_status_marker/resupply_active.svg"),
	&"ammunition_empty": preload("res://effects/unit_status_marker/ammunition_empty.svg"),
	&"ammunition_partial": preload("res://effects/unit_status_marker/ammunition_partial.svg"),
}

@onready var supply_badge: Sprite3D = $SupplyBadge
@onready var obstruction_badge: Sprite3D = $ObstructionBadge

func set_clearance(half_width: float) -> void:
	_resolve_badges()
	var horizontal := half_width / supply_badge.pixel_size + 12.0 + 2.0
	supply_badge.offset.x = horizontal
	obstruction_badge.offset.x = -horizontal

func _resolve_badges() -> void:
	if supply_badge == null:
		supply_badge = get_node("SupplyBadge") as Sprite3D
		obstruction_badge = get_node("ObstructionBadge") as Sprite3D

func set_status(supply: StringName, obstructed: bool) -> void:
	_resolve_badges()
	supply_badge.texture = SUPPLY_TEXTURES.get(supply)
	supply_badge.visible = supply_badge.texture != null
	obstruction_badge.visible = obstructed
	visible = supply_badge.visible or obstructed
