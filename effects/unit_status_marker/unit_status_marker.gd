class_name UnitStatusMarker
extends Node3D

const RESUPPLY_WAITING := preload("res://effects/unit_status_marker/resupply_waiting.svg")
const RESUPPLY_ACTIVE := preload("res://effects/unit_status_marker/resupply_active.svg")

@onready var label: Label3D = $Label
@onready var badge: Sprite3D = $Badge

func set_status(message: String, color: Color) -> void:
	if label == null:
		label = get_node("Label") as Label3D
		badge = get_node("Badge") as Sprite3D
	visible = not message.is_empty()
	var texture: Texture2D
	if message == "재보급 대기":
		texture = RESUPPLY_WAITING
	elif message == "재보급 중":
		texture = RESUPPLY_ACTIVE
	badge.texture = texture
	badge.visible = texture != null and visible
	label.visible = texture == null and visible
	label.text = message
	if not visible:
		return
	label.modulate = color
