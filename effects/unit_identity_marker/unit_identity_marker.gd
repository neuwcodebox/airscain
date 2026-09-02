extends Node3D

const SENSOR_ROLE := 1
const COMMAND_ROLE := 2
const DEFENSE_ROLE := 4
const RELAY_ROLE := 8
const SENSOR_COLOR := Color("55d7f2")
const COMMAND_COLOR := Color("8eb8ff")
const DEFENSE_COLOR := Color("75e49a")
const SUPPORT_COLOR := Color("f0c86a")

@onready var icon: Label3D = $Icon

func set_role(roles: int) -> void:
	if icon == null:
		icon = get_node("Icon") as Label3D
	if roles & SENSOR_ROLE:
		icon.text = "◎"
		icon.modulate = SENSOR_COLOR
	elif roles & (COMMAND_ROLE | RELAY_ROLE):
		icon.text = "◆"
		icon.modulate = COMMAND_COLOR
	elif roles & DEFENSE_ROLE:
		icon.text = "▲"
		icon.modulate = DEFENSE_COLOR
	else:
		icon.text = "■"
		icon.modulate = SUPPORT_COLOR
	visible = true
