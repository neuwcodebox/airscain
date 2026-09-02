class_name UnitStatusMarker
extends Node3D

@onready var label: Label3D = $Label

func set_status(message: String, color: Color) -> void:
	if label == null:
		label = get_node("Label") as Label3D
	visible = not message.is_empty()
	if not visible:
		return
	label.text = message
	label.modulate = color
