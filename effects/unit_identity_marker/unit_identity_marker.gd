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
const DAMAGED_FRAME := preload("res://effects/unit_identity_marker/condition_damaged.svg")
const DISABLED_FRAME := preload("res://effects/unit_identity_marker/condition_disabled.svg")

@onready var icon: Sprite3D = $Icon
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var reload_background: Sprite3D = $ReloadBackground
@onready var reload_fill: Sprite3D = $ReloadFill
@onready var condition_frame: Sprite3D = $ConditionFrame

var selected: bool = false
var role_color := DEFENSE_COLOR
var operational: bool = true
var damaged: bool = false

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

func configure(texture: Texture2D, roles: int) -> void:
	if icon == null:
		icon = get_node("Icon") as Sprite3D
	icon.texture = texture
	if roles & SENSOR_ROLE:
		icon.modulate = SENSOR_COLOR
	elif roles & (COMMAND_ROLE | RELAY_ROLE):
		icon.modulate = COMMAND_COLOR
	elif roles & DEFENSE_ROLE:
		icon.modulate = DEFENSE_COLOR
	else:
		icon.modulate = SUPPORT_COLOR
	role_color = icon.modulate
	visible = true
	_apply_selection()

func set_selected(enabled: bool) -> void:
	selected = enabled
	_apply_selection()

func set_condition(is_operational: bool, is_damaged: bool) -> void:
	if operational == is_operational and damaged == is_damaged:
		return
	operational = is_operational
	damaged = is_damaged
	if condition_frame == null:
		condition_frame = get_node("ConditionFrame") as Sprite3D
	condition_frame.texture = DISABLED_FRAME if not operational else DAMAGED_FRAME
	condition_frame.visible = not operational or damaged
	icon.modulate = role_color if operational else Color(role_color.r * 0.38, role_color.g * 0.38, role_color.b * 0.38, 1.0)

func status_half_width() -> float:
	var boundary := condition_frame if is_instance_valid(condition_frame) and condition_frame.visible else icon
	return boundary.texture.get_width() * 0.5 * boundary.pixel_size * boundary.scale.x

func set_reload(magazine: WeaponMagazine) -> void:
	if reload_background == null:
		reload_background = get_node("ReloadBackground") as Sprite3D
		reload_fill = get_node("ReloadFill") as Sprite3D
	var reloading := magazine != null and magazine.is_reloading() and not magazine.is_depleted()
	reload_background.visible = reloading
	reload_fill.visible = reloading
	if not reloading:
		return
	var progress := clampf(1.0 - magazine.reload_remaining / magazine.reload_duration, 0.0, 1.0)
	var width := 40.0 * progress
	reload_fill.region_rect = Rect2(0, 0, width, 2)
	reload_fill.offset = Vector2((width - 40.0) * 0.5, -29)
	reload_fill.visible = width > 0.0

func _apply_selection() -> void:
	if icon == null or selection_ring == null:
		return
	selection_ring.visible = selected
	icon.scale = Vector3.ONE * (1.2 if selected else 1.0)
	reload_background.scale = icon.scale
	reload_fill.scale = icon.scale
	condition_frame.scale = icon.scale
