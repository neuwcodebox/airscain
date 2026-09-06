extends Node3D

const SENSOR_ROLE := 1
const COMMAND_ROLE := 2
const DEFENSE_ROLE := 4
const RELAY_ROLE := 8
const SENSOR_COLOR := Color("55d7f2")
const COMMAND_COLOR := Color("8eb8ff")
const DEFENSE_COLOR := Color("75e49a")
const SUPPORT_COLOR := Color("f0c86a")
const SELECTION_COLOR := Color(0.26, 0.9, 1.0, 0.92)

@onready var icon: Label3D = $Icon
@onready var detail: Label3D = $Detail
@onready var selection_ring: MeshInstance3D = $SelectionRing

var selected: bool = false

func _ready() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 10.0
	ring.outer_radius = 11.5
	ring.rings = 64
	ring.ring_segments = 8
	selection_ring.mesh = ring
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = SELECTION_COLOR
	selection_ring.material_override = material
	_apply_selection()

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
	_apply_selection()

func set_detail(count: int, symbol: String = "") -> void:
	if detail == null:
		detail = get_node("Detail") as Label3D
	detail.text = ""
	for index: int in clampi(count, 0, 3):
		detail.text += "|" if index == 0 else " |"
	if not symbol.is_empty():
		detail.text = symbol
	detail.offset = Vector2(0, 12) if symbol.is_empty() else Vector2.ZERO
	detail.font_size = 12 if symbol.is_empty() else 16
	# A radial sweep ends at the center; a full diagonal would read as disabled.
	if symbol == "/":
		detail.font_size = 8
		detail.offset = Vector2(2, 2)
	detail.outline_size = 4 if symbol.is_empty() else 0
	detail.modulate = icon.modulate
	detail.visible = not detail.text.is_empty()

func set_selected(enabled: bool) -> void:
	selected = enabled
	_apply_selection()

func _apply_selection() -> void:
	if icon == null or selection_ring == null:
		return
	selection_ring.visible = selected
	icon.outline_size = 8 if selected else 4
	icon.scale = Vector3.ONE * (1.2 if selected else 1.0)
	if detail.offset.y == 12.0:
		detail.outline_size = icon.outline_size
	detail.scale = icon.scale
